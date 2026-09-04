import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/capture/data/food_log_repository.dart';
import '../../features/capture/data/photosnap_service.dart';
import '../../features/coach/data/chat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/status_colour_pref.dart';
import '../../features/coach/data/memory_extractor.dart';
import '../../features/media/data/photo_repository.dart';
import '../../features/media/data/photo_uploader.dart';
import '../../features/coach/data/memory_repository.dart';
import '../../features/coach/data/vita_service.dart';
import '../../features/foods/data/food_repository.dart';
import '../../features/foods/data/user_food_repository.dart';
import '../../features/foods/data/ai_estimator.dart';
import '../../features/plans/data/plan_generator.dart';
import '../../features/foods/data/food_seed.dart';
import '../../features/foods/data/off_client.dart';
import '../../features/foods/data/off_repository.dart';
import '../../features/foods/domain/barcode_result.dart';
import '../../features/settings/data/attribution_repository.dart';
import '../../features/onboarding/data/profile_repository.dart';
import '../../features/onboarding/data/target_history_repository.dart';
import '../../features/water/data/water_repository.dart';
import '../../features/plans/data/plan_repository.dart';
import '../../features/weight/data/weight_repository.dart';
import '../../features/meals/data/meal_repository.dart';
import '../../features/workouts/data/workout_repository.dart';
import '../../features/onboarding/domain/profile_record.dart';
import '../ai/ai_consent_store.dart';
import '../ai/byok_store.dart';
import '../auth/auth_service.dart';
import '../config/remote_config.dart';
import '../config/remote_config_service.dart';
import '../db/database.dart';
import '../sync/sync_failure_repository.dart';
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
final authServiceProvider = Provider<AuthService>((ref) {
  final auth = AuthService(ref.watch(syncServiceProvider));
  // Local-only conversations are outside PowerSync's clear, so they are dropped
  // explicitly on a CONFIRMED identity change (docs/architecture/06 §2a).
  auth.onIdentityChanged = () async {
    // EACH CLEAR IS GUARDED SEPARATELY. They are all wipes of the departing
    // user's health data, and a sequential chain means one throw strands
    // everything after it in the next user's session — the receipts most of
    // all, since they are last and carry row payloads.
    Future<void> wipe(String what, Future<void> Function() go) async {
      try {
        await go();
      } catch (e) {
        debugPrint('identity change: could not clear $what: $e');
      }
    }

    final repo = await ref.read(chatRepositoryProvider.future);
    await wipe('conversations', repo.deleteAll);
    // Memory is DISTILLED health data — the most sensitive thing on the
    // device — so it must be dropped on the same signal. Blanket, not
    // user-scoped: at identity-change time the departing uid is precisely what
    // has just gone away, so forgetAll(oldId) would leave rows behind in
    // exactly the case this exists to handle (review of #106).
    final memory = await ref.read(memoryRepositoryProvider.future);
    await wipe('memory', memory.deleteAll);
    // Receipts carry the payload of the row that failed, so they hold health
    // data and follow the same rule as the conversations and the memory.
    final failures = await ref.read(syncFailureRepositoryProvider.future);
    await wipe('sync receipts', failures.clear);
    // Queued photos are the MOST sensitive thing on this list: a pending
    // progress photo is a picture of the departing user's body, still on disk.
    // PowerSync's clear cannot reach it (clearLocal:false preserves local-only
    // tables on purpose), and it could not be uploaded or removed by whoever
    // signs in next — the object path's first segment is the old uid, and the
    // storage policy compares it against theirs. Files go with the rows.
    final photos = await ref.read(photoRepositoryProvider.future);
    await wipe('queued photos', photos.clearAll);
  };
  return auth;
});

/// Photos waiting to reach storage (A7).
final photoRepositoryProvider = FutureProvider<PhotoRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PhotoRepository(db);
});

/// Uploads queued photos, and signs links for the sensitive ones.
final photoUploaderProvider = FutureProvider<PhotoUploader>((ref) async {
  final repo = await ref.watch(photoRepositoryProvider.future);
  return PhotoUploader(
    repo: repo,
    storage: SupabasePhotoStorage(),
    // Read per drain, not captured here, so a photo uploads as whoever is
    // signed in at the time rather than whoever was when this was built.
    currentUserId: () => ref.read(currentUserIdProvider),
  );
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

final mealRepositoryProvider = FutureProvider<MealRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MealRepository(db);
});

/// Saved meals for the current signer, most-used first.
final savedMealsProvider = StreamProvider<List<MealRow>>((ref) async* {
  final repo = await ref.watch(mealRepositoryProvider.future);
  yield* repo.watchAll(userId: ref.watch(currentUserIdProvider));
});

final workoutRepositoryProvider =
    FutureProvider<WorkoutRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WorkoutRepository(db);
});

/// Receipts for writes the server refused (#148 follow-up). Local-only.
final syncFailureRepositoryProvider =
    FutureProvider<SyncFailureRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SyncFailureRepository(db);
});

/// How many writes were discarded, live. Drives the only honest thing the app
/// can do about silent loss: say it happened.
final syncFailureCountProvider = StreamProvider<int>((ref) async* {
  final repo = await ref.watch(syncFailureRepositoryProvider.future);
  yield* repo.watchCount();
});

final syncFailuresProvider =
    StreamProvider<List<SyncFailureRow>>((ref) async* {
  final repo = await ref.watch(syncFailureRepositoryProvider.future);
  yield* repo.watchAll();
});

