// Onboarding value types. Plain enums (no persistence yet — that lands with the
// onboarding UI + profile table). Activity factors and BMR sex-constants are
// documented against their sources so the numbers are auditable.

/// Biological sex drives the Mifflin–St Jeor constant only. The app is
/// inclusive: `other` uses the mean of the male/female constants, which is the
/// most defensible neutral for an equation that has no third parameterisation.
enum Sex {
  male(bmrConstant: 5),
  female(bmrConstant: -161),
  other(bmrConstant: -78); // (5 + -161) / 2

  const Sex({required this.bmrConstant});
  final int bmrConstant;
}

/// Mifflin–St Jeor TDEE multipliers (the standard 5-bucket mapping).
/// Source: mifflin_st_jeor equation, activity factors 1.2 … 1.9.
enum ActivityLevel {
  sedentary(factor: 1.2),
  light(factor: 1.375),
  moderate(factor: 1.55),
  active(factor: 1.725),
  veryActive(factor: 1.9);

  const ActivityLevel({required this.factor});
  final double factor;
}

/// The onboarding goal. `calorieDelta` is applied to TDEE as a fraction; macro
/// split per goal lives in the calculator. Deltas follow the plan-engine design
/// note (−15–20% loss, +10–15% gain, 0 maintain).
enum Goal {
  loseWeight(calorieDelta: -0.20),
  detox(calorieDelta: -0.15),
  buildMuscle(calorieDelta: 0.125),
  manageCondition(calorieDelta: 0.0),
  maintain(calorieDelta: 0.0);

  const Goal({required this.calorieDelta});
  final double calorieDelta;
}

enum DietPreference { veg, nonVeg, vegan, eggetarian }

enum CuisinePreference { north, south, both, other }

enum HealthCondition { diabetes, thyroid, liver, pcod, hypertension, none }
