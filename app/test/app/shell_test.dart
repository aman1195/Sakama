import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';

void main() {
  testWidgets('shell renders five tabs and actually switches branches',
      (tester) async {
    // The real databaseProvider opens PowerSync (platform channels) — widget
    // tests override it with in-memory Drift, per its own contract.
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const SakamaApp(),
    ));
    // Bounded pumps, NOT pumpAndSettle: the Home branch shows an infinitely
    // animating spinner while the db future resolves, so settle can never
    // complete (its default timeout is 10 minutes — learned the hard way).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Proves the override actually resolved (no stuck loading state).
    expect(find.byType(CircularProgressIndicator), findsNothing);

    for (final id in ['nav-home', 'nav-diary', 'nav-capture', 'nav-coach', 'nav-me']) {
      expect(find.byKey(Key(id)), findsOneWidget, reason: '$id missing');
    }

    // Home branch active initially; diary page must NOT be built yet.
    expect(find.bySemanticsIdentifier('home-page'), findsOneWidget);
    expect(find.bySemanticsIdentifier('diary-page'), findsNothing);

    // Tap by stable key (never by localizable label). If goBranch is a no-op,
    // the diary-page assertion below fails — unlike asserting on the tab label,
    // which is always present.
    await tester.tap(find.byKey(const Key('nav-diary')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsIdentifier('diary-page'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-coach')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsIdentifier('coach-page'), findsOneWidget);

    // Unmount before teardown so drift's stream-debounce timers are flushed —
    // otherwise the binding's '!timersPending' invariant trips.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
