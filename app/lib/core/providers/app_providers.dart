import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../sync/sync_service.dart';

/// Singleton sync service; owns the database and the replication lifecycle.
final syncServiceProvider = Provider<SyncService>((ref) => SyncService());

/// The one database handle the UI reads (offline-first, CLAUDE.md rule 1).
/// Overridden with an in-memory instance in widget tests.
final databaseProvider = FutureProvider<SakamaDatabase>((ref) async {
  final sync = ref.watch(syncServiceProvider);
  final db = await sync.open();
  await sync.connect(); // no-op until configured + signed in
  return db;
});
