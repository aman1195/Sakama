// Reproduces the on-device "Start tracking does nothing" report (SAK-34) on
// the REAL production stack: PowerSync-backed DB, no provider overrides.
// Widget tests could not catch it because they override databaseProvider
// with plain in-memory Drift.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakama/app/app.dart';
import 'package:sakama/core/env/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder f,
    {int seconds = 15}) async {
  for (var i = 0; i < seconds * 10 && f.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets, reason: 'timed out waiting for $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full onboarding on the production stack reaches the shell',
      (tester) async {
    if (Env.isConfigured) {
      await Supabase.initialize(
          url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    }
    await tester.pumpWidget(const ProviderScope(child: SakamaApp()));

    // Gate resolves: fresh install -> onboarding.
    await _pumpUntil(tester, find.bySemanticsIdentifier('goal-loseWeight'));
    await tester.pump(const Duration(milliseconds: 400));

    Future<void> next(Finder landmark) async {
      await tester.tap(find.bySemanticsIdentifier('onboarding-next'));
      await _pumpUntil(tester, landmark); // wait for the next step to build
      // ...then let the 250ms page animation finish — a tap during the
      // slide lands on a moving (untappable) hit-target.
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.bySemanticsIdentifier('goal-loseWeight'));
    await tester.pump();
    await next(find.bySemanticsIdentifier('profile-weight'));

    // Profile step. Dob first: open the date picker, accept the initial
    // date (25 yrs ago — valid).
    await tester.tap(find.bySemanticsIdentifier('profile-dob'));
    await _pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.bySemanticsIdentifier('profile-weight'), '84');
    await tester.enterText(
        find.bySemanticsIdentifier('profile-height'), '178');
    await tester.ensureVisible(find.text('Male'));
    await tester.tap(find.text('Male')); // SegmentedButton has no semantics id
    await tester.pump();
    await next(find.bySemanticsIdentifier('diet-veg'));

    await tester.tap(find.bySemanticsIdentifier('diet-veg'));
    await tester.pump();
    await next(find.bySemanticsIdentifier('condition-none'));
    await next(find.bySemanticsIdentifier('cuisine-both')); // conditions optional
    await tester.tap(find.bySemanticsIdentifier('cuisine-both'));
    await tester.pump();
    await next(find.bySemanticsIdentifier('activity-moderate'));
    await tester.tap(find.bySemanticsIdentifier('activity-moderate'));
    await tester.pump();
    await next(find.bySemanticsIdentifier('onboarding-finish'));

    // Preview -> Start tracking.
    await tester.ensureVisible(find.bySemanticsIdentifier('onboarding-finish'));
    await tester.tap(find.bySemanticsIdentifier('onboarding-finish'));

    // THE ASSERTION UNDER TEST: the router gate must swap to the shell.
    await _pumpUntil(tester, find.byKey(const Key('nav-home')), seconds: 20);
  });
}
