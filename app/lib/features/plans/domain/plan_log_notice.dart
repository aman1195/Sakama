import 'plan_day.dart';

/// The plan reminders worth surfacing on the food-logging screen at a given
/// moment: whether the clock is outside the eating window, and which foods the
/// day's plan asks the user to avoid.
///
/// Advisory only — logging is never blocked (offline-first, user autonomy). Pure
/// and clock-as-argument so the decision is fully unit-testable; the widget just
/// renders it.
class PlanLogNotice {
  const PlanLogNotice({
    required this.outsideWindow,
    this.windowStart,
    this.windowEnd,
    this.avoidFoods = const [],
  });

  /// True when a fasting/eating window is defined and the clock is outside it.
  final bool outsideWindow;

  /// The eating window bounds ("HH:mm"), when one is defined.
  final String? windowStart, windowEnd;

  /// Foods the active day type asks the user to avoid (may be empty).
  final List<String> avoidFoods;

  bool get isEmpty => !outsideWindow && avoidFoods.isEmpty;

  /// The notice for [day] at [now], or null when there is no active plan or it
  /// has nothing to flag right now.
  static PlanLogNotice? forDay(PlanDay? day, DateTime now) {
    if (day == null) return null;
    final w = day.fastingWindow;
    final outside = w != null && !w.isEatingAt(now.hour * 60 + now.minute);
    final notice = PlanLogNotice(
      outsideWindow: outside,
      windowStart: w?.eatStart,
      windowEnd: w?.eatEnd,
      avoidFoods: day.blockedFoods,
    );
    return notice.isEmpty ? null : notice;
  }
}
