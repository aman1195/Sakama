import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import '../db/powersync_schema.dart';
import '../env/env.dart';
import 'supabase_connector.dart';

/// Owns the local database and, when configured, the sync pipeline (ADR 0003).
///
/// The PowerSyncDatabase is ALWAYS the local store — it works fully offline
/// with no server, which keeps one database path for both modes.
/// `connect()` attaches replication only when .env has real project values
/// AND a user session exists. CLAUDE.md rule 1: the UI reads Drift; it never
/// touches the network.
class SyncService {
  PowerSyncDatabase? _psDb;
  SakamaDatabase? _drift;

  bool get syncConfigured => Env.isConfigured;

  Future<SakamaDatabase> open() async {
    if (_drift != null) return _drift!;
    final dir = await getApplicationSupportDirectory();
    _psDb = PowerSyncDatabase(
      schema: powersyncSchema,
      path: p.join(dir.path, 'sakama.db'),
    );
    await _psDb!.initialize();
    // PowerSync owns the physical schema (views over synced data), so Drift
    // must NOT run CREATE TABLE — hence managedExternally.
    _drift = SakamaDatabase.withExecutor(
      DatabaseConnection.delayed(
        Future.value(SqliteAsyncDriftConnection(_psDb!)),
      ),
      managedExternally: true,
    );
    return _drift!;
  }

  /// Attach replication. Safe to call anytime: no-ops until the app is
  /// configured, initialized, and signed in.
  Future<void> connect() async {
    final db = _psDb;
    if (db == null || !syncConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    await db.connect(connector: SupabaseConnector());
  }

  Future<void> disconnect() async => _psDb?.disconnect();
}
