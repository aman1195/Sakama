import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/onboarding/data/target_history_repository.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';

/// The point of this table is that HISTORY DOES NOT MOVE. Every test here is
/// really the same assertion from a different angle: a day is scored by the
/// target that was in force when it was lived, not by the one in force now.
void main() {
  late SakamaDatabase db;
  late TargetHistoryRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = TargetHistoryRepository(db);
  });
  tearDown(() => db.close());

  const t2400 = NutritionTargets(
      calories: 2400, proteinG: 120, carbG: 270, fatG: 80, fiberG: 30,
      waterMl: 2500);
  const t1900 = NutritionTargets(
      calories: 1900, proteinG: 140, carbG: 190, fatG: 60, fiberG: 30,
      waterMl: 2500);

  group('resolution', () {
    test('a day is scored by the target in force THAT day, not the newest',
        () async {
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      await repo.recordIfChanged(date: '2026-08-20', targets: t1900);
      final rows = await repo.all();

      // The regression this whole feature exists to prevent: before the goal
      // changed, the old number applies.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-10')?.calories, 2400);
      // On and after the change, the new one does.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-20')?.calories, 1900);
      expect(TargetHistoryRepository.resolve(rows, '2026-08-31')?.calories, 1900);
    });

    test('returns null before history begins — never zero, never today\'s', () async {
      await repo.recordIfChanged(date: '2026-08-20', targets: t1900);
      final rows = await repo.all();
      // A day nobody recorded a target for is UNSCORABLE. Answering 0 would
      // mark it over, and answering 1900 would be the original lie.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-19'), isNull);
    });

    test('empty history resolves to null', () {
      expect(TargetHistoryRepository.resolve(const [], '2026-08-31'), isNull);
    });

    test('resolution does not depend on row order', () async {
      await repo.recordIfChanged(date: '2026-08-20', targets: t1900);
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      final shuffled = (await repo.all()).reversed.toList();
      expect(
          TargetHistoryRepository.resolve(shuffled, '2026-08-10')?.calories, 2400);
    });
  });

  group('recording', () {
    test('unchanged targets write nothing — a normal day costs zero rows',
        () async {
      expect(await repo.recordIfChanged(date: '2026-08-01', targets: t2400), isTrue);
      expect(await repo.recordIfChanged(date: '2026-08-02', targets: t2400), isFalse);
      expect(await repo.recordIfChanged(date: '2026-08-03', targets: t2400), isFalse);
      expect((await repo.all()).length, 1);
    });

    test('a macro-only change still records — calories are not the whole target',
        () async {
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      const sameCalsMoreProtein = NutritionTargets(
          calories: 2400, proteinG: 160, carbG: 230, fatG: 80, fiberG: 30,
          waterMl: 2500);
      expect(
          await repo.recordIfChanged(
              date: '2026-08-05', targets: sameCalsMoreProtein),
          isTrue);
      expect(
          TargetHistoryRepository.resolve(await repo.all(), '2026-08-06')
              ?.proteinG,
          160);
    });

    test('two changes on one day leave one row, holding the last answer',
        () async {
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      await repo.recordIfChanged(date: '2026-08-01', targets: t1900);
      final rows = await repo.all();
      expect(rows.length, 1);
      expect(rows.single.calories, 1900);
    });

    test('records the source, so a number can say where it came from', () async {
      await repo.recordIfChanged(
          date: '2026-08-01', targets: t2400, source: 'plan');
      expect((await repo.all()).single.source, 'plan');
    });

    test('rejects an unknown source', () {
      expect(
          () => repo.recordIfChanged(
              date: '2026-08-01', targets: t2400, source: 'vibes'),
          throwsArgumentError);
    });

    test('rejects a zero calorie target — that is a null, not a goal', () {
      const zero = NutritionTargets(
          calories: 0, proteinG: 0, carbG: 0, fatG: 0, fiberG: 0, waterMl: 0);
      expect(() => repo.recordIfChanged(date: '2026-08-01', targets: zero),
          throwsArgumentError);
    });
  });

  group('seeding', () {
    test('covers days logged before the table existed, tagged seed', () async {
      final logs = FoodLogRepository(db);
      await logs.add(
          date: '2026-08-05', meal: 'lunch', name: 'dal', grams: 200,
          energyKcal: 180, proteinG: 9, carbG: 22, fatG: 6);

      final earliest = await repo.earliestLoggedDate();
      expect(earliest, '2026-08-05');

      await repo.seedIfEmpty(date: earliest!, targets: t2400);
      final rows = await repo.all();
      expect(rows.single.source, 'seed');
      // The day that was previously scored against today's number now has its
      // own answer.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-05')?.calories, 2400);
    });

    test('never overwrites real history', () async {
      await repo.recordIfChanged(date: '2026-08-20', targets: t1900);
      expect(await repo.seedIfEmpty(date: '2026-08-01', targets: t2400), isFalse);
      expect((await repo.all()).length, 1);
      // And the pre-history day stays unscorable rather than being back-filled
      // with a number nobody recorded.
      expect(TargetHistoryRepository.resolve(await repo.all(), '2026-08-01'),
          isNull);
    });

    test('earliestLoggedDate is null when nothing has been logged', () async {
      expect(await repo.earliestLoggedDate(), isNull);
    });
  });
}
