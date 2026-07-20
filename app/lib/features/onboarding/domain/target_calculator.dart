import 'dart:math' as math;

import 'enums.dart';
import 'nutrition_targets.dart';
import 'profile.dart';

/// The one piece of nutrition math that lives in code (CLAUDE.md / plan-engine
/// note). Pure functions, no I/O, exhaustively tested. Protocol-specific targets
/// come from the JSON plan engine later; this is the no-plan default (Type 3).
class TargetCalculator {
  const TargetCalculator();

  // Kcal per gram.
  static const _kcalPerG = {'protein': 4.0, 'carb': 4.0, 'fat': 9.0};

  /// Never recommend below these, whatever the goal deficit computes — a safety
  /// floor against unhealthily low targets. Common clinical minimums.
  static const _calorieFloorMale = 1500;
  static const _calorieFloorFemaleOther = 1200;

  /// Basal metabolic rate — Mifflin–St Jeor (1990), the modern standard
  /// (~5% error). weight kg, height cm, age years:
  ///   BMR = 10·kg + 6.25·cm − 5·age + sexConstant
  /// sexConstant: male +5, female −161, other −78 (mean).
  double bmr(Profile p) =>
      10 * p.weightKg + 6.25 * p.heightCm - 5 * p.ageYears + p.sex.bmrConstant;

  /// Total daily energy expenditure = BMR × activity factor.
  double tdee(Profile p) => bmr(p) * p.activity.factor;

  /// Goal-adjusted daily calorie target, rounded to 10, with a sex-aware floor.
  int calorieTarget(Profile p) {
    final adjusted = tdee(p) * (1 + p.goal.calorieDelta);
    final floor = p.sex == Sex.male ? _calorieFloorMale : _calorieFloorFemaleOther;
    final rounded = (adjusted / 10).round() * 10;
    return math.max(rounded, floor);
  }

  /// Protein is anchored to BODY WEIGHT (g per kg), not to a % of the calorie
  /// budget. This is the nutritionally correct model: in a deficit you want
  /// protein HIGH in absolute terms to preserve lean mass, and a %-of-calories
  /// split perversely lowers it as the budget shrinks. Loss/gain get more per
  /// kg than maintenance.
  double proteinGPerKg(Goal goal) => switch (goal) {
        Goal.loseWeight => 2.0,
        Goal.buildMuscle => 1.8,
        Goal.maintain => 1.6,
        Goal.detox => 1.4,
        Goal.manageCondition => 1.4,
      };

  /// Fat as a fraction of calories (for essential fats/satiety); carbohydrate
  /// takes whatever calories remain after protein and fat.
  double fatFraction(Goal goal) => switch (goal) {
        Goal.buildMuscle => 0.25,
        Goal.maintain => 0.28,
        _ => 0.30,
      };

  NutritionTargets targets(Profile p) {
    final kcal = calorieTarget(p);
    final proteinG = (proteinGPerKg(p.goal) * p.weightKg).round();
    final fatG = (kcal * fatFraction(p.goal) / _kcalPerG['fat']!).round();
    // Carbs fill the remainder; never negative (very low targets + high
    // body-weight protein can consume the whole budget).
    final remainderKcal = kcal - proteinG * 4 - fatG * 9;
    final carbG = math.max(0, (remainderKcal / _kcalPerG['carb']!).round());
    return NutritionTargets(
      calories: kcal,
      proteinG: proteinG,
      carbG: carbG,
      fatG: fatG,
      // Dietary-guideline fibre target: 14 g per 1000 kcal.
      fiberG: (kcal / 1000 * 14).round(),
      // ~35 ml/kg body weight, min 2000 ml.
      waterMl: math.max((p.weightKg * 35).round(), 2000),
    );
  }
}
