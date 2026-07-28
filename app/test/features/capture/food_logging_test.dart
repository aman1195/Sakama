import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/capture/presentation/quick_add_page.dart';
import 'package:sakama/features/foods/data/ai_estimator.dart';
import 'package:sakama/features/foods/data/food_seed.dart';
import 'package:sakama/features/foods/domain/food_estimate.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny corpus so search tests never load the 1.5 MB USDA asset.
FoodSeedEntry _seed(String id, String name, double kcal, double servingGrams) =>
    FoodSeedEntry(
      id: id, name: name, type: 'dish', energyKcal: kcal, proteinG: 2,
      carbG: 28, fatG: 1, servingLabel: '1 katori', servingGrams: servingGrams,
      source: 'sample', licence: 'CC0', confidence: 0.5);

class _FakeEstimator implements AiEstimator {
  _FakeEstimator({this.fail = false});
  final bool fail;
  int calls = 0;
  @override
  Future<FoodEstimate> estimate(String dishName) async {
    calls++;
    if (fail) throw EstimateException('daily limit', budgetExhausted: true);
    return const FoodEstimate(
        name: 'Misal Pav', energyKcal: 180, proteinG: 7, carbG: 20, fatG: 8,
        servingLabel: '1 plate', servingGrams: 250, confidence: 0.35,
        assumptions: 'moderate oil');
  }
}

