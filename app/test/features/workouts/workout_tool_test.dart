import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/workouts/domain/workout_set.dart';

void main() {
  const parser = ToolCallParser();

  ({ToolDraft? draft, ToolRejection? rejection}) call(Map<String, Object?> a) =>
      parser.parse(jsonEncode({'tool': 'log_workout', 'arguments': a}));

  test('parses the PRD example: 3 sets of 10 bench press at 80kg', () {
    final r = call({
      'name': 'bench press',
      'kind': 'strength',
      'sets': List.generate(3, (_) => {'reps': 10, 'weight_kg': 80}),
    });
    final d = r.draft as LogWorkoutDraft;
    expect(d.name, 'bench press');
    expect(d.sets, hasLength(3));
    expect(d.sets.every((s) => s.reps == 10 && s.weightKg == 80), isTrue);
    expect(d.summary, 'bench press · 3 sets×10 @ 80 kg');
  });

  test('parses a cardio session with only a duration', () {
    final d = call({'name': 'evening run', 'kind': 'cardio', 'duration_min': 40})
        .draft as LogWorkoutDraft;
    expect(d.durationMin, 40);
    expect(d.sets, isEmpty);
    expect(d.summary, 'evening run · 40 min');
  });

  test('a bodyweight set keeps weight null, not 0', () {
    final d = call({
      'name': 'push ups',
      'kind': 'strength',
      'sets': [
        {'reps': 20},
      ],
    }).draft as LogWorkoutDraft;
    // 0 kg would read as a measured load in any later volume chart.
    expect(d.sets.single.weightKg, isNull);
  });

  test('refuses a workout with neither sets nor duration', () {
    // "I worked out" is a statement, not an entry.
    final r = call({'name': 'gym', 'kind': 'strength'});
    expect(r.draft, isNull);
    expect(r.rejection, ToolRejection.missingField);
  });

  test('refuses an unknown kind instead of defaulting to other', () {
    // The Supabase CHECK constraint would reject it at sync time, and that is
    // a failure the user would never see.
    final r = call({'name': 'run', 'kind': 'cardiovascular', 'duration_min': 20});
    expect(r.draft, isNull);
    expect(r.rejection, ToolRejection.outOfRange);
  });

  test('refuses out-of-range magnitudes', () {
    final cases = <String, Map<String, Object?>>{
      'duration beyond a day': {
        'name': 'walk', 'kind': 'cardio', 'duration_min': 1441,
      },
      'a lift above the world record': {
        'name': 'deadlift', 'kind': 'strength',
        'sets': [{'reps': 1, 'weight_kg': 1001}],
      },
      'impossible reps': {
        'name': 'squats', 'kind': 'strength',
        'sets': [{'reps': 1001}],
      },
      'negative load': {
        'name': 'squats', 'kind': 'strength',
        'sets': [{'reps': 5, 'weight_kg': -20}],
      },
      'too many sets': {
        'name': 'squats', 'kind': 'strength',
        'sets': List.generate(51, (_) => {'reps': 5}),
      },
    };
    cases.forEach((why, args) {
      expect(call(args).rejection, ToolRejection.outOfRange, reason: why);
    });
  });

  test('rejects non-finite numbers, which slip past range checks', () {
    // Every comparison against NaN is false, so a NaN would pass min AND max.
    // It arrives as a JSON string because JSON has no NaN literal.
    for (final bad in ['NaN', 'Infinity', '-Infinity']) {
      final r = call({
        'name': 'deadlift', 'kind': 'strength',
        'sets': [{'reps': 5, 'weight_kg': bad}],
      });
      expect(r.draft, isNull, reason: 'weight_kg $bad must not become a draft');
    }
  });

  test('the model cannot smuggle in a calorie burn', () {
    // energy_kcal is not in the schema and is not read. Burn is computed from
    // body weight, never taken from the model.
    final d = call({
      'name': 'evening run', 'kind': 'cardio', 'duration_min': 40,
      'energy_kcal': 9999,
    }).draft as LogWorkoutDraft;
    expect(d.durationMin, 40);
    expect(
      (d as dynamic).toString(),
      isNot(contains('9999')),
    );
  });

  test('WorkoutSet.decode survives malformed stored JSON', () {
    expect(WorkoutSet.decode('not json'), isEmpty);
    expect(WorkoutSet.decode('{"reps":5}'), isEmpty); // object, not a list
    expect(WorkoutSet.decode('[{"reps":0},{"reps":8}]'), hasLength(1));
    expect(WorkoutSet.decode('[]'), isEmpty);
  });

  test('a set round-trips through encode/decode unchanged', () {
    final sets = [
      const WorkoutSet(reps: 10, weightKg: 80),
      const WorkoutSet(reps: 20),
    ];
    final back = WorkoutSet.decode(WorkoutSet.encode(sets));
    expect(back.map((s) => (s.reps, s.weightKg)),
        [(10, 80.0), (20, null)]);
  });
}
