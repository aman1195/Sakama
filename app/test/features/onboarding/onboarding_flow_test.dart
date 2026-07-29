import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/presentation/onboarding_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sakama/features/onboarding/presentation/onboarding_page.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/onboarding/data/profile_repository.dart';
import 'package:sakama/features/onboarding/presentation/onboarding_draft.dart';

void main() {
  group('OnboardingDraft validation', () {
    final now = DateTime(2026, 6, 1);
    OnboardingDraft full() => OnboardingDraft(
          goal: Goal.loseWeight,
          dob: DateTime(1994, 3, 15),
          weightKg: 70, heightCm: 175, sex: Sex.male,
          diet: DietPreference.veg, cuisine: CuisinePreference.both,
          activity: ActivityLevel.moderate);

    test('a fully-filled, in-range draft is complete', () {
      expect(full().complete(now), isTrue);
    });
    test('out-of-range weight/height/age block the profile step', () {
      expect(full().copyWith(weightKg: 5).profileOk(now), isFalse); // < 20
      expect(full().copyWith(heightCm: 300).profileOk(now), isFalse); // > 250
      expect(full().copyWith(dob: DateTime(2020)).profileOk(now), isFalse); // too young
    });
    test('missing any required selection blocks completion', () {
      expect(full().copyWith(goal: null).complete(now), isFalse);
      expect(full().copyWith(cuisine: null).complete(now), isFalse);
    });
    test('conditions are optional (step passes with none)', () {
      expect(full().conditions, isEmpty);
      expect(full().complete(now), isTrue);
    });
  });

  test('controller.finish persists a ProfileRecord; incomplete draft does not',
      () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    final ctl = container.read(onboardingControllerProvider.notifier);

    // Incomplete -> false, nothing written.
    expect(await ctl.finish(), isFalse);
    expect(await db.select(db.profiles).get(), isEmpty);

    // Fill it in via the controller setters, then finish.
    ctl
      ..setGoal(Goal.buildMuscle)
      ..setDob(DateTime(1990, 5, 20))
      ..setWeight(80)
      ..setHeight(180)
      ..setSex(Sex.male)
      ..setDiet(DietPreference.nonVeg)
      ..setCuisine(CuisinePreference.north)
      ..setActivity(ActivityLevel.active);
    expect(await ctl.finish(), isTrue);

    final rows = await db.select(db.profiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.goal, 'buildMuscle');
    expect(rows.single.onboardingComplete, isTrue);
  });

  test('condition toggle: "none" is mutually exclusive with real conditions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctl = container.read(onboardingControllerProvider.notifier);

    ctl.toggleCondition(HealthCondition.diabetes);
    ctl.toggleCondition(HealthCondition.thyroid);
    expect(container.read(onboardingControllerProvider).conditions,
        [HealthCondition.diabetes, HealthCondition.thyroid]);

    // Choosing "none" clears the rest.
    ctl.toggleCondition(HealthCondition.none);
    expect(container.read(onboardingControllerProvider).conditions,
        [HealthCondition.none]);

    // Choosing a real one clears "none".
    ctl.toggleCondition(HealthCondition.pcod);
    expect(container.read(onboardingControllerProvider).conditions,
        [HealthCondition.pcod]);
  });

  testWidgets('gate: no profile -> onboarding shown, not the shell', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const SakamaApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Onboarding's first step is visible; the shell's nav is not.
    expect(find.bySemanticsIdentifier('goal-loseWeight'), findsOneWidget);
    expect(find.byKey(const Key('nav-home')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('concurrent save() calls produce exactly ONE profile row (PR #49 race)',
      () async {
    // Pre-transaction, a double-tap interleaved two saves at the first await:
    // both saw an empty table, minted different uuids, both INSERTed — and two
    // rows make watchSingleOrNull/getSingleOrNull throw forever (onboarding
    // permanently wedged on device). The transaction serializes them.
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ProfileRepository(db);
    final record = ProfileRecord(
        dob: DateTime(1994, 1, 1), weightKg: 70, heightCm: 175, sex: Sex.male,
        activity: ActivityLevel.moderate, goal: Goal.maintain,
        diet: DietPreference.veg, cuisine: CuisinePreference.both,
        onboardingComplete: true);
    await Future.wait([repo.save(record), repo.save(record)]);
    final rows = await db.select(db.profiles).get();
    expect(rows, hasLength(1),
        reason: 'two interleaved saves must serialize into one row');
    // And the single-row invariants still hold for readers.
    expect(await repo.get(), isNotNull);
  });

  testWidgets('numeric-field focus is released on step navigation (iOS keypad '
      'has no Done key — a surviving keyboard blocks the flow)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const MaterialApp(home: OnboardingPage()),
    ));
    await tester.pump();

    // Step 0: pick a goal, continue to the profile step.
    await tester.tap(find.bySemanticsIdentifier('goal-loseWeight'));
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('onboarding-next'));
    await tester.pumpAndSettle();

    // Focus the weight field (keyboard would be up on a device).
    await tester.tap(find.bySemanticsIdentifier('profile-weight'));
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus?.context?.widget,
        isNotNull);
    final focusedBefore = tester.binding.focusManager.primaryFocus;
    expect(focusedBefore, isNotNull);

    // Navigate BACK — focus (and with it the keyboard) must be released.
    await tester.tap(find.bySemanticsIdentifier('onboarding-back'));
    await tester.pumpAndSettle();
    final focused = tester.binding.focusManager.primaryFocus;
    expect(focused?.context?.widget is EditableText, isFalse,
        reason: 'no text field may keep focus after leaving the step');
  });
}
