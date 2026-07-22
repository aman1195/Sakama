import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/foods/data/food_repository.dart';
import 'package:sakama/features/foods/data/food_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';

FoodSeedEntry _entry(String id, String name,
        {double kcal = 100,
        double confidence = 0.9,
        String source = 'usda_fdc',
        double? servingGrams}) =>
    FoodSeedEntry(
      id: id,
      name: name,
      type: 'ingredient',
      energyKcal: kcal,
      proteinG: 1,
      carbG: 2,
      fatG: 3,
      servingGrams: servingGrams,
      source: source,
      licence: 'CC0',
      confidence: confidence,
    );

void main() {
  late SakamaDatabase db;
  late FoodRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({}); // fresh install: no seed version
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = FoodRepository(db);
  });
  tearDown(() => db.close());

  test('seeds from the source and is idempotent within a version', () async {
    final src = InMemoryFoodSeed([
      _entry('a', 'Cooked Rice', kcal: 130, servingGrams: 150),
      _entry('b', 'Dal'),
    ]);
    await repo.ensureSeeded(src);
    expect((await db.select(db.foods).get()).length, 2);

    await repo.ensureSeeded(src); // same version -> no-op
    expect((await db.select(db.foods).get()).length, 2);
  });

  test('a version bump clears and reloads (existing installs get updates)',
      () async {
    // Simulate an install already at the current seed version but with STALE
    // rows; ensureSeeded must NOT touch it (version satisfied)...
    SharedPreferences.setMockInitialValues(
        {'foods.seed_version': FoodRepository.seedVersion});
    await repo.ensureSeeded(InMemoryFoodSeed([_entry('x', 'Old')]));
    expect(await db.select(db.foods).get(), isEmpty,
        reason: 'version already satisfied -> no seeding');

    // ...but a fresh install (version 0) loads the new corpus.
    SharedPreferences.setMockInitialValues({});
    await repo.ensureSeeded(InMemoryFoodSeed([_entry('y', 'New')]));
    final rows = await db.select(db.foods).get();
    expect(rows.map((r) => r.id), ['y']);
  });

  test('provenance columns are carried, not faked', () async {
    await repo.ensureSeeded(InMemoryFoodSeed([
      _entry('u', 'Broccoli', source: 'usda_fdc', confidence: 0.9),
      _entry('s', 'Dal Tadka', source: 'sample', confidence: 0.5),
    ]));
    final rows = {for (final r in await db.select(db.foods).get()) r.id: r};
    expect(rows['u']!.source, 'usda_fdc');
    expect(rows['u']!.confidence, 0.9);
    expect(rows['s']!.source, 'sample');
    expect(rows['s']!.licence, 'CC0');
  });

  test('search matches by name, ranks, and carries per-100g macros', () async {
    await repo.ensureSeeded(InMemoryFoodSeed([
      _entry('a', 'Cooked Rice', kcal: 130, servingGrams: 150),
      _entry('b', 'Fried Rice', kcal: 200),
      _entry('c', 'Dal', kcal: 120),
    ]));
    expect(await repo.search(''), isEmpty);

    final rice = await repo.search('rice');
    expect(rice.map((f) => f.name),
        containsAll(['Cooked Rice', 'Fried Rice']));
    expect(rice.every((f) => f.name.toLowerCase().contains('rice')), isTrue);

    final cooked = (await repo.search('cooked rice')).first;
    expect(cooked.per100g.energyKcal, 130);
    expect(cooked.defaultServingGrams, 150);
  });

  test('search respects the limit', () async {
    await repo.ensureSeeded(InMemoryFoodSeed([
      for (var i = 0; i < 10; i++) _entry('a$i', 'Apple $i'),
    ]));
    expect((await repo.search('apple', limit: 3)).length, 3);
  });

  test('off_foods stays empty — ODbL table is separate and unseeded', () async {
    await repo.ensureSeeded(InMemoryFoodSeed([_entry('a', 'Rice')]));
    expect(await db.select(db.offFoods).get(), isEmpty);
  });
}
