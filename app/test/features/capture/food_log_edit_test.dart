import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/capture/domain/portion.dart';

void main() {
  late SakamaDatabase db;
  late FoodLogRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = FoodLogRepository(db);
  });
  tearDown(() => db.close());

  Future<String> seed({String date = '2026-08-28'}) async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'fl',
          date: date,
          meal: 'dinner',
          name: 'dal',
          energyKcal: 180,
          createdAt: 1,
          updatedAt: 1,
        ));
    return 'fl';
  }

  Future<void> edit(String id,
      {String? date, String? label, double? qty, double? grams}) =>
      repo.update(
        id: id,
        meal: 'dinner',
        name: 'dal',
        energyKcal: 180,
        proteinG: 9,
        carbG: 22,
        fatG: 6,
        grams: Value(grams),
        date: date,
        servingLabel: Value(label),
        servingQty: Value(qty),
      );

  group('moving an entry to another day', () {
    test('changes the date and keeps the same row', () async {
      final id = await seed(date: '2026-08-29'); // logged just after midnight
      await edit(id, date: '2026-08-28');

      final row = await db.select(db.foodLogs).getSingle();
      expect(row.id, id, reason: 'the entry moves, it is not recreated');
      expect(row.date, '2026-08-28');
      expect(row.energyKcal, 180);
    });

    test('omitting the date leaves it alone', () async {
      final id = await seed(date: '2026-08-28');
      await edit(id); // editing macros only
      expect((await db.select(db.foodLogs).getSingle()).date, '2026-08-28');
    });

    test('refuses a date that is not a real day', () async {
      final id = await seed();
      for (final bad in [
        '2026-13-01', // month 13
        '2026-02-30', // February has no 30th
        '26-08-28', // two-digit year
        '2026-8-28', // unpadded
        'today',
        '',
      ]) {
        expect(() => edit(id, date: bad), throwsA(isA<ArgumentError>()),
            reason: '$bad must not reach the diary');
      }
      // The row is untouched by every refusal.
      expect((await db.select(db.foodLogs).getSingle()).date, '2026-08-28');
    });
  });

  group('serving label and quantity', () {
    test('are stored together and grams stay the truth', () async {
      final id = await seed();
      await edit(id, label: 'katori', qty: 1.5, grams: 225);

      final row = await db.select(db.foodLogs).getSingle();
      expect(row.servingLabel, 'katori');
      expect(row.servingQty, 1.5);
      // Nutrition is computed from grams; the pair is only how it was said.
      expect(row.grams, 225);
      expect(row.energyKcal, 180);
    });

    test('a label with no quantity is refused, and the reverse', () async {
      final id = await seed();
      expect(() => edit(id, label: 'katori'), throwsA(isA<ArgumentError>()));
      expect(() => edit(id, qty: 1.5), throwsA(isA<ArgumentError>()));
      // The server CHECK would reject the half-written row at sync time, which
      // is a failure the user would never see.
      expect((await db.select(db.foodLogs).getSingle()).servingLabel, isNull);
    });

    test('a blank label counts as absent, not as a label', () async {
      final id = await seed();
      expect(() => edit(id, label: '   ', qty: 1.5),
          throwsA(isA<ArgumentError>()));
    });

    test('refuses a quantity that is not a portion', () async {
      final id = await seed();
      for (final bad in [0.0, -1.0, 101.0, double.nan, double.infinity]) {
        expect(() => edit(id, label: 'katori', qty: bad),
            throwsA(isA<ArgumentError>()),
            reason: 'qty $bad must not be stored');
      }
    });

    test('clearing the pair is possible', () async {
      final id = await seed();
      await edit(id, label: 'katori', qty: 2);
      expect((await db.select(db.foodLogs).getSingle()).servingQty, 2);
      // Switching back to plain grams drops both.
      await edit(id);
      final row = await db.select(db.foodLogs).getSingle();
      expect(row.servingLabel, isNull);
      expect(row.servingQty, isNull);
    });
  });

  test('an edit re-marks the row manual', () async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'v', date: '2026-08-28', meal: 'lunch', name: 'roti',
          energyKcal: 100, loggedVia: const Value('vita'),
          createdAt: 1, updatedAt: 1,
        ));
    await repo.update(
        id: 'v', meal: 'lunch', name: 'roti', energyKcal: 120,
        proteinG: 0, carbG: 0, fatG: 0);
    // Provenance follows the edit: a corrected row must not still claim Vita
    // produced these numbers.
    expect((await db.select(db.foodLogs).getSingle()).loggedVia, 'manual');
  });

  group('portionLabel', () {
    Future<FoodLog> row({double? grams, String? label, double? qty}) async {
      await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: 'p', date: '2026-08-28', meal: 'lunch', name: 'dal',
            energyKcal: 100, grams: Value(grams),
            servingLabel: Value(label), servingQty: Value(qty),
            createdAt: 1, updatedAt: 1,
          ));
      return db.select(db.foodLogs).getSingle();
    }

    test('prefers the stated portion over grams', () async {
      // The whole point: nobody weighs a katori, so show the number they can
      // check against the bowl rather than the one they must take on trust.
      expect(portionLabel(await row(grams: 225, label: 'katori', qty: 1.5)),
          '1.5 katori');
    });

    test('drops a trailing .0 but keeps a real half', () async {
      expect(portionLabel(await row(label: 'roti', qty: 2)), '2 roti');
      await db.delete(db.foodLogs).go();
      expect(portionLabel(await row(label: 'roti', qty: 2.5)), '2.5 roti');
    });

    test('falls back to grams when no portion was stated', () async {
      expect(portionLabel(await row(grams: 150)), '150 g');
    });

    test('returns null rather than inventing a serving', () async {
      // An entry with neither is common (AI estimates, quick adds). "1 serving"
      // would claim the user said something they did not.
      expect(portionLabel(await row()), isNull);
      await db.delete(db.foodLogs).go();
      expect(portionLabel(await row(grams: 0)), isNull);
    });
  });

  group('partial updates leave untouched columns alone', () {
    test('passing only the date does not blank grams or the portion', () async {
      // The bug this pins. `Value(grams)` was full-replace, so a future
      // "move to yesterday" swipe passing only a date would have silently
      // erased the portion and the weight. Same latent bug as
      // WorkoutRepository.update (#130 review).
      await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: 'p', date: '2026-08-29', meal: 'dinner', name: 'dal',
            energyKcal: 180, grams: const Value(225),
            servingLabel: const Value('katori'), servingQty: const Value(1.5),
            createdAt: 1, updatedAt: 1,
          ));

      await repo.update(
        id: 'p', meal: 'dinner', name: 'dal', energyKcal: 180,
        proteinG: 9, carbG: 22, fatG: 6,
        date: '2026-08-28', // the ONLY thing being changed
      );

      final row = await db.select(db.foodLogs).getSingle();
      expect(row.date, '2026-08-28');
      expect(row.grams, 225, reason: 'weight must survive a date-only edit');
      expect(row.servingLabel, 'katori');
      expect(row.servingQty, 1.5);
    });

    test('an explicit Value(null) still clears', () async {
      await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: 'c', date: '2026-08-28', meal: 'lunch', name: 'roti',
            energyKcal: 100, grams: const Value(80),
            servingLabel: const Value('roti'), servingQty: const Value(2),
            createdAt: 1, updatedAt: 1,
          ));
      await repo.update(
        id: 'c', meal: 'lunch', name: 'roti', energyKcal: 100,
        proteinG: 0, carbG: 0, fatG: 0,
        grams: const Value(null),
        servingLabel: const Value(null),
        servingQty: const Value(null),
      );
      final row = await db.select(db.foodLogs).getSingle();
      expect(row.grams, isNull);
      expect(row.servingLabel, isNull);
      expect(row.servingQty, isNull);
    });

    test('clearing one half of the pair without the other is refused', () async {
      await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: 'h', date: '2026-08-28', meal: 'lunch', name: 'roti',
            energyKcal: 100, servingLabel: const Value('roti'),
            servingQty: const Value(2), createdAt: 1, updatedAt: 1,
          ));
      expect(
          () => repo.update(
                id: 'h', meal: 'lunch', name: 'roti', energyKcal: 100,
                proteinG: 0, carbG: 0, fatG: 0,
                servingLabel: const Value(null), // qty left absent
              ),
          throwsA(isA<ArgumentError>()));
      expect((await db.select(db.foodLogs).getSingle()).servingQty, 2);
    });
  });
}
