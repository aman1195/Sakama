import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

void main() {
  testWidgets('shell renders five tabs and actually switches branches',
      (tester) async {
    // The real databaseProvider opens PowerSync (platform channels) — widget
    // tests override it with in-memory Drift, per its own contract.
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    // A completed profile so the onboarding gate lets us reach the shell.
    final onboarded = ProfileRecord(
      dob: DateTime(1994, 1, 1), weightKg: 70, heightCm: 175, sex: Sex.male,
      activity: ActivityLevel.moderate, goal: Goal.maintain,
      diet: DietPreference.veg, cuisine: CuisinePreference.both,
      onboardingComplete: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        profileProvider.overrideWith((ref) => Stream.value(onboarded)),
      ],
      child: const SakamaApp(),
    ));
    // NOT pumpAndSettle: the Home branch shows an infinitely animating spinner
    // while the db future resolves, so settle can never complete (its default
    // timeout is 10 minutes). Pump until the spinner CLEARS rather than a fixed
    // count: the onboarding gate added async hops (profile stream -> redirect
    // off /splash -> shell mounts -> HomePage db resolves), so the settle point
    // moved past the old 3-pump count. Robust against the exact timing.
    for (var i = 0;
        i < 40 && tester.any(find.byType(CircularProgressIndicator));
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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
