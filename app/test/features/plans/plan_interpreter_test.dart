import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';
import 'package:sakama/features/plans/domain/plan.dart';
import 'package:sakama/features/plans/domain/plan_interpreter.dart';

/// The design-note example plan (docs/architecture/04-plan-engine.md): weekly,
/// Tuesday = reset, everything else = normal.
const _weeklyPlanJson = '''
{
  "schema_version": 1,
  "id": "p1",
  "name": "4-Week Metabolic Reset",
  "goal": "detox",
  "source": "ai_generated",
  "duration_days": 28,
  "targets_default": {
    "calories": 1600,
    "macros": { "protein_g": 90, "carb_g": 150, "fat_g": 50, "fiber_g": 30 },
    "water_ml": 3000
  },
  "day_types": {
    "normal": {
      "label": "Normal day",
      "fasting_window": { "eat_start": "08:00", "eat_end": "20:00" },
      "blocked_foods": ["sugar"],
      "checklist": ["10k steps"]
    },
    "reset": {
      "label": "Tuesday reset",
      "targets": { "calories": 1200, "macros": { "protein_g": 80, "carb_g": 80, "fat_g": 40, "fiber_g": 35 } },
      "fasting_window": { "eat_start": "12:00", "eat_end": "20:00" },
      "allowed_foods": ["vegetables", "coconut_water"],
      "blocked_foods": ["grains", "dairy"],
      "checklist": ["Electrolytes", "3L water", "No solid food before 12:00"]
    }
  },
  "schedule": {
    "type": "weekly",
    "map": { "mon": "normal", "tue": "reset", "wed": "normal",
             "thu": "normal", "fri": "normal", "sat": "normal", "sun": "normal" }
  },
  "rules": [
    { "id": "reset_electrolytes", "when": { "day_type": "reset" },
      "effect": { "emphasize": ["electrolytes"] },
      "message": "Electrolytes matter on reset days." },
    { "id": "no_solids_am", "when": { "day_type": "reset", "before": "12:00" },
      "effect": { "block_logging": ["solid_food"] },
      "message": "No solid food before noon." }
  ]
}
''';

Plan _weeklyPlan() =>
    Plan.fromJson(jsonDecode(_weeklyPlanJson) as Map<String, dynamic>);

// 2026-07-27 is a Monday; 2026-07-28 a Tuesday.
final _monday = DateTime(2026, 7, 27);
final _tuesday = DateTime(2026, 7, 28);

