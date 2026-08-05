import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';

void main() {
  late SakamaDatabase db;
  late FoodLogRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = FoodLogRepository(db);
  });
  tearDown(() => db.close());

  /// Insert directly so createdAt is explicit — wall-clock inserts can land in
  /// the same millisecond and make "newest" undefined.
  Future<void> log(String name, {required int at, double kcal = 180}) =>
      db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: '$name-$at',
            date: '2026-08-05',
            meal: 'lunch',
            name: name,
            energyKcal: kcal,
            createdAt: at,
            updatedAt: at,
          ));

  test('returns one row per distinct food, newest first', () async {
    await log('dal tadka', at: 1);
    await log('roti', at: 2);
    await log('dal tadka', at: 3); // eaten again, more recently

    final recent = await repo.recentDistinct();
    expect(recent.map((r) => r.name), ['dal tadka', 'roti'],
        reason: 'the repeat collapses, and its NEWEST occurrence leads');
    expect(recent.first.id, 'dal tadka-3');
  });

  test('dedupe is case- and whitespace-insensitive', () async {
    await log('Dal Tadka', at: 1);
    await log('  dal tadka  ', at: 2);

    final recent = await repo.recentDistinct();
    expect(recent.length, 1,
        reason: 'the same dish typed differently is still the same dish');
  });

  test('honours the limit', () async {
    for (var i = 0; i < 20; i++) {
      await log('food $i', at: i);
    }
    expect((await repo.recentDistinct(limit: 5)).length, 5);
  });

  test('carries the portion actually eaten, not a per-100g reference', () async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'x', date: '2026-08-05', meal: 'dinner', name: 'paneer bhurji',
          energyKcal: 320, proteinG: const Value(18), carbG: const Value(9),
          fatG: const Value(24), grams: const Value(180),
          createdAt: 9, updatedAt: 9,
        ));

    final r = (await repo.recentDistinct()).single;
    expect(r.energyKcal, 320, reason: 're-logging should reuse what was eaten');
    expect(r.grams, 180);
    expect(r.proteinG, 18);
    expect(r.meal, 'dinner');
  });

  test('empty history yields an empty list, not an error', () async {
    expect(await repo.recentDistinct(), isEmpty);
  });
}
