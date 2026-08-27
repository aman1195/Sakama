import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/workouts/data/workout_repository.dart';
import 'package:sakama/features/workouts/domain/workout_set.dart';
import 'package:sakama/features/coach/data/tool_executor.dart';
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/water/data/water_repository.dart';
import 'package:sakama/features/weight/data/weight_repository.dart';

void main() {
  late SakamaDatabase db;
  late WorkoutRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = WorkoutRepository(db);
  });
  tearDown(() => db.close());

  test('stores sets as JSON and reads them back intact', () async {
    await repo.add(
      date: '2026-08-27',
      name: 'bench press',
      sets: [
        const WorkoutSet(reps: 10, weightKg: 80),
        const WorkoutSet(reps: 8, weightKg: 85),
      ],
      loggedVia: 'vita',
    );
    final row = await db.select(db.workouts).getSingle();
    expect(row.name, 'bench press');
    expect(row.loggedVia, 'vita');
    expect(row.energyKcal, isNull, reason: 'unknown burn stays unknown');
    final sets = WorkoutSet.decode(row.sets);
    expect(sets.map((s) => (s.reps, s.weightKg)), [(10, 80.0), (8, 85.0)]);
  });

  test('refuses an empty name and an unknown kind', () async {
    expect(() => repo.add(date: '2026-08-27', name: '   '),
        throwsA(isA<ArgumentError>()));
    expect(() => repo.add(date: '2026-08-27', name: 'run', kind: 'cardiovascular'),
        throwsA(isA<ArgumentError>()));
    expect(await db.select(db.workouts).get(), isEmpty);
  });

  test('renaming a row does not wipe its other columns', () async {
    // The bug this pins: writing Value(durationMin) unconditionally meant an
    // edit that only changed the name silently NULLed the duration, the burn
    // and the notes.
    final id = await repo.add(
      date: '2026-08-27',
      name: 'evening run',
      kind: 'cardio',
      durationMin: 30,
      energyKcal: 412,
      notes: 'felt easy',
    );
    await repo.update(id: id, name: 'morning run');

    final row = await db.select(db.workouts).getSingle();
    expect(row.name, 'morning run');
    expect(row.durationMin, 30);
    expect(row.energyKcal, 412);
    expect(row.notes, 'felt easy');
  });

  test('clearing a nullable column is still possible, and distinct', () async {
    final id = await repo.add(
        date: '2026-08-27', name: 'run', kind: 'cardio', durationMin: 30);
    // Value(null) means clear; Value.absent() (the default) means leave alone.
    await repo.update(id: id, durationMin: const Value(null));
    expect((await db.select(db.workouts).getSingle()).durationMin, isNull);
  });

  test('update refuses an empty name and an unknown kind', () async {
    final id = await repo.add(date: '2026-08-27', name: 'run', kind: 'cardio');
    expect(() => repo.update(id: id, name: '  '), throwsA(isA<ArgumentError>()));
    expect(() => repo.update(id: id, kind: 'cardiovascular'),
        throwsA(isA<ArgumentError>()));
    // The row is untouched by a refused edit.
    expect((await db.select(db.workouts).getSingle()).name, 'run');
  });

  test('editing a Vita-logged row re-marks it manual', () async {
    final id = await repo.add(
        date: '2026-08-27', name: 'squat', loggedVia: 'vita');
    await repo.update(id: id, name: 'front squat');
    final row = await db.select(db.workouts).getSingle();
    expect(row.name, 'front squat');
    // Provenance must follow the edit, exactly as a corrected food row does.
    expect(row.loggedVia, 'manual');
  });

  test('dayBurn skips unknowns instead of counting them as zero', () async {
    await repo.add(
        date: '2026-08-27', name: 'run', kind: 'cardio', energyKcal: 380);
    await repo.add(date: '2026-08-27', name: 'bench', kind: 'strength');
    await repo.add(date: '2026-08-27', name: 'squat', kind: 'strength');

    final rows = await repo.watchDay('2026-08-27').first;
    final burn = WorkoutRepository.dayBurn(rows);
    expect(burn.kcal, 380);
    // The count is reported so the UI can say "plus 2 without an estimate"
    // rather than quietly under-reporting the day.
    expect(burn.unknown, 2);
  });

  test('watchDay returns only that day, newest first', () async {
    var at = DateTime(2026, 8, 27, 9);
    final r = WorkoutRepository(db, now: () => at);
    await r.add(date: '2026-08-27', name: 'morning walk', kind: 'cardio');
    at = DateTime(2026, 8, 27, 18);
    await r.add(date: '2026-08-27', name: 'evening lift');
    await repo.add(date: '2026-08-26', name: 'yesterday');

    final today = await r.watchDay('2026-08-27').first;
    expect(today.map((w) => w.name), ['evening lift', 'morning walk']);
  });

  test('watchSince spans a window across days', () async {
    await repo.add(date: '2026-08-20', name: 'old');
    await repo.add(date: '2026-08-25', name: 'recent');
    await repo.add(date: '2026-08-27', name: 'today');
    final rows = await repo.watchSince('2026-08-24').first;
    expect(rows.map((w) => w.name), ['today', 'recent']);
  });

  test('delete removes the row', () async {
    final id = await repo.add(date: '2026-08-27', name: 'run', kind: 'cardio');
    await repo.delete(id);
    expect(await db.select(db.workouts).get(), isEmpty);
  });

  group('via ToolExecutor', () {
    ToolExecutor exec({double? bodyWeightKg}) => ToolExecutor(
          foodLogs: FoodLogRepository(db),
          water: WaterRepository(db),
          weight: WeightRepository(db),
          workouts: repo,
          bodyWeightKg: bodyWeightKg,
        );

    test('computes the burn from body weight for a known cardio activity',
        () async {
      await exec(bodyWeightKg: 80).execute(
        const LogWorkoutDraft(
            name: 'evening run', kind: 'cardio', durationMin: 30),
        date: '2026-08-27',
      );
      final row = await db.select(db.workouts).getSingle();
      expect(row.energyKcal, closeTo(412, 2)); // 9.8*3.5*80/200*30
      expect(row.loggedVia, 'vita');
    });

    test('leaves the burn null when we do not know the body weight', () async {
      await exec().execute(
        const LogWorkoutDraft(
            name: 'evening run', kind: 'cardio', durationMin: 30),
        date: '2026-08-27',
      );
      final row = await db.select(db.workouts).getSingle();
      // Not 0, and not an average person's burn.
      expect(row.energyKcal, isNull);
    });

    test('a strength set gets no burn, only the sets', () async {
      final line = await exec(bodyWeightKg: 80).execute(
        const LogWorkoutDraft(
          name: 'bench press',
          kind: 'strength',
          sets: [WorkoutSet(reps: 10, weightKg: 80)],
        ),
        date: '2026-08-27',
      );
      final row = await db.select(db.workouts).getSingle();
      // No duration, so nothing to compute a burn from.
      expect(row.energyKcal, isNull);
      expect(WorkoutSet.decode(row.sets), hasLength(1));
      expect(line, contains('bench press'));
    });
  });
}
