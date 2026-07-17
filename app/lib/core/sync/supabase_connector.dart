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
    try {
      for (final op in tx.crud) {
        final table = rest.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert({...?op.opData, 'id': op.id});
          case UpdateType.patch:
            await table.update(op.opData ?? {}).eq('id', op.id);
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
        }
      }
      await tx.complete();
    } on PostgrestException catch (e) {
      if (e.code != null && _fatal.hasMatch(e.code!)) {
        await tx.complete(); // poison op: drop it, keep the queue moving
      } else {
        rethrow; // transient (network/5xx): PowerSync retries with backoff
      }
    }
  }
}