/// What the targets were, per date (A1). Synced; the diary and every trend read
/// history through it so a changed goal never re-scores days already lived.
final targetHistoryRepositoryProvider =
    FutureProvider<TargetHistoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TargetHistoryRepository(db);
});

/// The whole (small) target timeline, live. Every row is a CHANGE, so this is
/// a handful of rows, not one per day.
final targetHistoryProvider =
    StreamProvider<List<TargetHistoryRow>>((ref) async* {
  final repo = await ref.watch(targetHistoryRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Favourites + custom foods (docs/architecture/08-user-foods.md). SYNCED, and
/// deliberately not `foods` — that table is wiped on every seedVersion bump.
final userFoodRepositoryProvider =
    FutureProvider<UserFoodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return UserFoodRepository(db);
});

/// Saved foods, resolved (a pointer's nutrition read from its source) and
/// most-used first. Null owner = pre-auth rows only, per the usual scoping.
final favouriteFoodsProvider =
    StreamProvider<List<ResolvedUserFood>>((ref) async* {
  final repo = await ref.watch(userFoodRepositoryProvider.future);
  final uid = ref.watch(currentUserIdProvider);
  await for (final rows in repo.watchAll(uid)) {
    yield await repo.resolveAll(rows);
  }
});

/// Vita conversations (ADR 0016 phase 1). DEVICE-LOCAL: local-only tables, so
/// nothing here syncs or reaches a server.
final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ChatRepository(db);
});

/// Resolved in main() before the first frame and injected here, so display
/// preferences are readable SYNCHRONOUSLY.
///
/// Null when nothing overrode it — widget tests, which mount screens without
/// wiring prefs and do not exercise these preferences. Deliberately NOT a
/// throwing provider: Riverpod wraps a thrown error into a ProviderException
/// that puts every dependent provider into an error state, so a missing
/// override would take out the whole screen rather than degrading one setting.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final statusColourPrefProvider = Provider<StatusColourPref>(
    (ref) => StatusColourPref(prefs: ref.watch(sharedPreferencesProvider)));

/// Whether the hero card is filled by status colour (PRODUCT.md principle 5).
///
/// SYNCHRONOUS on purpose. As a FutureProvider this rendered the coloured card
/// for a frame before resolving to neutral — showing an opted-out user the
/// exact judgement they had switched off (review of #127).
///
/// Falling back to `true` without prefs is safe rather than lazy: it yields
/// the DEFAULT experience, which is what a user with no stored preference gets
/// anyway. It cannot mute the app and it cannot invent a verdict.
final statusColourEnabledProvider =
    Provider<bool>((ref) => ref.watch(statusColourPrefProvider).enabledSync());

/// What Vita has learned (ADR 0016 phase 4). DEVICE-LOCAL, like the
/// conversations it is derived from.
final memoryRepositoryProvider =
    FutureProvider<MemoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MemoryRepository(db);
});

/// Everything Vita has learned, for the memory screen. Most useful first.
final memoryFactsProvider = StreamProvider<List<MemoryFact>>((ref) async* {
  final repo = await ref.watch(memoryRepositoryProvider.future);
  yield* repo.watchAll(ref.watch(currentUserIdProvider));
});

/// Distils a transcript into durable facts. Behind an interface so an
/// on-device implementation (Apple Foundation Models) can replace the Edge
/// Function without touching a caller.
final memoryExtractorProvider =
    Provider<MemoryExtractor>((ref) => EdgeFunctionMemoryExtractor());

/// User plans store (M4). Offline-first over the synced `user_plans` table.
final planRepositoryProvider = FutureProvider<PlanRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PlanRepository(db);
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

/// The user's BYOK OpenRouter key store (M3.4, on-device secure storage).
final byokStoreProvider = Provider<ByokStore>((ref) => ByokStore());

/// Whether a BYOK key is present, live (drives the "unlimited" UI + skips caps).
final hasByokProvider = FutureProvider<bool>((ref) async =>
    ref.watch(byokStoreProvider).has());

/// AI-data consent store (#60): device-local tri-state for whether AI features
/// may send logged data to the provider.
final aiConsentStoreProvider = Provider<AiConsentStore>((ref) => AiConsentStore());

/// The user's AI-data consent: `null` never-asked, `true` on, `false` off.
/// Mutated via [AiConsentController]; the first-use gate and the settings
/// toggle both read this.
class AiConsentController extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() => ref.read(aiConsentStoreProvider).read();

  Future<void> set(bool enabled) async {
    await ref.read(aiConsentStoreProvider).write(enabled);
    state = AsyncData(enabled);
  }
}

final aiConsentProvider =
    AsyncNotifierProvider<AiConsentController, bool?>(AiConsentController.new);

/// Vita coach service (M3.3). Injectable so tests use a fake.
final vitaServiceProvider =
    Provider<VitaService>((ref) => EdgeFunctionVita());

/// PhotoSnap vision service (M3.2). Injectable so tests use a fake.
final photoSnapServiceProvider =
    Provider<PhotoSnapService>((ref) => EdgeFunctionPhotoSnap());

/// AI nutrition estimation (ADR 0011: Edge Function -> managed gateway).
/// Injectable so tests use a fake and the UI works before deployment.
final aiEstimatorProvider =
    Provider<AiEstimator>((ref) => EdgeFunctionAiEstimator());

/// AI plan generation (M4.4, ADR 0007 + 0011: Edge Function `generate-plan`).
/// Injectable so tests use a fake; the UI entry ships dark behind a kill switch
/// until the function is smoke-tested live (design §7).
final planGeneratorProvider =
    Provider<PlanGenerator>((ref) => EdgeFunctionPlanGenerator());

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
