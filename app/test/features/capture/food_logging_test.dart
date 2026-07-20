import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/capture/presentation/quick_add_page.dart';
import 'package:sakama/features/home/domain/day_totals.dart';

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
    setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
    tearDown(() => db.close());

    Widget harness(Meal? meal) => ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(home: QuickAddPage(initialMeal: meal)),
        );

    testWidgets('validation blocks empty name and non-positive kcal',
        (tester) async {
      await tester.pumpWidget(harness(Meal.lunch));
      await tester.pump();

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
      await tester.pumpWidget(harness(Meal.dinner));
      await tester.pump();

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
  });
}
