import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/capture/data/food_log_repository.dart';
import '../../features/foods/data/food_repository.dart';
import '../../features/onboarding/data/profile_repository.dart';
import '../../features/water/data/water_repository.dart';
import '../../features/weight/data/weight_repository.dart';
import '../../features/onboarding/domain/profile_record.dart';
import '../config/remote_config.dart';
import '../config/remote_config_service.dart';
import '../db/database.dart';
import '../sync/sync_service.dart';

/// Singleton sync service; owns the database and the replication lifecycle.
final syncServiceProvider = Provider<SyncService>((ref) => SyncService());

/// Current signed-in user id, or null. Reads the Supabase session, but returns
/// null (rather than throwing) when Supabase is not initialized — so the app
/// works offline pre-auth AND the controllers that read it stay unit-testable
/// without the whole auth stack. Overridable in tests.
final currentUserIdProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentSession?.user.id;
  } catch (_) {
    return null; // not initialized
  }
});

/// The one database handle the UI reads (offline-first, CLAUDE.md rule 1).
/// Overridden with an in-memory instance in widget tests.
final databaseProvider = FutureProvider<SakamaDatabase>((ref) async {
  final sync = ref.watch(syncServiceProvider);
  final db = await sync.open();
  await sync.connect(); // no-op until configured + signed in
  return db;
});

final profileRepositoryProvider = FutureProvider<ProfileRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ProfileRepository(db);
});

final foodLogRepositoryProvider = FutureProvider<FoodLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FoodLogRepository(db);
});

final waterRepositoryProvider = FutureProvider<WaterRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WaterRepository(db);
});

final weightRepositoryProvider = FutureProvider<WeightRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WeightRepository(db);
});

/// The food reference repository, seeded on first access (idempotent). The
/// seed is a labelled sample today; real INDB/USDA ingestion lands in M2.2.
final foodRepositoryProvider = FutureProvider<FoodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final repo = FoodRepository(db);
  await repo.ensureSeeded();
  return repo;
});

/// The persisted profile, live. Null until onboarding writes it.
final profileProvider = StreamProvider<ProfileRecord?>((ref) async* {
  final repo = await ref.watch(profileRepositoryProvider.future);
  yield* repo.watch();
});

/// Server-controlled config: the min-version gate + feature kill-switches
/// (MOBILE.md). Overridable in tests. This talks to Supabase REST directly,
/// NOT PowerSync — app_config is global, not per-user synced data.
final remoteConfigServiceProvider =
    Provider<RemoteConfigService>((ref) => RemoteConfigService());

/// The fetched config. FutureProvider so callers can fail-open while it loads.
/// Fetched once per launch; the service caches the min-build for offline use.
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  return ref.watch(remoteConfigServiceProvider).fetch();
});

/// True ONLY when we know the running build is below the required floor.
/// While the fetch is loading or errored, resolves to false (fail-open) so a
/// merely-offline user is never locked out (CLAUDE.md rule 1).
final mustUpdateProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  final config = await ref.watch(remoteConfigProvider.future);
  return service.mustUpdate(config);
});

/// Read a feature kill-switch by name, defaulting to [orElse] until config
/// loads or when the flag is absent. Future features (PhotoSnap in M3) gate on
/// this so we can disable them server-side without shipping a new build.
bool featureEnabled(WidgetRef ref, String name, {bool orElse = true}) {
  return ref.watch(remoteConfigProvider).maybeWhen(
        data: (c) => c.flag(name, orElse: orElse),
        orElse: () => orElse,
      );
}

/// Onboarding is done once a profile exists AND is flagged complete.
/// Drives the router gate. Loading/error resolve to "not complete" so the
/// gate never flashes the main app before the profile is known.
final onboardingCompleteProvider = Provider<bool>((ref) {
  return ref.watch(profileProvider).maybeWhen(
        data: (p) => p?.onboardingComplete ?? false,
        orElse: () => false,
      );
});
