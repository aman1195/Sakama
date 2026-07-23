import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/foods/data/food_seed.dart';
import 'package:sakama/features/settings/data/attribution_repository.dart';
import 'package:sakama/features/settings/domain/data_source_credit.dart';
import 'package:sakama/features/settings/presentation/data_sources_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

FoodSeedEntry _e(String id, String name, String source, String licence) =>
    FoodSeedEntry(
        id: id, name: name, type: 'ingredient', energyKcal: 100, proteinG: 1,
        carbG: 2, fatG: 3, source: source, licence: licence, confidence: 0.9);

Future<void> _insertOff(SakamaDatabase db, String id) =>
    db.into(db.offFoods).insert(OffFoodsCompanion.insert(
          id: id, name: 'Branded thing', type: 'branded', energyKcal: 100,
          proteinG: 1, carbG: 2, fatG: 3, source: 'openfoodfacts',
          licence: 'ODbL', confidence: 0.6, barcode: const Value('123'),
        ));

void main() {
  group('AttributionRepository', () {
    late SakamaDatabase db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('groups by (source, licence) with counts, sorted by size', () async {
      final repo = FoodRepositoryHarness(db);
      await repo.seed([
        _e('u1', 'Broccoli', 'usda_fdc', 'CC0'),
        _e('u2', 'Carrot', 'usda_fdc', 'CC0'),
        _e('s1', 'Dal', 'sample', 'CC0'),
      ]);
      final used = await AttributionRepository(db).usedSources();
      expect(used.map((u) => u.source), ['usda_fdc', 'sample']);
      expect(used.first.rowCount, 2);
      expect(used.every((u) => u.isOdbl == false), isTrue);
    });

    test('ODbL rows are reported separately and flagged', () async {
      final repo = FoodRepositoryHarness(db);
      await repo.seed([_e('u1', 'Broccoli', 'usda_fdc', 'CC0')]);
      await _insertOff(db, 'off1');
      final used = await AttributionRepository(db).usedSources();
      final off = used.firstWhere((u) => u.source == 'openfoodfacts');
      expect(off.isOdbl, isTrue,
          reason: 'ODbL rows must be flagged — different share-alike posture');
      expect(off.licence, 'ODbL');
    });
  });

  group('creditFor', () {
    test('known sources resolve to real attribution metadata', () {
      final usda = creditFor('usda_fdc', 'CC0');
      expect(usda.creator, contains('Department of Agriculture'));
      expect(usda.licenceUrl, isNotNull);
      expect(usda.modification, isNotNull, reason: 'CC BY §3(a)(1)(B) habit');
    });

    test('an UNKNOWN source renders loudly as uncredited, never blank', () {
      // The whole point of generating credits from data: a new source with no
      // attribution entry must be impossible to miss.
      final c = creditFor('mystery_corpus', 'Unknown');
      expect(c.creator, contains('Unknown'));
      expect(c.obligation, contains('UNVERIFIED'));
      expect(c.title, 'mystery_corpus');
    });
  });

  group('DataSourcesPage', () {
    late SakamaDatabase db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    testWidgets('renders a credit card per source + the OSS licences button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          foodSeedSourceProvider.overrideWithValue(InMemoryFoodSeed([
            _e('u1', 'Broccoli', 'usda_fdc', 'CC0'),
            _e('s1', 'Dal Tadka', 'sample', 'CC0'),
          ])),
        ],
        child: const MaterialApp(home: DataSourcesPage()),
      ));
      for (var i = 0;
          i < 40 &&
              find.bySemanticsIdentifier('credit-usda_fdc').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.bySemanticsIdentifier('credit-usda_fdc'), findsOneWidget);
      expect(find.bySemanticsIdentifier('credit-sample'), findsOneWidget);
      // The USDA credit shows creator + licence, satisfying our attribution.
      expect(find.textContaining('Department of Agriculture'), findsOneWidget);
      expect(find.bySemanticsIdentifier('oss-licences'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}

/// Thin helper so the attribution tests can seed `foods` without depending on
/// FoodRepository's version-gating semantics.
class FoodRepositoryHarness {
  FoodRepositoryHarness(this.db);
  final SakamaDatabase db;
  Future<void> seed(List<FoodSeedEntry> entries) async {
    await db.batch((b) {
      b.insertAll(db.foods, [
        for (final e in entries)
          FoodsCompanion.insert(
            id: e.id, name: e.name, type: e.type,
            energyKcal: e.energyKcal, proteinG: e.proteinG, carbG: e.carbG,
            fatG: e.fatG, source: e.source, licence: e.licence,
            confidence: e.confidence,
          ),
      ]);
    });
  }
}
