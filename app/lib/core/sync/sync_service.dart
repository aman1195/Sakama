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
    // BEFORE anything reads. PowerSync created these tables without defaults,
    // so a column an older build never wrote is stored NULL and the generated
    // mapper's `!` turns one bad row into a permanently broken screen.
    await _drift!.repairMissingDefaults();
    return _drift!;
  }

  /// Attach replication. Safe to call anytime: no-ops until the app is
  /// configured, initialized, and signed in.
  /// How long to wait before retrying a failed sync connection.
  ///
  /// PowerSync's default is 5 seconds with NO backoff and no ceiling, which is
  /// fine for a momentary blip and wasteful for anything longer: an instance
  /// that is down, deprovisioned (free projects deactivate after a week idle),
  /// or simply unreachable produces a radio wake-up every 5 seconds for as long
  /// as the app is open. 30s still reconnects promptly on a real outage while
  /// costing a sixth of the wake-ups — this is a phone, and battery is a
  /// first-class performance metric (docs/MOBILE.md).
  static const retryDelay = Duration(seconds: 30);

  Future<void> connect() async {
    final db = _psDb;
    if (db == null || !syncConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    await db.connect(
      connector: SupabaseConnector(),
      options: const SyncOptions(retryDelay: retryDelay),
    );
  }

  Future<void> disconnect() async => _psDb?.disconnect();

  /// User switch / sign-out: local synced data belongs to the OLD identity and
  /// must not leak to the next signer-in.
  ///
  /// ⚠️ DESTRUCTIVE: this also deletes the PENDING UPLOAD QUEUE (ps_crud) —
  /// any row written offline that has not yet uploaded is gone, locally and
  /// irrecoverably. Correct for the dev harness and the isolation test; the
  /// M1 auth flow must decide deliberately between plain disconnect()
  /// (same-user re-login, keeps data) and a bounded drain-then-clear for real
  /// user switches. Tracked as an M1 design decision.
  /// [clearLocal] false preserves LOCAL-ONLY tables (Vita conversations, which
  /// have no server copy to restore from). Callers clear those explicitly, and
  /// only after a CONFIRMED identity change — docs/architecture/06 §2a.
  Future<void> disconnectAndClear({bool clearLocal = true}) async =>
      _psDb?.disconnectAndClear(clearLocal: clearLocal);

  /// Test/orchestration seams. Fail loudly if the database was never opened —
  /// a null no-op here would make "queue drained" / "first sync done" pass
  /// vacuously in a test that forgot open().
  Future<void> waitForFirstSync() => _requireDb().waitForFirstSync();
  Future<int> uploadQueueCount() async =>
      (await _requireDb().getUploadQueueStats()).count;

  PowerSyncDatabase _requireDb() {
    final db = _psDb;
    if (db == null) {
      throw StateError('SyncService.open() must be called first');
    }
    return db;
  }
}