void main() {
  const engine = PlanInterpreter();

  group('Tuesday reset (milestone exit test, engine level)', () {
    test('Tuesday resolves to the reset day type; Monday to normal', () {
      expect(engine.resolveDayTypeKey(_weeklyPlan(), _tuesday), 'reset');
      expect(engine.resolveDayTypeKey(_weeklyPlan(), _monday), 'normal');
    });

    test('reset day changes targets and checklist vs a normal day', () {
      final normal = engine.resolve(_weeklyPlan(), date: _monday);
      final reset = engine.resolve(_weeklyPlan(), date: _tuesday);

      expect(normal.targets.calories, 1600); // from targets_default
      expect(reset.targets.calories, 1200); // day type overrides
      expect(reset.label, 'Tuesday reset');
      expect(reset.checklist, contains('No solid food before 12:00'));
      expect(normal.checklist, isNot(contains('Electrolytes')));
    });
  });

  group('targets merge: day type over targets_default', () {
    test('reset inherits water from default, overrides macros', () {
      final reset = engine.resolve(_weeklyPlan(), date: _tuesday);
      expect(reset.targets.proteinG, 80); // overridden
      expect(reset.targets.waterMl, 3000); // inherited from default
    });

    test('toNutritionTargets fills a still-null field from the computed default',
        () {
      // A plan that sets only calories; everything else must fall back.
      final plan = Plan.fromJson({
        'id': 'x',
        'name': 'sparse',
        'targets_default': {'calories': 1800},
        'day_types': {
          'normal': {'label': 'n'}
        },
        'schedule': {
          'type': 'weekly',
          'map': {'mon': 'normal'}
        },
      });
      final day = engine.resolve(plan, date: _monday);
      const fallback = NutritionTargets(
          calories: 2000,
          proteinG: 120,
          carbG: 200,
          fatG: 60,
          fiberG: 30,
          waterMl: 2500);
      final done = day.targets.toNutritionTargets(fallback);
      expect(done.calories, 1800); // from the plan
      expect(done.proteinG, 120); // from the computed fallback
      expect(done.waterMl, 2500); // from the computed fallback
    });
  });

  group('rules', () {
    test('reset rules apply on reset days, gated by time bounds', () {
      final reset = engine.resolve(_weeklyPlan(), date: _tuesday);
      // Both reset rules are scoped to this day type.
      expect(reset.rules.map((r) => r.id),
          containsAll(['reset_electrolytes', 'no_solids_am']));
      // 09:00 (540 min): the no-solids-before-noon rule is active.
      expect(reset.rulesAt(9 * 60).map((r) => r.id), contains('no_solids_am'));
      // 13:00 (780 min): it has lapsed.
      expect(
          reset.rulesAt(13 * 60).map((r) => r.id), isNot(contains('no_solids_am')));
    });

    test('no reset rules leak onto a normal day', () {
      final normal = engine.resolve(_weeklyPlan(), date: _monday);
      expect(normal.rules, isEmpty);
    });

    test('an unknown effect key is preserved raw, never fatal', () {
      final plan = Plan.fromJson({
        'id': 'x',
        'name': 'future',
        'day_types': {
          'normal': {'label': 'n'}
        },
        'schedule': {
          'type': 'weekly',
          'map': {'mon': 'normal'}
        },
        'rules': [
          {
            'id': 'future_rule',
            'when': {'day_type': 'normal'},
            'effect': {'teleport_user': true} // a key this client doesn't know
          }
        ],
      });
      final day = engine.resolve(plan, date: _monday);
      expect(day.rules.single.effect['teleport_user'], true);
    });
  });

  group('fasting window', () {
    test('eating vs fasting inside/outside the window', () {
      final reset = engine.resolve(_weeklyPlan(), date: _tuesday);
      final w = reset.fastingWindow!;
      expect(w.isFastingAt(9 * 60), isTrue); // 09:00 before 12:00 eat_start
      expect(w.isEatingAt(13 * 60), isTrue); // 13:00 inside 12:00-20:00
      expect(w.isEatingAt(21 * 60), isFalse); // 21:00 after eat_end
    });
  });

  group('schedules', () {
    test('cyclic indexes by whole days from plan start', () {
      final plan = Plan.fromJson({
        'id': 'c',
        'name': 'cyclic',
        'day_types': {
          'a': {'label': 'A'},
          'b': {'label': 'B'}
        },
        'schedule': {
          'type': 'cyclic',
          'cycle': ['a', 'a', 'b']
        },
      });
      final start = DateTime(2026, 7, 1);
      // index 0,1 -> a; index 2 -> b; index 3 wraps -> a.
      expect(engine.resolveDayTypeKey(plan, DateTime(2026, 7, 1), planStart: start), 'a');
      expect(engine.resolveDayTypeKey(plan, DateTime(2026, 7, 3), planStart: start), 'b');
      expect(engine.resolveDayTypeKey(plan, DateTime(2026, 7, 4), planStart: start), 'a');
    });

    test('explicit dates win; unmapped days fall back to normal', () {
      final plan = Plan.fromJson({
        'id': 'e',
        'name': 'explicit',
        'day_types': {
          'normal': {'label': 'n'},
          'detox': {'label': 'd'}
        },
        'schedule': {
          'type': 'explicit',
          'dates': {'2026-07-15': 'detox'}
        },
      });
      expect(engine.resolveDayTypeKey(plan, DateTime(2026, 7, 15)), 'detox');
      expect(engine.resolveDayTypeKey(plan, DateTime(2026, 7, 16)), 'normal');
    });
  });

  group('forward-compat / tolerant parsing', () {
    test('unknown top-level fields are ignored, plan still parses', () {
      final plan = Plan.fromJson({
        'schema_version': 2, // newer than we implement
        'id': 'x',
        'name': 'newer',
        'moon_phase_targets': {'full': {}}, // unknown field
        'day_types': {
          'normal': {'label': 'n', 'vibe': 'chill'} // unknown day-type field
        },
        'schedule': {
          'type': 'weekly',
          'map': {'mon': 'normal'}
        },
      });
      expect(plan.schemaVersion, 2);
      expect(engine.resolve(plan, date: _monday).dayTypeKey, 'normal');
    });

    test('a schedule pointing at a missing day type falls back safely', () {
      final plan = Plan.fromJson({
        'id': 'x',
        'name': 'broken',
        'day_types': {
          'normal': {'label': 'n'}
        },
        'schedule': {
          'type': 'weekly',
          'map': {'tue': 'ghost'} // 'ghost' isn't defined
        },
      });
      expect(engine.resolveDayTypeKey(plan, _tuesday), 'normal');
    });

    test('numbers as strings parse (lenient AI output)', () {
      final t = PlanTargets.fromJson({
        'calories': '1500',
        'macros': {'protein_g': 100.0}
      });
      expect(t.calories, 1500);
      expect(t.proteinG, 100);
    });
  });
}