void main() {
  group('FoodLogRepository', () {
    late SakamaDatabase db;
    late FoodLogRepository repo;
    setUp(() {
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      repo = FoodLogRepository(db);
    });
    tearDown(() => db.close());

    test('add writes a row that watchDay streams back', () async {
      final id = await repo.add(
          date: '2026-07-20', meal: 'lunch', name: 'dal tadka',
          energyKcal: 180, proteinG: 9, carbG: 22, fatG: 6);
      final rows = await repo.watchDay('2026-07-20').first;
      expect(rows, hasLength(1));
      expect(rows.single.id, id);
      expect(rows.single.name, 'dal tadka');
      expect(rows.single.loggedVia, 'quick_add');
    });

    test('delete removes it', () async {
      final id = await repo.add(
          date: '2026-07-20', meal: 'lunch', name: 'x', energyKcal: 1);
      await repo.delete(id);
      expect(await repo.watchDay('2026-07-20').first, isEmpty);
    });

    test('watchDay is scoped to the day', () async {
      await repo.add(date: '2026-07-20', meal: 'lunch', name: 'a', energyKcal: 1);
      await repo.add(date: '2026-07-19', meal: 'lunch', name: 'b', energyKcal: 1);
      expect(await repo.watchDay('2026-07-20').first, hasLength(1));
    });
  });

  group('QuickAddPage', () {
    late SakamaDatabase db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Widget harness(Meal? meal) => ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            foodSeedSourceProvider.overrideWithValue(InMemoryFoodSeed([
              _seed('sample-rice', 'Cooked Rice', 130, 150),
              _seed('sample-dal', 'Dal Tadka', 120, 150),
            ])),
          ],
          child: MaterialApp(home: QuickAddPage(initialMeal: meal)),
        );

    // Tall surface: the form (search + meal + name + optional grams + 4 macro
    // fields + save) exceeds the default 600px, and off-screen ListView
    // children are not built, so the save button would be unfindable.
    Future<void> pumpTall(WidgetTester tester, Meal? meal) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(harness(meal));
      await tester.pump();
    }

    testWidgets('validation blocks empty name and non-positive kcal',
        (tester) async {
      await pumpTall(tester, Meal.lunch);

      // Save with nothing filled -> validation errors, nothing written.
      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      expect(find.text('Required'), findsWidgets);
      expect(await db.select(db.foodLogs).get(), isEmpty);

      // Zero kcal is rejected.
      await tester.enterText(find.bySemanticsIdentifier('qa-name'), 'roti');
      await tester.enterText(find.bySemanticsIdentifier('qa-kcal'), '0');
      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      expect(find.text('Must be greater than 0'), findsOneWidget);
      expect(await db.select(db.foodLogs).get(), isEmpty);
    });

    testWidgets('a valid entry persists to the preselected meal', (tester) async {
      await pumpTall(tester, Meal.dinner);

      await tester.enterText(find.bySemanticsIdentifier('qa-name'), 'paneer');
      await tester.enterText(find.bySemanticsIdentifier('qa-kcal'), '250');
      await tester.enterText(find.bySemanticsIdentifier('qa-protein'), '14');
      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rows = await db.select(db.foodLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'paneer');
      expect(rows.single.meal, 'dinner');
      expect(rows.single.energyKcal, 250);
      expect(rows.single.proteinG, 14);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('search → pick derives macros from grams and logs via search',
        (tester) async {
      await pumpTall(tester, Meal.lunch);

      // Type a corpus food; the repo seeds itself + searches (both async).
      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'cooked rice');
      for (var i = 0;
          i < 40 && find.text('Cooked Rice').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Cooked Rice'), findsOneWidget,
          reason: 'search result should appear');

      await tester.tap(find.text('Cooked Rice'));
      await tester.pump();

      // Picking reveals the grams field and derives the macros (sample rice is
      // 130 kcal/100 g, default serving 150 g -> 195 kcal).
      expect(find.bySemanticsIdentifier('qa-grams'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rows = await db.select(db.foodLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Cooked Rice');
      expect(rows.single.meal, 'lunch');
      expect(rows.single.loggedVia, 'search',
          reason: 'a corpus pick must be provenance-tagged as search');
      expect(rows.single.grams, 150);
      expect(rows.single.energyKcal, closeTo(195, 0.5),
          reason: 'macros derived from per-100g × grams/100');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('editing the name after a pick reverts to manual provenance',
        (tester) async {
      await pumpTall(tester, Meal.lunch);
      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'cooked rice');
      for (var i = 0;
          i < 40 && find.text('Cooked Rice').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Cooked Rice'));
      await tester.pump();
      // Hand-edit the name: it is no longer the picked food.
      await tester.enterText(find.bySemanticsIdentifier('qa-name'), 'My Rice');
      await tester.pump();
      expect(find.bySemanticsIdentifier('qa-grams'), findsNothing,
          reason: 'grams field is only for a picked food');

      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rows = await db.select(db.foodLogs).get();
      expect(rows.single.name, 'My Rice');
      expect(rows.single.loggedVia, 'manual');
      expect(rows.single.grams, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('editing a MACRO after a pick also reverts to manual (#32)',
        (tester) async {
      await pumpTall(tester, Meal.lunch);
      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'cooked rice');
      for (var i = 0;
          i < 40 && find.text('Cooked Rice').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Cooked Rice'));
      await tester.pump();
      expect(find.bySemanticsIdentifier('qa-grams'), findsOneWidget);

      // Hand-edit the CALORIES: the row no longer equals scaleTo(grams) of the
      // picked food, so keeping loggedVia='search' would be false provenance.
      await tester.enterText(find.bySemanticsIdentifier('qa-kcal'), '999');
      await tester.pump();
      expect(find.bySemanticsIdentifier('qa-grams'), findsNothing,
          reason: 'the picked-food link is dropped on a nutrition edit');

      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rows = await db.select(db.foodLogs).get();
      expect(rows.single.energyKcal, 999);
      expect(rows.single.loggedVia, 'manual',
          reason: 'hand-edited macros must not claim corpus provenance');
      expect(rows.single.grams, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('no results → AI estimate → prefilled pick logged as search',
        (tester) async {
      final fake = _FakeEstimator();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          foodSeedSourceProvider.overrideWithValue(InMemoryFoodSeed([
            _seed('sample-rice', 'Cooked Rice', 130, 150),
          ])),
          aiEstimatorProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: QuickAddPage(initialMeal: Meal.lunch)),
      ));
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pump();

      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'misal pav');
      for (var i = 0;
          i < 40 &&
              find.bySemanticsIdentifier('qa-estimate').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.bySemanticsIdentifier('qa-estimate'), findsOneWidget,
          reason: 'zero results should offer AI estimation');

      await tester.tap(find.bySemanticsIdentifier('qa-estimate'));
      for (var i = 0;
          i < 40 && find.text('Misal Pav').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fake.calls, 1);
      // Estimate flows into the picked-food path: grams visible, name filled.
      expect(find.bySemanticsIdentifier('qa-grams'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('qa-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final logs = await db.select(db.foodLogs).get();
      expect(logs.single.name, 'Misal Pav');
      expect(logs.single.grams, 250); // default serving from the estimate
      expect(logs.single.energyKcal, closeTo(450, 0.5)); // 180/100g × 250g
      // Reference row persisted with honest provenance.
      final foods = await db.select(db.foods).get();
      expect(foods.map((f) => f.source), contains('ai_estimate'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('estimator failure shows the budget message, nothing logged',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          foodSeedSourceProvider.overrideWithValue(InMemoryFoodSeed([
            _seed('sample-rice', 'Cooked Rice', 130, 150),
          ])),
          aiEstimatorProvider.overrideWithValue(_FakeEstimator(fail: true)),
        ],
        child: const MaterialApp(home: QuickAddPage(initialMeal: Meal.lunch)),
      ));
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pump();
      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'misal pav');
      for (var i = 0;
          i < 40 &&
              find.bySemanticsIdentifier('qa-estimate').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.bySemanticsIdentifier('qa-estimate'));
      for (var i = 0;
          i < 40 &&
              find.bySemanticsIdentifier('qa-estimate-error').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('Daily AI limit'), findsOneWidget);
      expect(await db.select(db.foodLogs).get(), isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('search is debounced — no results before the delay elapses',
        (tester) async {
      await pumpTall(tester, Meal.lunch);
      await tester.enterText(
          find.bySemanticsIdentifier('qa-search'), 'cooked rice');
      // Well inside the 250ms debounce window: the query must not have run.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Cooked Rice'), findsNothing,
          reason: 'a keystroke should not fire a query immediately');

      // After the window (plus async seed+search), results arrive.
      for (var i = 0;
          i < 40 && find.text('Cooked Rice').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Cooked Rice'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
