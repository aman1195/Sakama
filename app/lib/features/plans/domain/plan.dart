import '../../onboarding/domain/nutrition_targets.dart';

/// The Plan JSON contract (docs/architecture/04-plan-engine.md, ADR 0007).
///
/// Plans are DATA, not code: a diabetic plan, a muscle-gain plan and a
/// Tuesday-reset detox are the same engine reading different JSON. Parsing is
/// deliberately TOLERANT — unknown fields are ignored and never fatal, so an
/// AI- or user-authored plan can carry richer structure than this client
/// understands without breaking (forward-compat rule in the design note).
///
/// These are plain immutable classes (matching the sealed-value convention used
/// for SnapState / BarcodeResult) with hand-written `fromJson`, because the
/// tolerant parsing is the whole point and json_serializable would fight it.

/// The schema version this client understands. A plan tagged higher still
/// parses (unknown fields skipped); this gates any future breaking change.
const int kPlanSchemaVersion = 1;

int? _asInt(Object? v) => switch (v) {
      final int i => i,
      final double d => d.round(),
      final String s => int.tryParse(s) ?? double.tryParse(s)?.round(),
      _ => null,
    };

String? _asStr(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

List<String>? _asStrList(Object? v) => v is List
    ? v.map((e) => e?.toString()).whereType<String>().toList()
    : null;

/// A (possibly partial) set of nutrition targets. Every field is nullable so a
/// day type can override just what it changes and inherit the rest from
/// `targets_default`, and so anything the plan omits can fall back to the
/// computed maintenance default.
class PlanTargets {
  const PlanTargets({
    this.calories,
    this.proteinG,
    this.carbG,
    this.fatG,
    this.fiberG,
    this.waterMl,
  });

  final int? calories, proteinG, carbG, fatG, fiberG, waterMl;

  /// JSON shape: `{ calories, water_ml, macros: { protein_g, carb_g, fat_g,
  /// fiber_g } }`. `water_ml` also accepted at this level (targets_default).
  factory PlanTargets.fromJson(Map<String, dynamic> j) {
    final macros = j['macros'] is Map
        ? (j['macros'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return PlanTargets(
      calories: _asInt(j['calories']),
      proteinG: _asInt(macros['protein_g']),
      carbG: _asInt(macros['carb_g']),
      fatG: _asInt(macros['fat_g']),
      fiberG: _asInt(macros['fiber_g']),
      waterMl: _asInt(j['water_ml']),
    );
  }

  /// This set wins where present; [base] fills every field left null. Used to
  /// merge a day type's targets over the plan's `targets_default`.
  PlanTargets mergeOver(PlanTargets base) => PlanTargets(
        calories: calories ?? base.calories,
        proteinG: proteinG ?? base.proteinG,
        carbG: carbG ?? base.carbG,
        fatG: fatG ?? base.fatG,
        fiberG: fiberG ?? base.fiberG,
        waterMl: waterMl ?? base.waterMl,
      );

  /// Complete these targets into concrete [NutritionTargets], filling any field
  /// still null from [fallback] (the computed maintenance default). This is the
  /// last link in the fallback chain: day type → targets_default → computed.
  NutritionTargets toNutritionTargets(NutritionTargets fallback) =>
      NutritionTargets(
        calories: calories ?? fallback.calories,
        proteinG: proteinG ?? fallback.proteinG,
        carbG: carbG ?? fallback.carbG,
        fatG: fatG ?? fallback.fatG,
        fiberG: fiberG ?? fallback.fiberG,
        waterMl: waterMl ?? fallback.waterMl,
      );
}

/// An eating window, e.g. 08:00–20:00. Stored as minutes-of-day for cheap
/// comparison; the original "HH:mm" labels are kept for display.
class FastingWindow {
  const FastingWindow({required this.eatStart, required this.eatEnd});

  /// "HH:mm" as authored.
  final String eatStart, eatEnd;

  int get eatStartMin => _minutes(eatStart);
  int get eatEndMin => _minutes(eatEnd);

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return (h.clamp(0, 23)) * 60 + m.clamp(0, 59);
  }

  /// True when [minutesOfDay] is inside the eating window (inclusive start,
  /// exclusive end). Handles an overnight window (eat_start > eat_end), e.g.
  /// 20:00–04:00.
  bool isEatingAt(int minutesOfDay) {
    if (eatStartMin <= eatEndMin) {
      return minutesOfDay >= eatStartMin && minutesOfDay < eatEndMin;
    }
    return minutesOfDay >= eatStartMin || minutesOfDay < eatEndMin;
  }

  /// The complement of the eating window.
  bool isFastingAt(int minutesOfDay) => !isEatingAt(minutesOfDay);

  /// null when the field is absent or malformed (no window = no fast).
  static FastingWindow? fromJson(Object? v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final start = _asStr(m['eat_start']);
    final end = _asStr(m['eat_end']);
    if (start == null || end == null) return null;
    return FastingWindow(eatStart: start, eatEnd: end);
  }
}

/// A named kind of day with its own targets, window, food rules and checklist.
class DayType {
  const DayType({
    required this.label,
    this.targets = const PlanTargets(),
    this.fastingWindow,
    this.allowedFoods, // null = anything allowed
    this.blockedFoods = const [],
    this.checklist = const [],
  });

  final String label;
  final PlanTargets targets;
  final FastingWindow? fastingWindow;
  final List<String>? allowedFoods;
  final List<String> blockedFoods;
  final List<String> checklist;

  factory DayType.fromJson(String key, Map<String, dynamic> j) => DayType(
        label: _asStr(j['label']) ?? key,
        targets: j['targets'] is Map
            ? PlanTargets.fromJson((j['targets'] as Map).cast<String, dynamic>())
            : const PlanTargets(),
        fastingWindow: FastingWindow.fromJson(j['fasting_window']),
        allowedFoods: _asStrList(j['allowed_foods']),
        blockedFoods: _asStrList(j['blocked_foods']) ?? const [],
        checklist: _asStrList(j['checklist']) ?? const [],
      );
}

/// A declarative rule. The `effect` map is kept RAW: the engine reads the keys
/// it knows and skips the rest, so a plan can carry richer effects than this
/// client implements without breaking (forward-compat).
class PlanRule {
  const PlanRule({
    required this.id,
    this.whenDayType,
    this.beforeTime,
    this.afterTime,
    this.effect = const {},
    this.message,
  });

  final String id;
  final String? whenDayType;

  /// "HH:mm" bounds from `when`. A rule with `before` applies only earlier than
  /// that time; `after`, only later.
  final String? beforeTime, afterTime;
  final Map<String, dynamic> effect;
  final String? message;

  factory PlanRule.fromJson(Map<String, dynamic> j) {
    final when = j['when'] is Map
        ? (j['when'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return PlanRule(
      id: _asStr(j['id']) ?? '',
      whenDayType: _asStr(when['day_type']),
      beforeTime: _asStr(when['before']),
      afterTime: _asStr(when['after']),
      effect: j['effect'] is Map
          ? (j['effect'] as Map).cast<String, dynamic>()
          : const {},
      message: _asStr(j['message']),
    );
  }

  /// Whether this rule is in force for [dayTypeKey] at [minutesOfDay]. A null
  /// `whenDayType` means every day; before/after gate the time.
  bool appliesTo(String dayTypeKey, int minutesOfDay) {
    if (whenDayType != null && whenDayType != dayTypeKey) return false;
    if (beforeTime != null && minutesOfDay >= FastingWindow._minutes(beforeTime!)) {
      return false;
    }
    if (afterTime != null && minutesOfDay < FastingWindow._minutes(afterTime!)) {
      return false;
    }
    return true;
  }
}

/// Maps calendar days to day-type keys. Sealed: weekly by weekday, cyclic by
/// day-index from the plan start, or explicit by date.
sealed class Schedule {
  const Schedule();

  factory Schedule.fromJson(Object? v) {
    if (v is! Map) return const WeeklySchedule({});
    final m = v.cast<String, dynamic>();
    switch (_asStr(m['type'])) {
      case 'cyclic':
        return CyclicSchedule(_asStrList(m['cycle']) ?? const []);
      case 'explicit':
        final dates = <String, String>{};
        if (m['dates'] is Map) {
          (m['dates'] as Map).forEach((k, val) {
            final s = _asStr(val);
            if (s != null) dates[k.toString()] = s;
          });
        }
        return ExplicitSchedule(dates);
      case 'weekly':
      default:
        final map = <String, String>{};
        if (m['map'] is Map) {
          (m['map'] as Map).forEach((k, val) {
            final s = _asStr(val);
            if (s != null) map[k.toString().toLowerCase()] = s;
          });
        }
        return WeeklySchedule(map);
    }
  }
}

class WeeklySchedule extends Schedule {
  const WeeklySchedule(this.map);
  /// weekday key ('mon'..'sun') -> day-type key.
  final Map<String, String> map;
}

class CyclicSchedule extends Schedule {
  const CyclicSchedule(this.cycle);
  /// day-type keys repeated from the plan start, e.g. [normal, normal, reset].
  final List<String> cycle;
}

class ExplicitSchedule extends Schedule {
  const ExplicitSchedule(this.dates);
  /// "yyyy-MM-dd" -> day-type key.
  final Map<String, String> dates;
}

/// A whole plan config.
class Plan {
  const Plan({
    required this.schemaVersion,
    required this.id,
    required this.name,
    this.goal,
    this.source,
    this.durationDays,
    this.targetsDefault = const PlanTargets(),
    this.dayTypes = const {},
    this.schedule = const WeeklySchedule({}),
    this.rules = const [],
  });

  final int schemaVersion;
  final String id;
  final String name;
  final String? goal;
  final String? source;
  final int? durationDays;
  final PlanTargets targetsDefault;
  final Map<String, DayType> dayTypes;
  final Schedule schedule;
  final List<PlanRule> rules;

  /// Tolerant parse. Never throws on a well-formed JSON map: missing/oddly
  /// typed fields degrade to defaults so the engine always has something to run.
  factory Plan.fromJson(Map<String, dynamic> j) {
    final dayTypes = <String, DayType>{};
    if (j['day_types'] is Map) {
      (j['day_types'] as Map).forEach((k, val) {
        if (val is Map) {
          dayTypes[k.toString()] =
              DayType.fromJson(k.toString(), val.cast<String, dynamic>());
        }
      });
    }
    final rules = <PlanRule>[];
    if (j['rules'] is List) {
      for (final r in j['rules'] as List) {
        if (r is Map) rules.add(PlanRule.fromJson(r.cast<String, dynamic>()));
      }
    }
    return Plan(
      schemaVersion: _asInt(j['schema_version']) ?? kPlanSchemaVersion,
      id: _asStr(j['id']) ?? '',
      name: _asStr(j['name']) ?? 'Plan',
      goal: _asStr(j['goal']),
      source: _asStr(j['source']),
      durationDays: _asInt(j['duration_days']),
      targetsDefault: j['targets_default'] is Map
          ? PlanTargets.fromJson(
              (j['targets_default'] as Map).cast<String, dynamic>())
          : const PlanTargets(),
      dayTypes: dayTypes,
      schedule: Schedule.fromJson(j['schedule']),
      rules: rules,
    );
  }
}
