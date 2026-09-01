import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/home/presentation/home_page.dart';
import 'package:sakama/features/home/presentation/widgets/today_hero.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/onboarding/domain/target_calculator.dart';
import 'package:sakama/features/plans/application/plan_providers.dart';
import 'package:sakama/features/plans/domain/plan.dart';

/// M4.1b: the active plan's day-type targets overlay the computed maintenance
/// targets on the dashboard (and, via targetsProvider, in Vita's grounding).

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

final _profile = ProfileRecord(
  dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: Sex.male,
  activity: ActivityLevel.moderate, goal: Goal.maintain,
  diet: DietPreference.veg, cuisine: CuisinePreference.both,
  onboardingComplete: true);

/// Identical but for sex, so a difference in outcome can only come from the
/// floor being sex-aware.
final _femaleProfile = ProfileRecord(
  dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: Sex.female,
  activity: ActivityLevel.moderate, goal: Goal.maintain,
  diet: DietPreference.veg, cuisine: CuisinePreference.both,
  onboardingComplete: true);

// A plan whose default calories are a distinctive 1500 (unlike any computed
// maintenance value); every weekday maps to the sole 'normal' day type.
const _planCalories1500 = '{"schema_version":1,"id":"p","name":"Reset",'
    '"goal":"detox","targets_default":{"calories":1500},'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"normal",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

Future<void> _seedActivePlan(SakamaDatabase db, String config) =>
    db.into(db.userPlans).insert(UserPlansCompanion.insert(
          id: 'plan-1', name: 'Reset', config: config,
          active: const Value(true), createdAt: 1, updatedAt: 1));

String _planWithCalories(int kcal) =>
    '{"schema_version":1,"id":"p","name":"Reset",'
    '"goal":"lose_weight","targets_default":{"calories":$kcal},'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"normal",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

/// A plan whose macros are sized for [kcal], so discarding the calories without
/// discarding the macros would be visible.
String _planWithCaloriesAndMacros(int kcal) =>
    '{"schema_version":1,"id":"p","name":"Reset",'
    '"goal":"lose_weight","targets_default":{"calories":$kcal,'
    '"macros":{"protein_g":45,"carb_g":90,"fat_g":25,"fiber_g":13}},'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"normal",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

Future<bool> _resolveOverrideFlag({
  required ProfileRecord profile,
  String? planConfig,
}) =>
    _resolve(profile: profile, planConfig: planConfig, read: (c) => c.read(planTargetsOverriddenProvider));

/// Resolve [targetsProvider] against a seeded plan, without a widget tree.
Future<NutritionTargets?> _resolveTargets({
  required ProfileRecord profile,
  String? planConfig,
}) =>
    _resolve(profile: profile, planConfig: planConfig, read: (c) => c.read(targetsProvider));

Future<T> _resolve<T>({
  required ProfileRecord profile,
  required T Function(ProviderContainer) read,
  String? planConfig,
}) async {
  final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
  addTearDown(db.close);
  if (planConfig != null) await _seedActivePlan(db, planConfig);

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWith((ref) async => db),
    profileProvider.overrideWith((ref) => Stream.value(profile)),
  ]);
  addTearDown(container.dispose);
  container.listen(targetsProvider, (_, _) {});
  container.listen(activePlanDayProvider, (_, _) {});
  await container.read(databaseProvider.future);

  // Wait on the CONDITION, not on a fixed number of milliseconds. A timed
  // settle can pass vacuously on a slow machine: if the plan stream has not
  // arrived, there is no plan to refuse, and "the starvation target was not
  // used" is then true for the wrong reason.
  await _until(() =>
      container.read(profileProvider).hasValue &&
      (planConfig == null) == (container.read(activePlanDayProvider) == null));
  return read(container);
}

Future<void> _until(bool Function() condition, {int maxMs = 3000}) async {
  for (var waited = 0; waited < maxMs; waited += 10) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('providers did not settle within ${maxMs}ms');
}

