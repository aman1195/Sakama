import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/foods/data/user_food_repository.dart';

void main() {
  late SakamaDatabase db;
  late UserFoodRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = UserFoodRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seedCorpus() =>
      db.into(db.foods).insert(FoodsCompanion.insert(
            id: 'dal-1', name: 'Dal Tadka', type: 'dish',
            energyKcal: 120, proteinG: 6, carbG: 15, fatG: 4,
            source: 'sample', licence: 'proprietary', confidence: 0.9,
          ));

  Future<void> seedOff() =>
      db.into(db.offFoods).insert(OffFoodsCompanion.insert(
            id: 'off-1', name: 'Branded Biscuit', type: 'branded',
            energyKcal: 480, proteinG: 6, carbG: 68, fatG: 20,
            source: 'openfoodfacts', licence: 'ODbL-1.0', confidence: 0.6,
          ));

  group('licence containment (CLAUDE.md rule 5)', () {
    test('an OFF favourite stores NO nutrition — only a pointer', () async {
      await seedOff();
      final id = await repo.addPointer(
        name: 'my biscuit',
        sourceTable: UserFoodRepository.sourceOffFoods,
        sourceId: 'off-1',
        servingGrams: 30,
      );

      final row = await (db.select(db.userFoods)..where((t) => t.id.equals(id)))
          .getSingle();
      // The guarantee: no ODbL value is copied into this SYNCED table.
      expect(row.energyKcal, isNull);
      expect(row.proteinG, isNull);
      expect(row.carbG, isNull);
      expect(row.fatG, isNull);
      expect(row.fiberG, isNull);
      expect(row.sourceTable, 'off_foods');
      expect(row.sourceId, 'off-1');
    });

    test('nutrition is still shown, read from the source at display time',
        () async {
      await seedOff();
      final id = await repo.addPointer(
        name: 'my biscuit',
        sourceTable: UserFoodRepository.sourceOffFoods,
        sourceId: 'off-1',
        servingGrams: 30,
      );
      final row = await (db.select(db.userFoods)..where((t) => t.id.equals(id)))
          .getSingle();

      final resolved = await repo.resolve(row);
      expect(resolved.energyKcal, 480, reason: 'followed, not copied');
      expect(resolved.portionKcal, closeTo(144, 0.01)); // 480 * 30/100
    });
  });

  group('pointers degrade instead of crashing', () {
    test('a vanished OFF target leaves a completable entry', () async {
      // No seedOff(): the live-lookup cache (ADR 0014) has been evicted.
      final id = await repo.addPointer(
        name: 'my biscuit',
        sourceTable: UserFoodRepository.sourceOffFoods,
        sourceId: 'gone',
      );
      final row = await (db.select(db.userFoods)..where((t) => t.id.equals(id)))
          .getSingle();

      final resolved = await repo.resolve(row);
      expect(resolved.nutritionMissing, isTrue);
      expect(resolved.energyKcal, isNull,
          reason: 'null, NOT zero — a silent zero would corrupt totals');
      expect(resolved.row.name, 'my biscuit', reason: 'still tappable');
    });

    test('a reseeded-away corpus target degrades the same way', () async {
      final id = await repo.addPointer(
        name: 'dal',
        sourceTable: UserFoodRepository.sourceFoods,
        sourceId: 'nope',
      );
      final row = await (db.select(db.userFoods)..where((t) => t.id.equals(id)))
          .getSingle();
      expect((await repo.resolve(row)).nutritionMissing, isTrue);
    });
  });

  test('a custom food carries its own values', () async {
    final id = await repo.addCustom(
      name: "mum's rajma",
      energyKcal: 140,
      proteinG: 8,
      carbG: 20,
      fatG: 3,
      servingGrams: 200,
    );
    final row =
        await (db.select(db.userFoods)..where((t) => t.id.equals(id))).getSingle();
    expect(row.kind, 'custom');
    expect(row.sourceId, isNull);

    final resolved = await repo.resolve(row);
    expect(resolved.energyKcal, 140);
    expect(resolved.portionKcal, closeTo(280, 0.01)); // 140 * 200/100
  });

  test('a pointer FOLLOWS its source when the source changes', () async {
    await seedCorpus();
    final id = await repo.addPointer(
      name: 'dal',
      sourceTable: UserFoodRepository.sourceFoods,
      sourceId: 'dal-1',
    );
    // The corpus is corrected in a later seed.
    await (db.update(db.foods)..where((t) => t.id.equals('dal-1')))
        .write(const FoodsCompanion(energyKcal: Value(135)));

    final row =
        await (db.select(db.userFoods)..where((t) => t.id.equals(id))).getSingle();
    expect((await repo.resolve(row)).energyKcal, 135,
        reason: 'following is why no value had to be copied in the first place');
  });

  test('most-used ordering puts the shortcut people take first', () async {
    final a = await repo.addCustom(name: 'A', energyKcal: 100, userId: 'u1');
    await repo.addCustom(name: 'B', energyKcal: 100, userId: 'u1');
    await repo.markUsed(a);
    await repo.markUsed(a);

    final rows = await repo.watchAll('u1').first;
    expect(rows.first.name, 'A');
    expect(rows.first.useCount, 2);
  });

  test('user_id scoping matches every other per-user read', () async {
    await repo.addCustom(name: 'mine', energyKcal: 100, userId: 'userA');
    expect(await repo.watchAll('userB').first, isEmpty);
    expect(await repo.watchAll(null).first, isEmpty,
        reason: 'null matches only pre-auth rows, never everybody');
  });

  test('rename and remove', () async {
    final id = await repo.addCustom(name: 'old', energyKcal: 100);
    await repo.rename(id, 'new');
    expect((await repo.watchAll(null).first).single.name, 'new');
    await repo.remove(id);
    expect(await repo.watchAll(null).first, isEmpty);
  });
}
