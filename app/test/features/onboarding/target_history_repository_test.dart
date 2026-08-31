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

      await repo.backfillIfUncovered(earliestLogged: earliest!, targets: t2400);
      final rows = await repo.all();
      expect(rows.single.source, 'seed');
      // The day that was previously scored against today's number now has its
      // own answer.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-05')?.calories, 2400);
    });

    test('still backfills when today is already recorded — logs arrive later',
        () async {
      // THE FRESH-INSTALL TRAP. A new phone on an existing account records
      // today at first frame, and only THEN does PowerSync deliver 60 days of
      // logs. A seed that only fires on an empty table is locked out forever,
      // and all that real history resolves to nothing.
      await repo.recordIfChanged(date: '2026-08-31', targets: t1900);
      expect(
          await repo.backfillIfUncovered(
              earliestLogged: '2026-07-02', targets: t2400),
          isTrue);

      final rows = await repo.all();
      expect(rows.length, 2);
      expect(TargetHistoryRepository.resolve(rows, '2026-07-02')?.calories, 2400);
      // And the row that was already there still governs its own day.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-31')?.calories, 1900);
    });

    test('no-ops when history already reaches back far enough', () async {
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      expect(
          await repo.backfillIfUncovered(
              earliestLogged: '2026-08-05', targets: t1900),
          isFalse);
      expect((await repo.all()).length, 1);
    });

    test('never overwrites a real row at the same date', () async {
      await repo.recordIfChanged(date: '2026-08-01', targets: t1900);
      await repo.backfillIfUncovered(earliestLogged: '2026-08-01', targets: t2400);
      final rows = await repo.all();
      expect(rows.single.calories, 1900,
          reason: 'the recorded answer wins over the approximation');
      expect(rows.single.source, 'computed');
    });

    test('earliestLoggedDate is null when nothing has been logged', () async {
      expect(await repo.earliestLoggedDate(), isNull);
    });
  });

  group('concurrency', () {
    test('two passes for one date leave ONE row, not two answers', () async {
      // The recorder fires from three listeners, and a midnight rollover that
      // also flips a plan's day type fires two of them in the same turn.
      // Without a transaction both passes see no row for today and both
      // INSERT — after which the diary and Vita can resolve the same day
      // differently, and the server drops the loser as a duplicate.
      await Future.wait([
        repo.recordIfChanged(date: '2026-08-31', targets: t1900),
        repo.recordIfChanged(date: '2026-08-31', targets: t1900),
      ]);
      expect((await repo.all()).length, 1);
    });

    test('a burst of differing targets still leaves one row for the day',
        () async {
      await Future.wait([
        repo.recordIfChanged(date: '2026-08-31', targets: t1900),
        repo.recordIfChanged(date: '2026-08-31', targets: t2400),
        repo.recordIfChanged(date: '2026-08-31', targets: t1900),
      ]);
      final rows = await repo.all();
      expect(rows.length, 1, reason: 'a date has exactly one answer');
      // Whichever won, resolution is unambiguous — that is the property that
      // matters, not which of two simultaneous writes landed last.
      expect(TargetHistoryRepository.resolve(rows, '2026-08-31'), isNotNull);
    });

    test('resolution is deterministic even if two rows share a date', () async {
      // Defence in depth: the server's unique index forbids this, but a device
      // mid-sync can hold it briefly. Ties break on updatedAt, so every reader
      // picks the same row.
      await repo.recordIfChanged(date: '2026-08-01', targets: t2400);
      final one = (await repo.all()).single;
      await db.into(db.targetHistory).insert(TargetHistoryCompanion.insert(
            id: 'duplicate',
            date: one.date,
            calories: 1200,
            proteinG: 100,
            carbG: 100,
            fatG: 40,
            fiberG: 25,
            waterMl: 2000,
            createdAt: one.createdAt + 10,
            updatedAt: one.updatedAt + 10, // newer wins
          ));
      final rows = await repo.all();
      expect(TargetHistoryRepository.resolve(rows, '2026-08-02')?.calories, 1200);
      expect(TargetHistoryRepository.resolve(rows.reversed.toList(), '2026-08-02')
          ?.calories,
          1200,
          reason: 'and it does not depend on the order rows arrive in');
    });
  });
}
