import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/foods/data/food_repository.dart';
import 'package:sakama/features/foods/data/food_seed.dart';

void main() {
  late SakamaDatabase db;
  late FoodRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = FoodRepository(db);
  });
  tearDown(() => db.close());

  test('ensureSeeded loads the sample once and is idempotent', () async {
    await repo.ensureSeeded();
    final first = await db.select(db.foods).get();
    expect(first.length, kFoodSeed.length);
    // Every row honestly tagged — no faked provenance (CLAUDE.md rule 7).
    expect(first.every((r) => r.source == 'sample' && r.licence == 'CC0'),
        isTrue);
    expect(first.every((r) => r.confidence == 0.5), isTrue);

    await repo.ensureSeeded(); // second call is a no-op
    expect((await db.select(db.foods).get()).length, kFoodSeed.length);
  });

  test('search matches by name and ranks; empty query returns nothing',
      () async {
    await repo.ensureSeeded();
    expect(await repo.search(''), isEmpty);

    final dal = await repo.search('dal');
    expect(dal, isNotEmpty);
    expect(dal.first.name.toLowerCase(), contains('dal'));
    // Every result actually matches the query.
    expect(dal.every((f) => f.name.toLowerCase().contains('dal')), isTrue);

    // A pick carries per-100g macros ready to scale to a portion.
    final rice = (await repo.search('cooked rice')).first;
    expect(rice.per100g.energyKcal, greaterThan(0));
    expect(rice.defaultServingGrams, isNotNull);
  });

  test('search respects the limit', () async {
    await repo.ensureSeeded();
    final results = await repo.search('a', limit: 3); // 'a' matches many
    expect(results.length, lessThanOrEqualTo(3));
  });

  test('off_foods stays empty — ODbL table is separate and unseeded', () async {
    await repo.ensureSeeded();
    expect(await db.select(db.offFoods).get(), isEmpty);
  });
}
