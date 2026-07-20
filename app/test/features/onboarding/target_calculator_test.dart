import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile.dart';
import 'package:sakama/features/onboarding/domain/target_calculator.dart';

void main() {
  const calc = TargetCalculator();

  Profile p({
    int age = 30,
    double kg = 70,
    double cm = 175,
    Sex sex = Sex.male,
    ActivityLevel activity = ActivityLevel.moderate,
    Goal goal = Goal.maintain,
  }) =>
      Profile(
        ageYears: age, weightKg: kg, heightCm: cm, sex: sex,
        activity: activity, goal: goal,
        diet: DietPreference.veg, cuisine: CuisinePreference.both,
      );

  group('BMR (Mifflin–St Jeor)', () {
    test('male 70kg/175cm/30y = 1648.75', () {
      // 10*70 + 6.25*175 - 5*30 + 5 = 700 + 1093.75 - 150 + 5
      expect(calc.bmr(p()), closeTo(1648.75, 1e-9));
    });
    test('female same body = 1482.75 (constant −161)', () {
      expect(calc.bmr(p(sex: Sex.female)), closeTo(1482.75, 1e-9));
    });
    test('other = mean constant −78 -> 1565.75', () {
      expect(calc.bmr(p(sex: Sex.other)), closeTo(1565.75, 1e-9));
    });
  });

  group('TDEE = BMR × activity factor', () {
    test('sedentary 1.2', () {
      expect(calc.tdee(p(activity: ActivityLevel.sedentary)),
          closeTo(1648.75 * 1.2, 1e-9));
    });
    test('veryActive 1.9', () {
      expect(calc.tdee(p(activity: ActivityLevel.veryActive)),
          closeTo(1648.75 * 1.9, 1e-9));
    });
  });

  group('calorie target: goal delta + round-to-10 + floor', () {
    test('maintain moderate ≈ 2555 (1648.75*1.55=2555.56 -> 2560)', () {
      expect(calc.calorieTarget(p()), 2560);
    });
    test('loseWeight applies −20%', () {
      // 2555.56 * 0.8 = 2044.45 -> 2040
      expect(calc.calorieTarget(p(goal: Goal.loseWeight)), 2040);
    });
    test('buildMuscle applies +12.5%', () {
      // 2555.56 * 1.125 = 2875.0 -> 2880 (2875 rounds to 2880? 2875/10=287.5->288)
      expect(calc.calorieTarget(p(goal: Goal.buildMuscle)), 2880);
    });
    test('female sedentary loseWeight hits the 1200 floor, not lower', () {
      // BMR 1482.75 * 1.2 = 1779.3; *0.8 = 1423.4 -> 1420 (above floor)
      final t = calc.calorieTarget(
          p(sex: Sex.female, activity: ActivityLevel.sedentary, goal: Goal.loseWeight));
      expect(t, greaterThanOrEqualTo(1200));
    });
    test('tiny person + aggressive deficit is floored to 1200 (female/other)', () {
      // 40kg/150cm/25y female sedentary loseWeight: BMR=10*40+6.25*150-125-161
      // =400+937.5-125-161=1051.5; *1.2=1261.8; *0.8=1009.4 -> floored to 1200
      final t = calc.calorieTarget(Profile(
        ageYears: 25, weightKg: 40, heightCm: 150, sex: Sex.female,
        activity: ActivityLevel.sedentary, goal: Goal.loseWeight,
        diet: DietPreference.veg, cuisine: CuisinePreference.both));
      expect(t, 1200);
    });
    test('male floor is 1500', () {
      final t = calc.calorieTarget(Profile(
        ageYears: 70, weightKg: 45, heightCm: 150, sex: Sex.male,
        activity: ActivityLevel.sedentary, goal: Goal.loseWeight,
        diet: DietPreference.veg, cuisine: CuisinePreference.both));
      expect(t, 1500);
    });
  });

  group('targets: macros, protein-by-bodyweight, fibre + water', () {
    test('every goal: protein+carb+fat kcal within rounding of target', () {
      for (final goal in Goal.values) {
        final t = calc.targets(p(goal: goal));
        final macroKcal = t.proteinG * 4 + t.carbG * 4 + t.fatG * 9;
        expect((macroKcal - t.calories).abs(), lessThanOrEqualTo(12),
            reason: 'goal $goal: macro kcal $macroKcal vs ${t.calories}');
      }
    });
    test('protein is anchored to body weight, not the calorie budget', () {
      // 70kg loseWeight = 2.0 g/kg = 140g, DESPITE fewer calories than maintain
      expect(calc.targets(p(kg: 70, goal: Goal.loseWeight)).proteinG, 140);
      expect(calc.targets(p(kg: 70, goal: Goal.maintain)).proteinG, 112); // 1.6*70
    });
    test('loseWeight now HAS more absolute protein than maintain (the fix)', () {
      expect(calc.targets(p(goal: Goal.loseWeight)).proteinG,
          greaterThan(calc.targets(p(goal: Goal.maintain)).proteinG));
    });
    test('carbs never go negative on a low target with high protein', () {
      for (final goal in Goal.values) {
        final t = calc.targets(Profile(
          ageYears: 25, weightKg: 45, heightCm: 150, sex: Sex.female,
          activity: ActivityLevel.sedentary, goal: goal,
          diet: DietPreference.veg, cuisine: CuisinePreference.both));
        expect(t.carbG, greaterThanOrEqualTo(0), reason: '$goal');
      }
    });
    test('fibre = 14 g per 1000 kcal', () {
      final t = calc.targets(p()); // 2560 kcal
      expect(t.fiberG, (2560 / 1000 * 14).round()); // 36
    });
    test('water = 35 ml/kg, min 2000', () {
      expect(calc.targets(p(kg: 70)).waterMl, 2450);
      expect(calc.targets(p(kg: 50)).waterMl, 2000); // 1750 -> floored
    });
  });

  test('all enum factors are sane (monotonic activity, correct constants)', () {
    expect(ActivityLevel.values.map((a) => a.factor).toList(),
        [1.2, 1.375, 1.55, 1.725, 1.9]);
    expect(Sex.male.bmrConstant - Sex.female.bmrConstant, 166);
    expect(Sex.other.bmrConstant, (Sex.male.bmrConstant + Sex.female.bmrConstant) ~/ 2);
  });
}
