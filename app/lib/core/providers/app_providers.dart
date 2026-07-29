import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/capture/data/food_log_repository.dart';
import '../../features/foods/data/food_repository.dart';
import '../../features/foods/data/ai_estimator.dart';
import '../../features/foods/data/food_seed.dart';
import '../../features/foods/data/off_client.dart';
import '../../features/foods/data/off_repository.dart';
import '../../features/foods/domain/barcode_result.dart';
import '../../features/settings/data/attribution_repository.dart';
import '../../features/onboarding/data/profile_repository.dart';
import '../../features/water/data/water_repository.dart';
import '../../features/weight/data/weight_repository.dart';
import '../../features/onboarding/domain/profile_record.dart';
import '../auth/auth_service.dart';
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

/// Anonymous-first auth (M3.1). ensureSession is fired on startup by
/// SakamaApp and before AI calls; it never blocks or throws.
final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(syncServiceProvider)));

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

/// The seed corpus. Production = Indian sample + USDA asset; overridable in
/// tests with a small in-memory set (so tests never load the 1.5 MB asset).
final foodSeedSourceProvider =
    Provider<FoodSeedSource>((ref) => const AssetFoodSeed());

/// The food reference repository, seeded (version-gated) on first access.
/// Reloads when the bundled seed version bumps (existing installs get updates).
final foodRepositoryProvider = FutureProvider<FoodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final repo = FoodRepository(db);
  await repo.ensureSeeded(ref.watch(foodSeedSourceProvider));
  return repo;
});

/// Attribution derived FROM the provenance columns, so no bundled dataset can
/// ship uncredited (ASSET_CREDITS.md is a legal obligation, not a courtesy).
/// Depends on foodRepositoryProvider so the seed has loaded before we read it.
final usedDataSourcesProvider = FutureProvider<List<SourceUsage>>((ref) async {
  await ref.watch(foodRepositoryProvider.future); // ensure seeded
  final db = await ref.watch(databaseProvider.future);
  return AttributionRepository(db).usedSources();
});

/// OFF barcode lookup (ADR 0014: live + per-scan cache, ODbL-contained). The
/// client sends OFF the REAL app version in its User-Agent (OFF may block
/// clients it cannot identify). Overridable in tests with a mock http client.
final offClientProvider = FutureProvider<OffClient>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return OffClient(appVersion: info.version);
});

final offRepositoryProvider = FutureProvider<OffRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final client = await ref.watch(offClientProvider.future);
  return OffRepository(db, client);
});

/// AI nutrition estimation (ADR 0011: Edge Function -> managed gateway).
/// Injectable so tests use a fake and the UI works before deployment.
final aiEstimatorProvider =
    Provider<AiEstimator>((ref) => EdgeFunctionAiEstimator());

/// Resolve one scanned [barcode] into an explicit [BarcodeResult]. Failure
/// modes are VALUES, not thrown errors, so they stay off Riverpod's auto-retry
/// path (a thrown "rate limited" would loop in loading forever) and the UI is a
/// plain switch over states.
final barcodeLookupProvider =
    FutureProvider.family<BarcodeResult, String>((ref, barcode) async {
  final repo = await ref.watch(offRepositoryProvider.future);
  try {
    final food = await repo.lookup(barcode);
    return food == null ? const BarcodeNotFound() : BarcodeFound(food);
  } on OffRateLimitException {
    return const BarcodeRateLimited();
  } on OffLookupException {
    return const BarcodeOffline();
  }
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
