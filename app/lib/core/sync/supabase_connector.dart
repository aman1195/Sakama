import 'dart:developer' as dev;

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';

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
          // Never silent: a dropped health-data write must be diagnosable.
          // TODO(observability): count these once analytics exists (no PII).
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
}
