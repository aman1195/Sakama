import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/coach/domain/coach_context.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

ProfileRecord _profile({List<HealthCondition> conditions = const []}) =>
    ProfileRecord(
        dob: DateTime(2000, 1, 1), weightKg: 84, heightCm: 178, sex: Sex.male,
        activity: ActivityLevel.moderate, goal: Goal.loseWeight,
        diet: DietPreference.veg, cuisine: CuisinePreference.both,
        conditions: conditions, onboardingComplete: true);

const _targets = NutritionTargets(
    calories: 1650, proteinG: 130, carbG: 165, fatG: 55, fiberG: 30,
    waterMl: 3000);

FoodLog _log(String meal, String name, double kcal, double p) => FoodLog(
    id: name, userId: null, date: '2026-07-30', meal: meal, name: name,
    grams: 150, energyKcal: kcal, proteinG: p, carbG: 20, fatG: 5,
    loggedVia: 'search', createdAt: 1, updatedAt: 1);

void main() {
  final now = DateTime(2026, 7, 30, 16, 5);

  test('grounds on real totals: kcal eaten/left + macros + meal contents', () {
    final ctx = CoachContext.build(
        profile: _profile(), targets: _targets, now: now,
        todayLogs: [_log('breakfast', 'Poha', 195, 4),
                    _log('lunch', 'Dal Tadka', 180, 9)]);
    expect(ctx, contains('375 of 1650 kcal'));   // 195+180
    expect(ctx, contains('1275 left'));          // 1650-375
    expect(ctx, contains('protein 13/130g'));    // 4+9
    expect(ctx, contains('Breakfast: Poha.'));
    expect(ctx, contains('Lunch: Dal Tadka.'));
    expect(ctx, contains('16:05'));
    expect(ctx, contains('lose weight'));        // goal humanized
  });

  test('empty day says so explicitly (Vita must not invent meals)', () {
    final ctx = CoachContext.build(
        profile: _profile(), targets: _targets, now: now, todayLogs: []);
    expect(ctx, contains('Nothing logged yet today'));
    expect(ctx, contains('0 of 1650 kcal'));
  });

  test('surfaces conditions (grounds condition-aware advice)', () {
    final ctx = CoachContext.build(
        profile: _profile(conditions: [HealthCondition.diabetes]),
        targets: _targets, now: now, todayLogs: []);
    expect(ctx, contains('diabetes'));
  });

  test('handles no targets (casual tracker) without crashing', () {
    final ctx = CoachContext.build(
        profile: null, targets: null, now: now,
        todayLogs: [_log('snack', 'Peanuts', 170, 8)]);
    expect(ctx, contains('170 kcal logged'));
    expect(ctx, contains('no targets set'));
  });
}
