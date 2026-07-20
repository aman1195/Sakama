import '../../../core/db/database.dart';

/// Consumed totals for a day, summed from food_logs. Pure — trivially tested.
/// food_logs track protein/carb/fat (not fibre yet), so those three plus
/// calories are what the dashboard reconciles against targets.
class DayTotals {
  const DayTotals({
    this.calories = 0,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
  });

  final double calories;
  final double proteinG;
  final double carbG;
  final double fatG;

  static DayTotals fromLogs(Iterable<FoodLog> logs) {
    var kcal = 0.0, p = 0.0, c = 0.0, f = 0.0;
    for (final l in logs) {
      kcal += l.energyKcal;
      p += l.proteinG;
      c += l.carbG;
      f += l.fatG;
    }
    return DayTotals(calories: kcal, proteinG: p, carbG: c, fatG: f);
  }
}

/// The four meal slots, in display order.
enum Meal {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  dinner('dinner', 'Dinner'),
  snack('snack', 'Snack');

  const Meal(this.key, this.label);
  final String key; // matches food_logs.meal
  final String label;
}

/// Group a day's logs by meal slot (empty slots included, in order).
Map<Meal, List<FoodLog>> groupByMeal(Iterable<FoodLog> logs) {
  final map = {for (final m in Meal.values) m: <FoodLog>[]};
  for (final l in logs) {
    final m = Meal.values.where((m) => m.key == l.meal).firstOrNull;
    if (m != null) map[m]!.add(l);
  }
  return map;
}
