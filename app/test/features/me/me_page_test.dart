import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/core/auth/auth_service.dart';
import 'package:sakama/core/sync/sync_service.dart';
import 'package:sakama/features/me/presentation/me_page.dart';

/// Every destination the Me tab is responsible for reaching.
///
/// This list exists because SAK-126 regrouped five separate cards into one and
/// silently dropped a section in the process — caught only by an unused-import
/// warning, which is luck, not a safety net. A screen whose whole job is
/// navigation should fail loudly when a route stops being reachable.
const _rows = {
  'nav-plans': '/plans',
  'nav-byok': '/byok',
  'nav-ai-privacy': '/ai-privacy',
  'nav-memory': '/memory',
  'nav-data-sources': '/data-sources',
};

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String?> pump(WidgetTester t, {String? tap, bool configured = true}) async {
    String? went;
    final router = GoRouter(
      initialLocation: '/me',
      routes: [
        GoRoute(path: '/me', builder: (_, _) => const MePage()),
        for (final r in _rows.values)
          GoRoute(
              path: r,
              builder: (_, _) {
                went = r;
                return const SizedBox();
              }),
      ],
    );
    await t.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        // AccountSection renders NOTHING when auth is unconfigured, which is
        // correct — an unconfigured build has no account feature to show. But
        // it made this suite environment-dependent: green on a machine with a
        // real app/.env, red on CI which has none. Pinning `configured` makes
        // the test assert the widget's behaviour instead of the runner's
        // environment.
        authServiceProvider.overrideWith(
            (ref) => AuthService(SyncService(), configuredOverride: configured)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    if (tap != null) {
      await t.tap(find.bySemanticsIdentifier(tap));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }
    return went;
  }

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('every destination is present', (t) async {
    await pump(t);
    for (final id in _rows.keys) {
      expect(find.bySemanticsIdentifier(id), findsOneWidget,
          reason: '$id vanished — a Me row was dropped');
    }
    await dispose(t);
  });

  testWidgets('the account section survives a regroup', (t) async {
    // The exact thing that went missing. It is the only way to sign in, so
    // losing it strands a user with no route to their own account.
    await pump(t);
    expect(find.bySemanticsIdentifier('account-section'), findsOneWidget);
    await dispose(t);
  });

  testWidgets('the status-colour opt-out is reachable without hunting', (t) async {
    // A setting that exists for people who find the default uncomfortable
    // should sit in the main list, not behind a "Display" sub-screen.
    await pump(t);
    expect(find.bySemanticsIdentifier('toggle-status-colour'), findsOneWidget);
    // And it says what it does rather than whether it is good for you.
    expect(find.textContaining('Colour my day'), findsOneWidget);
    await dispose(t);
  });

  testWidgets('an unconfigured build shows no account section at all',
      (t) async {
    // The other half, and the reason the first test needed pinning: with no
    // Supabase configured there is no account feature, so rendering a sign-in
    // card that cannot work would be worse than rendering nothing. Asserting
    // it stops someone "fixing" the blank state by showing a dead form.
    await pump(t, configured: false);
    expect(find.bySemanticsIdentifier('account-section'), findsNothing);
    // Navigation still works — the rest of Me does not depend on auth.
    expect(find.bySemanticsIdentifier('nav-plans'), findsOneWidget);
    await dispose(t);
  });

  for (final entry in _rows.entries) {
    testWidgets('${entry.key} navigates to ${entry.value}', (t) async {
      expect(await pump(t, tap: entry.key), entry.value);
      await dispose(t);
    });
  }
}
