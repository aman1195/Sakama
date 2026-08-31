import 'dart:developer' as dev;

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';
import 'sync_failure_repository.dart';

/// PowerSync <-> Supabase bridge, ported from the CC0 `supabase-todolist-drift`
/// demo (docs/references/BY-MODULE.md). Downloads ride PowerSync's replication;
/// this class handles auth handoff and the UPLOAD side of local writes.
class SupabaseConnector extends PowerSyncBackendConnector {
  /// Postgres errors where retrying the same op can never succeed — the op is
  /// discarded (the row stays locally; RLS/constraints rejected it upstream).
  /// Retrying forever would wedge the upload queue behind a poison message.
  ///
  /// Auth-transients do NOT land here: an expired/invalid JWT surfaces as an
  /// AuthException or a PGRST3xx code, neither of which matches — those
  /// rethrow into PowerSync's retry/backoff and recover after token refresh.
  static final _fatal = RegExp(r'^(22...|23...|42501)$');

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null; // signed out -> sync paused, app stays local
    return PowerSyncCredentials(
      endpoint: Env.powersyncUrl,
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final tx = await database.getNextCrudTransaction();
    if (tx == null) return;

    final rest = Supabase.instance.client;
    // Poison handling is PER-OP: one fatally-rejected op must not take its
    // innocent transaction-mates down with it (a whole-loop try/catch would
    // ack the transaction and silently discard every op after the bad one).
    // On a TRANSIENT error we rethrow mid-loop instead: the whole transaction
    // retries, and re-sending the already-sent prefix is safe because every
    // verb here is idempotent (upsert / update-by-id / delete-by-id).
    for (final op in tx.crud) {
      try {
        final table = rest.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert({...?op.opData, 'id': op.id});
          case UpdateType.patch:
            await table.update(op.opData ?? {}).eq('id', op.id);
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
        }
      } on PostgrestException catch (e) {
        if (e.code != null && _fatal.hasMatch(e.code!)) {
          // NEVER SILENT — and a log line is not enough.
          //
          // Dropping the op is right (retrying forever wedges the queue), but
          // on its own it made data loss invisible: the local write succeeded,
          // the UI said so, the op was discarded, and the next checkpoint
          // reconciled the row away. Three weeks of meals went that way before
          // a human noticed (#148), because `dev.log` reaches nobody in a
          // release build.
          //
          // So the receipt is PERSISTED, with the payload, which is what makes
          // the loss visible in the UI and the row recoverable once the cause
          // is fixed.
          await _recordFailure(database, op, e);
          dev.log(
            'dropping poison op ${op.op.name} ${op.table}/${op.id}: '
            '${e.code} ${e.message}',
            name: 'sakama.sync',
            level: 1000, // SEVERE
          );
          continue; // drop THIS op only; keep the rest of the transaction
        }
        rethrow; // transient (network/5xx/auth): PowerSync retries with backoff
      }
    }
    await tx.complete();
  }

  /// Persist a receipt for an op we are about to throw away.
  ///
  /// Guarded, and deliberately: this runs while handling a failure, and a
  /// failure to record a failure must not take down the upload loop or mask
  /// the original error. Losing the receipt is bad; losing the rest of the
  /// transaction because bookkeeping threw would be worse.
  Future<void> _recordFailure(
      PowerSyncDatabase database, CrudEntry op, PostgrestException e) async {
    try {
      final stmt = SyncFailureStatement.build(
        // PowerSync's own id for this op, so a retry of the same transaction
        // updates its receipt instead of writing another one.
        clientId: op.clientId,
        table: op.table,
        op: op.op.name,
        rowId: op.id,
        code: e.code,
        message: e.message,
        payload: op.opData,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      await database.execute(stmt.sql, stmt.params);
    } catch (recordError) {
      dev.log('could not record dropped op: $recordError',
          name: 'sakama.sync', level: 1000);
    }
  }
}
