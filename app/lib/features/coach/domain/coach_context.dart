import '../../../core/db/database.dart';
import '../../home/domain/day_totals.dart';
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/profile_record.dart';

/// Assembles the grounding snapshot Vita needs so every reply references real
/// data (PRODUCT.md principle 4). Pure + deterministic, so it's fully tested —
/// this is the "coach earns its place" logic, not chrome.
class CoachContext {
  const CoachContext._();

  /// A compact, human-readable snapshot for the system prompt. Deliberately
  /// plain text (the model reads it, the user never sees it) and small
  /// (the function caps it at 4000 chars anyway).
  static String build({
    required ProfileRecord? profile,
    required NutritionTargets? targets,
    required List<FoodLog> todayLogs,
    required DateTime now,
  }) {
    final totals = DayTotals.fromLogs(todayLogs);
    final b = StringBuffer();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    b.writeln('Local time: $hhmm.');

    if (profile != null) {
      final age = now.year - profile.dob.year;
      b.writeln('User: $age-year-old ${profile.sex.name}, goal '
          '${_goal(profile.goal.name)}, diet ${profile.diet.name}.');
      if (profile.conditions.isNotEmpty) {
        b.writeln('Conditions: ${profile.conditions.map((c) => c.name).join(', ')}.');
      }
    }

    if (targets != null) {
      final kcalLeft = targets.calories - totals.calories;
      b.writeln('Today so far: ${totals.calories.round()} of '
          '${targets.calories} kcal (${kcalLeft.round()} left), '
          'protein ${totals.proteinG.round()}/${targets.proteinG}g, '
          'carbs ${totals.carbG.round()}/${targets.carbG}g, '
          'fat ${totals.fatG.round()}/${targets.fatG}g.');
    } else {
      b.writeln('Today so far: ${totals.calories.round()} kcal logged '
          '(no targets set).');
    }

    if (todayLogs.isEmpty) {
      b.writeln('Nothing logged yet today.');
    } else {
      final byMeal = groupByMeal(todayLogs);
      for (final meal in Meal.values) {
        final items = byMeal[meal] ?? const [];
        if (items.isEmpty) continue;
        b.writeln('${meal.label}: '
            '${items.map((e) => e.name).join(', ')}.');
      }
    }
    return b.toString().trim();
  }

  static String _goal(String g) => switch (g) {
        'loseWeight' => 'lose weight',
        'buildMuscle' => 'build muscle',
        'manageCondition' => 'manage a condition',
        _ => g,
      };
}
