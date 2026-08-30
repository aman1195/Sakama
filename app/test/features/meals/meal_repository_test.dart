import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/meals/data/meal_repository.dart';
import 'package:sakama/features/meals/domain/meal_item.dart';

void main() {
  late SakamaDatabase db;
  late MealRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = MealRepository(db);
  });
  tearDown(() => db.close());

  const roti = MealItem(userFoodId: 'uf-roti', servingQty: 2);
  const dal = MealItem(userFoodId: 'uf-dal', servingQty: 1.5);

  test('stores ids and portions, and NO nutrition', () async {
    await repo.create(
        name: 'my usual breakfast', items: [roti, dal], defaultMeal: 'breakfast');
    final row = await db.select(db.meals).getSingle();

    // The licence constraint, asserted rather than trusted. A meal is a
    // reusable definition, so macros here would rebuild an OFF-derived
    // branded-food table on our infrastructure (docs/architecture/08 §3).
    for (final forbidden in [
      'energy_kcal', 'protein', 'carb', 'fat', 'kcal', 'per_100',
    ]) {
      expect(row.items.contains(forbidden), isFalse,
          reason: 'a meal must never carry "$forbidden"');
    }
    expect(row.items, contains('user_food_id'));

    final items = MealItem.decode(row.items);
    expect(items.map((i) => (i.userFoodId, i.servingQty)),
        [('uf-roti', 2.0), ('uf-dal', 1.5)]);
  });

  test('refuses an empty name and an empty meal', () async {
    expect(() => repo.create(name: '  ', items: [roti]),
        throwsA(isA<ArgumentError>()));
    // Logging an empty meal would silently do nothing while looking like it
    // worked.
    expect(() => repo.create(name: 'nothing', items: const []),
        throwsA(isA<ArgumentError>()));
    expect(await db.select(db.meals).get(), isEmpty);
  });

  test('refuses an unknown meal slot rather than defaulting', () async {
    // The server CHECK would reject it at sync time, which is a failure the
    // user never sees.
    expect(
        () => repo.create(name: 'x', items: [roti], defaultMeal: 'brunch'),
        throwsA(isA<ArgumentError>()));
  });

  test('most-used first, so the common path gets shorter', () async {
    final a = await repo.create(name: 'a', items: [roti]);
    final b = await repo.create(name: 'b', items: [dal]);
    await repo.markUsed(b);
    await repo.markUsed(b);
    await repo.markUsed(a);

    expect((await repo.watchAll().first).map((m) => m.name), ['b', 'a']);
  });

  test('markUsed on a missing meal is a no-op, not a crash', () async {
    await repo.markUsed('gone');
    expect(await db.select(db.meals).get(), isEmpty);
  });

  test('owner scoping matches only that owner, never everybody', () async {
    await repo.create(name: 'mine', items: [roti], userId: 'u1');
    await repo.create(name: 'theirs', items: [dal], userId: 'u2');
    await repo.create(name: 'pre-auth', items: [roti]);

    expect((await repo.watchAll(userId: 'u1').first).map((m) => m.name),
        ['mine']);
    // A null owner matches pre-auth rows only — not "all rows".
    expect((await repo.watchAll().first).map((m) => m.name), ['pre-auth']);
  });

  group('MealItem.decode', () {
    test('survives malformed stored JSON', () {
      expect(MealItem.decode('not json'), isEmpty);
      expect(MealItem.decode('{"user_food_id":"x"}'), isEmpty); // object
      expect(MealItem.decode('[]'), isEmpty);
      expect(MealItem.decode('[{"serving_qty":2}]'), isEmpty); // no id
      expect(MealItem.decode('[{"user_food_id":""}]'), isEmpty); // blank id
    });

    test('drops an item rather than inventing a quantity', () {
      // Defaulting a missing or absurd qty to 1 would log an amount nobody
      // chose, in a feature whose whole job is logging without re-deciding.
      for (final bad in ['0', '-1', '101', '"NaN"', '"Infinity"', 'null']) {
        expect(MealItem.decode('[{"user_food_id":"x","serving_qty":$bad}]'),
            isEmpty,
            reason: 'qty $bad must not become an item');
      }
    });

    test('round-trips unchanged', () {
      final back = MealItem.decode(MealItem.encode([roti, dal]));
      expect(back.map((i) => (i.userFoodId, i.servingQty)),
          [('uf-roti', 2.0), ('uf-dal', 1.5)]);
    });
  });

  test('a meal referencing a vanished food degrades, it does not crash',
      () async {
    // user_foods rows can be deleted. The meal keeps the id; resolution is the
    // caller's problem and must not be a null-deref here.
    await db.into(db.userFoods).insert(UserFoodsCompanion.insert(
          id: 'uf-roti', name: 'roti', kind: 'custom',
          createdAt: 1, updatedAt: 1,
        ));
    await repo.create(name: 'breakfast', items: [roti, dal]);
    await (db.delete(db.userFoods)..where((t) => t.id.equals('uf-roti'))).go();

    final items = MealItem.decode((await db.select(db.meals).getSingle()).items);
    expect(items, hasLength(2), reason: 'the meal is unchanged by the deletion');
  });
}
