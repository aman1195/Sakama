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

/// Resolve [targetsProvider] against a seeded plan, without a widget tree.
Future<NutritionTargets?> _resolveTargets({
  required ProfileRecord profile,
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
  await container.read(databaseProvider.future);
  for (var i = 0; i < 60 && !container.read(profileProvider).hasValue; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  // Let the plan stream settle so an active plan is actually in force.
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(targetsProvider);
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
      // Clamping the energy alone would leave the plan's macros — sized for the
      // unsafe number — summing to less than the ring is scored against.
      final targets =
          await _resolveTargets(profile: _profile, planConfig: _planWithCalories(900));
      final fromMacros = targets!.proteinG * 4 + targets.carbG * 4 + targets.fatG * 9;
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
