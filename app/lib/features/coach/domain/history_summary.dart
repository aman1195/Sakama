import '../../../core/db/database.dart';
import '../../home/domain/day_totals.dart';

/// What Vita can say about the past, as opposed to today.
///
/// The coach could only ever see TODAY, so "how many calories did I average
/// this week?" and "show me my weight trend" — the two questions a person
/// most naturally asks a coach — were unanswerable. That is not a missing
/// nicety: a tracker shows you today, and noticing a pattern over weeks is
/// most of what makes something a coach.
class HistorySummary {
  const HistorySummary({
    required this.days,
    required this.avgCalories,
    required this.avgProtein,
    required this.daysLogged,
    required this.daysOnTarget,
    this.weightChangeKg,
    this.weightDays,
  });

  final int days;
  final double avgCalories;
  final double avgProtein;
  final int daysLogged;

  /// Days WITHIN the target band, not merely under it. Under-eating is not
  /// success, and a summary that scores it as such teaches the wrong thing —
  /// the same rule the Diary summary follows.
  final int daysOnTarget;

  /// Net change over the window, kg. Null when there are fewer than two
  /// weigh-ins: one measurement is not a trend, and stating it as one invites
  /// a conclusion the data cannot support.
  final double? weightChangeKg;
  final int? weightDays;

  bool get isEmpty => daysLogged == 0;

  /// Averages are over DAYS THE USER LOGGED, not over the window.
  ///
  /// Dividing by the window would report someone who logged two good days out
  /// of seven as eating 500 kcal a day, which is both wrong and alarming. The
  /// count of logged days is reported separately so the average can be read
  /// with the right amount of trust.
  static HistorySummary from({
    required List<FoodLog> logs,
    required int windowDays,
    required int calorieTarget,
    List<WeightLog> weights = const [],
  }) {
    final byDay = <String, List<FoodLog>>{};
    for (final l in logs) {
      (byDay[l.date] ??= []).add(l);
    }
    if (byDay.isEmpty) {
      return HistorySummary(
        days: windowDays,
        avgCalories: 0,
        avgProtein: 0,
        daysLogged: 0,
        daysOnTarget: 0,
      );
    }

    final totals = byDay.values.map(DayTotals.fromLogs).toList();
    final kcal = totals.map((t) => t.calories).toList();
    final protein = totals.map((t) => t.proteinG).toList();
    final onTarget = calorieTarget <= 0
        ? 0
        : kcal
            .where((c) =>
                c >= calorieTarget * 0.85 && c <= calorieTarget * 1.05)
            .length;

    double? change;
    int? weightDays;
    if (weights.length >= 2) {
      // Dates are yyyy-MM-dd strings, which sort lexicographically.
      final sorted = [...weights]..sort((a, b) => a.date.compareTo(b.date));
      change = sorted.last.weightKg - sorted.first.weightKg;
      weightDays = DateTime.parse(sorted.last.date)
          .difference(DateTime.parse(sorted.first.date))
          .inDays;
    }

    return HistorySummary(
      days: windowDays,
      avgCalories: kcal.reduce((a, b) => a + b) / kcal.length,
      avgProtein: protein.reduce((a, b) => a + b) / protein.length,
      daysLogged: byDay.length,
      daysOnTarget: onTarget,
      weightChangeKg: change,
      weightDays: weightDays,
    );
  }

  /// A line for the grounding snapshot. Plain text: the model reads it, the
  /// user never sees it.
  String get promptLine {
    if (isEmpty) return 'No history logged in the last $days days.';
    final b = StringBuffer()
      ..write('Last $days days: logged on $daysLogged of them, ')
      ..write('averaging ${avgCalories.round()} kcal and ')
      ..write('${avgProtein.round()}g protein on the days they logged')
      ..write(daysOnTarget > 0
          ? ', $daysOnTarget within target range.'
          : '.');
    if (weightChangeKg != null) {
      final d = weightChangeKg!;
      final dir = d == 0
          ? 'unchanged'
          : '${d > 0 ? "up" : "down"} ${d.abs().toStringAsFixed(1)}kg';
      b.write(' Weight $dir over $weightDays days.');
    }
    return b.toString();
  }
}