void main() {
  testWidgets('active plan target drives the dashboard hero, overlaying computed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'x', date: _today(), meal: 'lunch', name: 'dal tadka',
          energyKcal: 180, createdAt: 1, updatedAt: 1));
    await _seedActivePlan(db, _planCalories1500);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        profileProvider.overrideWith((ref) => Stream.value(_profile)),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    for (var i = 0;
        i < 40 && tester.widgetList(find.byType(TodayHero)).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Extra pumps so the plan stream (db future → repo → watchActiveRow) settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The ring shows the PLAN's 1500 target, not the computed maintenance value.
    // The point of the test is that the PLAN's 1500 wins over the computed
    // maintenance target; the hero states it as "of 1500 kcal" alongside what
    // has been eaten.
    expect(find.textContaining('of 1500 kcal'), findsOneWidget);
    expect(find.textContaining('180 eaten'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('targetsProvider falls back to computed when no plan is active', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      profileProvider.overrideWith((ref) => Stream.value(_profile)),
    ]);
    addTearDown(container.dispose);
    container.listen(targetsProvider, (_, _) {});

    // Let profile + the (empty) plan stream resolve.
    await container.read(databaseProvider.future);
    for (var i = 0;
        i < 50 && !container.read(profileProvider).hasValue;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final computed = container.read(targetsProvider);
    expect(computed, isNotNull);
    // No active plan → equals the raw computed maintenance target (never 1500).
    expect(computed!.calories, isNot(1500));
  });

  /// A plan overrides the computed target wholesale, and plans are DATA — model
  /// written, synced, or seeded. The safety floor used to guard only the path
  /// that COMPUTES a target, so any plan could quietly replace it with anything.
  group('the calorie floor survives an active plan', () {
    test('a starvation plan is not honoured; the computed target stands',
        () async {
      final targets =
          await _resolveTargets(profile: _profile, planConfig: _planWithCalories(900));
      expect(targets, isNotNull);
      expect(targets!.calories, isNot(900),
          reason: 'a plan must not be able to prescribe 900 kcal');
      expect(targets.calories,
          greaterThanOrEqualTo(TargetCalculator.calorieFloor(Sex.male)));
    });

    test('the macros stay consistent with the calories that are shown',
        () async {
      // The plan states macros sized for 900 kcal. Clamping the energy alone
      // would keep THOSE while showing ~2540, so the macro row would contradict
      // the ring directly above it. An earlier version of this test seeded a
      // plan with no macros at all, which only proved TargetCalculator can add
      // up — it passed whether or not the plan's macros were discarded.
      final targets = await _resolveTargets(
          profile: _profile, planConfig: _planWithCaloriesAndMacros(900));
      expect(targets!.proteinG, isNot(45), reason: "the plan's macros are gone");
      final fromMacros = targets.proteinG * 4 + targets.carbG * 4 + targets.fatG * 9;
      expect((fromMacros - targets.calories).abs(), lessThan(60),
          reason: 'macros must add up to the target being displayed');
    });

    test('a safe plan is still honoured — the floor is not a blanket override',
        () async {
      final targets = await _resolveTargets(
          profile: _profile, planConfig: _planWithCalories(1900));
      expect(targets!.calories, 1900);
    });

    test('the floor is sex-aware: the same plan is refused for one profile '
        'and honoured for another', () async {
      // 1300 kcal sits between the two clinical minimums, so a single absolute
      // number would get exactly one of these two users wrong.
      const plan = 1300;
      final male = await _resolveTargets(
          profile: _profile, planConfig: _planWithCalories(plan));
      final female = await _resolveTargets(
          profile: _femaleProfile, planConfig: _planWithCalories(plan));

      expect(male!.calories, isNot(plan),
          reason: 'below the 1500 floor for men');
      expect(female!.calories, plan,
          reason: 'above the 1200 floor, so the plan stands');
    });

    test('exactly the floor is allowed', () async {
      final targets = await _resolveTargets(
          profile: _femaleProfile, planConfig: _planWithCalories(1200));
      expect(targets!.calories, 1200);
    });
  });

  /// The override must be VISIBLE. The plan's rules — window, blocked foods,
  /// checklist — still apply on a day whose numbers were refused, so a silent
  /// override leaves the app instructing clear soup while scoring against a
  /// full maintenance target, with nothing to explain the gap.
  group('the override is observable', () {
    test('flagged when the plan day is refused', () async {
      final flag = await _resolveOverrideFlag(
          profile: _profile, planConfig: _planWithCalories(900));
      expect(flag, isTrue);
    });

    test('not flagged for a plan that is honoured', () async {
      final flag = await _resolveOverrideFlag(
          profile: _profile, planConfig: _planWithCalories(1900));
      expect(flag, isFalse);
    });

    test('not flagged when there is no plan at all', () async {
      expect(await _resolveOverrideFlag(profile: _profile), isFalse);
    });

    test('the flag and the numbers cannot disagree', () async {
      // targetsProvider is derived from the same predicate. If a refactor ever
      // splits them, one of these two assertions breaks.
      for (final kcal in [900, 1300, 1900, 2600]) {
        final targets = await _resolveTargets(
            profile: _profile, planConfig: _planWithCalories(kcal));
        final flag = await _resolveOverrideFlag(
            profile: _profile, planConfig: _planWithCalories(kcal));
        expect(flag, targets!.calories != kcal,
            reason: 'flag must be set exactly when the plan number is not used '
                '(plan stated $kcal, target is ${targets.calories})');
      }
    });
  });

  group('violatesCalorieFloor', () {
    const base = NutritionTargets(
        calories: 2000, proteinG: 140, carbG: 200, fatG: 67,
        fiberG: 28, waterMl: 2450);

    test('judges the value that would actually be used', () {
      expect(const PlanTargets(calories: 900).violatesCalorieFloor(base, 1200),
          isTrue);
      expect(const PlanTargets(calories: 1800).violatesCalorieFloor(base, 1200),
          isFalse);
    });

    test('a plan that sets no calories inherits the computed target, which is '
        'already floored', () {
      // Rejecting this would kill the legitimate plan that only sets an eating
      // window or a food rule.
      expect(const PlanTargets(proteinG: 150).violatesCalorieFloor(base, 1200),
          isFalse);
    });
  });
}
