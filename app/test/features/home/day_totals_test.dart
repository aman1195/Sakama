import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:drift/drift.dart' show Value;

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(String meal, String name, double kcal,
      {double p = 0, double c = 0, double f = 0}) async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: '$meal-$name', date: '2026-07-20', meal: meal, name: name,
          energyKcal: kcal, proteinG: Value(p), carbG: Value(c), fatG: Value(f),
          createdAt: 1, updatedAt: 1));
  }

  test('fromLogs sums calories and each macro', () async {
    await add('lunch', 'dal', 180, p: 9, c: 22, f: 6);
    await add('lunch', 'rice', 260, p: 5, c: 40, f: 8);
    final t = DayTotals.fromLogs(await db.select(db.foodLogs).get());
    expect(t.calories, 440);
    expect(t.proteinG, 14);
    expect(t.carbG, 62);
    expect(t.fatG, 14);
  });

  test('empty day totals are zero', () {
    const t = DayTotals();
    expect(t.calories, 0);
  });

  test('groupByMeal buckets every slot in order, empties included', () async {
    await add('breakfast', 'poha', 250);
    await add('dinner', 'roti', 100);
    await add('dinner', 'sabzi', 120);
    final g = groupByMeal(await db.select(db.foodLogs).get());
    expect(g.keys.toList(), Meal.values); // order preserved
    expect(g[Meal.breakfast]!.map((e) => e.name), ['poha']);
    expect(g[Meal.lunch], isEmpty);
    expect(g[Meal.dinner], hasLength(2));
  });
}
