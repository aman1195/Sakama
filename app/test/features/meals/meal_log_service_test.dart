import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/foods/data/user_food_repository.dart';
import 'package:sakama/features/meals/data/meal_log_service.dart';
import 'package:sakama/features/meals/data/meal_repository.dart';
import 'package:sakama/features/meals/domain/meal_item.dart';

void main() {
  late SakamaDatabase db;
  late MealRepository meals;
  late UserFoodRepository userFoods;
  late MealLogService service;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    meals = MealRepository(db);
    userFoods = UserFoodRepository(db);
    service = MealLogService(
      meals: meals,
      userFoods: userFoods,
      foodLogs: FoodLogRepository(db),
    );
  });
  tearDown(() => db.close());

  /// A custom food: 100 kcal / 10 P / 12 C / 3 F per 100 g, 50 g serving.
  Future<String> roti() => userFoods.addCustom(
      name: 'roti', energyKcal: 100, proteinG: 10, carbG: 12, fatG: 3,
      servingLabel: '1 roti', servingGrams: 50);

  test('one tap becomes diary rows with scaled nutrition', () async {
    final id = await roti();
    final mealId = await meals.create(
        name: 'breakfast', items: [MealItem(userFoodId: id, servingQty: 2)]);
    final meal = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();

    final r = await service.log(meal, date: '2026-08-31', mealSlot: 'breakfast');

    expect(r.logged, 1);
    expect(r.skipped, 0);
    final log = await db.select(db.foodLogs).getSingle();
    // 2 × 50 g serving = 100 g of a 100 kcal/100 g food.
    expect(log.grams, 100);
    expect(log.energyKcal, 100);
    expect(log.proteinG, 10);
    expect(log.carbG, 12);
    expect(log.fatG, 3);
    expect(log.date, '2026-08-31');
    expect(log.meal, 'breakfast');
    expect(log.loggedVia, 'meal');
    expect(r.kcal, 100);
  });

  test('THE CONTAINMENT: logging writes food_logs and nowhere else', () async {
    // The licence boundary this feature was flagged for. Resolved nutrition
    // may reach food_logs (a historical record, ADR 0014's permitted copy) and
    // must never be cached back onto the meal — that would turn `meals` into
    // the OFF-derived branded-food catalogue docs/architecture/08 §3 prevents.
    final id = await roti();
    final mealId = await meals.create(
        name: 'b', items: [MealItem(userFoodId: id, servingQty: 1)]);
    final before = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();

    await service.log(before, date: '2026-08-31', mealSlot: 'lunch');

    final after = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();
    // Byte-identical items; only usage bookkeeping may move.
    expect(after.items, before.items);
    expect(after.name, before.name);
    expect(after.useCount, before.useCount + 1);
    for (final forbidden in ['energy', 'kcal', 'protein', 'carb', 'fat']) {
      expect(after.items.toLowerCase().contains(forbidden), isFalse,
          reason: 'resolved "$forbidden" must never be written back to a meal');
    }
    // The user_foods row is also untouched by logging.
    final uf = await db.select(db.userFoods).getSingle();
    expect(uf.energyKcal, 100);
  });

  test('a deleted saved food is skipped and said, not invented', () async {
    final keep = await roti();
    final gone = await userFoods.addCustom(name: 'dal', energyKcal: 120);
    final mealId = await meals.create(name: 'b', items: [
      MealItem(userFoodId: keep, servingQty: 1),
      MealItem(userFoodId: gone, servingQty: 1),
    ]);
    await userFoods.remove(gone);
    final meal = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();

    final r = await service.log(meal, date: '2026-08-31', mealSlot: 'dinner');

    expect(r.logged, 1);
    expect(r.skipped, 1, reason: 'the caller must be able to say "1 skipped"');
    expect(await db.select(db.foodLogs).get(), hasLength(1));
  });

  test('a food with no portion weight is skipped, not guessed', () async {
    // addCustom without servingGrams: per-100g values exist, but "one serving"
    // has no weight, so qty × serving is not computable. Inventing 100 g would
    // put a number nobody chose into a calorie total.
    final id = await userFoods.addCustom(name: 'mystery', energyKcal: 200);
    final mealId = await meals.create(
        name: 'b', items: [MealItem(userFoodId: id, servingQty: 1)]);
    final meal = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();

    final r = await service.log(meal, date: '2026-08-31', mealSlot: 'lunch');
    expect(r.logged, 0);
    expect(r.skipped, 1);
    expect(await db.select(db.foodLogs).get(), isEmpty);
  });

  test('a tap that logs nothing does not bump most-used ordering', () async {
    final id = await userFoods.addCustom(name: 'mystery', energyKcal: 200);
    final mealId = await meals.create(
        name: 'b', items: [MealItem(userFoodId: id, servingQty: 1)]);
    final meal = await (db.select(db.meals)
          ..where((t) => t.id.equals(mealId)))
        .getSingle();

    await service.log(meal, date: '2026-08-31', mealSlot: 'lunch');

    // Promoting a meal whose tap produced zero rows would rank failure first.
    expect(
        (await (db.select(db.meals)..where((t) => t.id.equals(mealId)))
                .getSingle())
            .useCount,
        0);
  });
}
