import 'plan.dart';
import 'plan_day.dart';

/// Interprets a [Plan] for a given calendar day. Pure and deterministic: the
/// date is always an argument, never read from the clock, so every resolution
/// is testable. This is the "engine" of ADR 0007 — all protocol-specific
/// behavior lives in the JSON it reads, not here.
class PlanInterpreter {
  const PlanInterpreter();

  static const _weekdayKeys = [
    'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun', // DateTime.weekday is 1..7
  ];

  /// Resolve which day-type key is in force on [date].
  ///
  /// - weekly: by weekday.
  /// - cyclic: by whole days since [planStart] (defaults to [date], i.e. index
  ///   0) modulo the cycle length.
  /// - explicit: by exact "yyyy-MM-dd"; days with no entry fall through.
  ///
  /// Falls back to 'normal' when the schedule yields no (or an unknown) key, and
  /// finally to the first declared day type, so the engine always resolves to a
  /// real day type when the plan has any.
  String resolveDayTypeKey(Plan plan, DateTime date, {DateTime? planStart}) {
    final scheduled = switch (plan.schedule) {
      WeeklySchedule(:final map) => map[_weekdayKeys[date.weekday - 1]],
      CyclicSchedule(:final cycle) => cycle.isEmpty
          ? null
          : cycle[_dayIndex(date, planStart) % cycle.length],
      ExplicitSchedule(:final dates) => dates[_dateKey(date)],
    };
    if (scheduled != null && plan.dayTypes.containsKey(scheduled)) {
      return scheduled;
    }
    if (plan.dayTypes.containsKey('normal')) return 'normal';
    return plan.dayTypes.keys.isNotEmpty ? plan.dayTypes.keys.first : 'normal';
  }

  /// Resolve the full [PlanDay] for [date]: day type, merged targets, window,
  /// food rules, checklist, and the rules scoped to this day type.
  PlanDay resolve(Plan plan, {required DateTime date, DateTime? planStart}) {
    final key = resolveDayTypeKey(plan, date, planStart: planStart);
    final dt = plan.dayTypes[key];
    final merged =
        (dt?.targets ?? const PlanTargets()).mergeOver(plan.targetsDefault);
    final rules = plan.rules
        .where((r) => r.whenDayType == null || r.whenDayType == key)
        .toList();
    return PlanDay(
      dayTypeKey: key,
      label: dt?.label ?? key,
      targets: merged,
      fastingWindow: dt?.fastingWindow,
      allowedFoods: dt?.allowedFoods,
      blockedFoods: dt?.blockedFoods ?? const [],
      checklist: dt?.checklist ?? const [],
      rules: rules,
    );
  }

  /// Whole days from [planStart] (date-only) to [date]. With no start, index 0.
  int _dayIndex(DateTime date, DateTime? planStart) {
    if (planStart == null) return 0;
    final a = DateTime.utc(date.year, date.month, date.day);
    final b = DateTime.utc(planStart.year, planStart.month, planStart.day);
    final diff = a.difference(b).inDays;
    return diff < 0 ? 0 : diff;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
