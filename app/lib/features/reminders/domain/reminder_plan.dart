import '../../home/domain/day_totals.dart';

/// What a reminder is for. The kind decides its copy, and whether it is the
/// sort of thing that should ever be suppressed.
enum ReminderKind {
  /// "You haven't logged lunch." Suppressed when the slot already has food —
  /// see [ReminderPlan.due].
  meal,

  /// Weigh-in day.
  weighIn,

  /// The eating window is about to open or close (plans only).
  fastingEdge,

  /// One line about yesterday, in the morning.
  morningNudge,

  /// The week, on Sunday.
  weeklyDigest,
}

/// A reminder the user has asked for.
///
/// QUIET BY DEFAULT, ALL OPT-IN (system design A8). Nothing here schedules
/// itself: a health app that notifies without being asked is the reason people
/// turn notifications off for the whole category, and there is no coming back
/// from that.
class ReminderSetting {
  const ReminderSetting({
    required this.kind,
    required this.enabled,
    this.minuteOfDay,
    this.meal,
    this.weekday,
  });

  final ReminderKind kind;
  final bool enabled;

  /// Minutes past local midnight. Local because the device owns the timezone —
  /// computing this on a server would fire 08:00 IST at whatever hour the
  /// server thinks it is.
  final int? minuteOfDay;

  /// Which slot, for [ReminderKind.meal].
  final Meal? meal;

  /// 1 = Monday … 7 = Sunday, for weekly reminders.
  final int? weekday;
}

/// One reminder that should actually fire.
class DueReminder {
  const DueReminder({required this.kind, required this.minuteOfDay, this.meal});
  final ReminderKind kind;
  final int minuteOfDay;
  final Meal? meal;

  @override
  String toString() => '${kind.name}${meal == null ? '' : ':${meal!.key}'}'
      '@$minuteOfDay';

  @override
  bool operator ==(Object other) =>
      other is DueReminder &&
      other.kind == kind &&
      other.minuteOfDay == minuteOfDay &&
      other.meal == meal;

  @override
  int get hashCode => Object.hash(kind, minuteOfDay, meal);
}

/// Decides which reminders are worth showing for a given day.
///
/// PURE, so the judgement is testable without a notification permission, a
/// platform channel, or a clock. The plumbing that shows them is a separate
/// concern; this is the part that decides whether a person is interrupted.
class ReminderPlan {
  const ReminderPlan();

  /// The reminders that should fire on [date], given what has been logged.
  ///
  /// THE SUPPRESSION RULE IS THE WHOLE FEATURE. A meal reminder that fires
  /// after you have already logged lunch is not a reminder, it is a lie about
  /// your own diary — and it teaches people that this app's notifications are
  /// not worth reading. So a meal slot with food in it is silent, always,
  /// regardless of settings.
  List<DueReminder> due({
    required DateTime date,
    required Iterable<ReminderSetting> settings,
    required Set<Meal> loggedMeals,
    required bool weighedToday,
  }) {
    final out = <DueReminder>[];
    for (final s in settings) {
      if (!s.enabled || s.minuteOfDay == null) continue;

      switch (s.kind) {
        case ReminderKind.meal:
          // Nothing to remind about.
          if (s.meal == null || loggedMeals.contains(s.meal)) continue;
        case ReminderKind.weighIn:
          // Same rule, different slot: already done means already quiet.
          if (weighedToday) continue;
          if (s.weekday != null && s.weekday != date.weekday) continue;
        case ReminderKind.weeklyDigest:
          if (s.weekday != null && s.weekday != date.weekday) continue;
        case ReminderKind.fastingEdge:
        case ReminderKind.morningNudge:
          break;
      }

      out.add(DueReminder(
          kind: s.kind, minuteOfDay: s.minuteOfDay!, meal: s.meal));
    }
    out.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    return out;
  }

  /// The edges of an eating window, as reminders.
  ///
  /// Only meaningful with a plan that has one. `null` in, nothing out — a user
  /// without a fasting plan must never be told their window is closing.
  List<DueReminder> fastingEdges({
    required int? eatStartMin,
    required int? eatEndMin,
    required bool enabled,
    Duration warning = const Duration(minutes: 30),
  }) {
    if (!enabled || eatStartMin == null || eatEndMin == null) return const [];
    // Warn BEFORE the window closes, not as it shuts. A notification that says
    // "you can no longer eat" arrives too late to be a reminder and lands as a
    // reprimand.
    final closeWarn = eatEndMin - warning.inMinutes;
    return [
      DueReminder(kind: ReminderKind.fastingEdge, minuteOfDay: eatStartMin),
      if (closeWarn > eatStartMin)
        DueReminder(kind: ReminderKind.fastingEdge, minuteOfDay: closeWarn),
    ];
  }
}
