import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
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

  Future<String?> pump(WidgetTester t, {String? tap}) async {
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
      overrides: [databaseProvider.overrideWith((ref) async => db)],
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

  for (final entry in _rows.entries) {
    testWidgets('${entry.key} navigates to ${entry.value}', (t) async {
      expect(await pump(t, tap: entry.key), entry.value);
      await dispose(t);
    });
  }
}
