import 'plan.dart';

/// The plan resolved for one calendar day: which day type is in force, the
/// merged targets, the eating window, food rules, checklist, and the rules that
/// apply. This is what the dashboard, the log-enforcement surfaces, and Vita
/// all read — the engine's single output type.
class PlanDay {
  const PlanDay({
    required this.dayTypeKey,
    required this.label,
    required this.targets,
    this.fastingWindow,
    this.allowedFoods,
    this.blockedFoods = const [],
    this.checklist = const [],
    this.rules = const [],
  });

  /// The resolved day-type key, e.g. 'reset'.
  final String dayTypeKey;

  /// Human label for the day type, e.g. 'Tuesday reset'.
  final String label;

  /// Targets for the day: day-type targets merged over `targets_default`. May
  /// still hold nulls where the plan is silent; complete them with
  /// [PlanTargets.toNutritionTargets] against the computed default.
  final PlanTargets targets;

  final FastingWindow? fastingWindow;

  /// null = anything allowed; else the only foods (ids/tags) permitted today.
  final List<String>? allowedFoods;
  final List<String> blockedFoods;
  final List<String> checklist;

  /// Rules whose `when.day_type` matches this day (time bounds still apply per
  /// [PlanRule.appliesTo] at the moment of logging).
  final List<PlanRule> rules;

  /// Rules in force at [minutesOfDay] (applies the before/after time bounds).
  List<PlanRule> rulesAt(int minutesOfDay) =>
      rules.where((r) => r.appliesTo(dayTypeKey, minutesOfDay)).toList();
}
