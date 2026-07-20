import '../domain/enums.dart';

/// User-facing labels. Kept separate from the enums (which are locale-
/// independent storage keys) so Hindi localization later swaps only this file.
extension GoalLabel on Goal {
  String get label => switch (this) {
        Goal.loseWeight => 'Lose weight',
        Goal.detox => 'Detox / reset',
        Goal.buildMuscle => 'Build muscle',
        Goal.manageCondition => 'Manage a condition',
        Goal.maintain => 'Just track',
      };
}

extension SexLabel on Sex {
  String get label => switch (this) {
        Sex.male => 'Male',
        Sex.female => 'Female',
        Sex.other => 'Other',
      };
}

extension DietLabel on DietPreference {
  String get label => switch (this) {
        DietPreference.veg => 'Vegetarian',
        DietPreference.nonVeg => 'Non-vegetarian',
        DietPreference.vegan => 'Vegan',
        DietPreference.eggetarian => 'Eggetarian',
      };
}

extension CuisineLabel on CuisinePreference {
  String get label => switch (this) {
        CuisinePreference.north => 'North Indian',
        CuisinePreference.south => 'South Indian',
        CuisinePreference.both => 'Both',
        CuisinePreference.other => 'Other',
      };
}

extension ActivityLabel on ActivityLevel {
  String get label => switch (this) {
        ActivityLevel.sedentary => 'Sedentary (little exercise)',
        ActivityLevel.light => 'Light (1–3 days/week)',
        ActivityLevel.moderate => 'Moderate (3–5 days/week)',
        ActivityLevel.active => 'Active (6–7 days/week)',
        ActivityLevel.veryActive => 'Very active (physical job / 2×/day)',
      };
}

extension ConditionLabel on HealthCondition {
  String get label => switch (this) {
        HealthCondition.diabetes => 'Diabetes',
        HealthCondition.thyroid => 'Thyroid',
        HealthCondition.liver => 'Fatty liver',
        HealthCondition.pcod => 'PCOD / PCOS',
        HealthCondition.hypertension => 'Hypertension',
        HealthCondition.none => 'None',
      };
}
