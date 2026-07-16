import '../env/env.dart';

/// PowerSync <-> Supabase wiring lands here (ADR 0003), seeded from the CC0
/// `supabase-todolist-drift` demo (docs/references/BY-MODULE.md).
///
/// Until `.env` carries real project values this is a deliberate no-op:
/// offline-first (CLAUDE.md rule 1) means the app is fully usable local-only.
class SyncService {
  bool get enabled => Env.isConfigured;

  Future<void> connect() async {
    if (!enabled) return; // local-only mode
    // M0b: PowerSyncDatabase.connect(connector: SupabaseConnector(...))
  }
}
