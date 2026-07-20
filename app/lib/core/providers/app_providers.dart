import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/onboarding/data/profile_repository.dart';
import '../../features/onboarding/domain/profile_record.dart';
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

/// The persisted profile, live. Null until onboarding writes it.
final profileProvider = StreamProvider<ProfileRecord?>((ref) async* {
  final repo = await ref.watch(profileRepositoryProvider.future);
  yield* repo.watch();
});

/// Onboarding is done once a profile exists AND is flagged complete.
/// Drives the router gate. Loading/error resolve to "not complete" so the
/// gate never flashes the main app before the profile is known.
final onboardingCompleteProvider = Provider<bool>((ref) {
  return ref.watch(profileProvider).maybeWhen(
        data: (p) => p?.onboardingComplete ?? false,
        orElse: () => false,
      );
});
