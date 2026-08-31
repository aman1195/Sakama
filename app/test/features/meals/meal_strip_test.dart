import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/presentation/quick_add_page.dart';
import 'package:sakama/features/foods/data/user_food_repository.dart';
import 'package:sakama/features/meals/data/meal_repository.dart';
import 'package:sakama/features/meals/domain/meal_item.dart';

/// One tap on a saved meal writes the diary rows — the whole point of the
/// feature, exercised through the real page against a real database.
void main() {
  late SakamaDatabase db;

  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const MaterialApp(home: Scaffold(body: QuickAddPage())),
    ));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('tapping a saved meal logs its foods and says what happened',
      (t) async {
    final foods = UserFoodRepository(db);
    final a = await foods.addCustom(
        name: 'roti', energyKcal: 100, servingGrams: 50);
    final b = await foods.addCustom(
        name: 'dal', energyKcal: 120, servingGrams: 150);
    await MealRepository(db).create(name: 'usual breakfast', items: [
      MealItem(userFoodId: a, servingQty: 2),
      MealItem(userFoodId: b, servingQty: 1),
    ]);

    await pump(t);
    expect(find.text('usual breakfast'), findsOneWidget);

    await t.tap(find.text('usual breakfast'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    final logs = await db.select(db.foodLogs).get();
    expect(logs, hasLength(2));
    expect(logs.map((l) => l.name).toSet(), {'roti', 'dal'});
    expect(logs.every((l) => l.loggedVia == 'meal'), isTrue);
    // 2 × 50 g @ 100/100g = 100 kcal; 1 × 150 g @ 120/100g = 180 kcal.
    expect(logs.fold<double>(0, (s, l) => s + l.energyKcal), 280);
    // The snackbar states the outcome rather than assuming it.
    expect(find.textContaining('Logged usual breakfast'), findsOneWidget);
    expect(find.textContaining('~280 kcal'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 50));
  });

  testWidgets('a meal whose foods vanished logs nothing and says so',
      (t) async {
    final foods = UserFoodRepository(db);
    final a = await foods.addCustom(
        name: 'roti', energyKcal: 100, servingGrams: 50);
    await MealRepository(db)
        .create(name: 'ghost', items: [MealItem(userFoodId: a)]);
    await foods.remove(a);

    await pump(t);
    await t.tap(find.text('ghost'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    expect(await db.select(db.foodLogs).get(), isEmpty);
    expect(find.textContaining('Nothing logged'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 50));
  });

  testWidgets('the New meal pill opens the builder', (t) async {
    await pump(t);
    await t.tap(find.text('New meal'));
    await t.pumpAndSettle();
    expect(find.text('A group of your saved foods, logged together in one tap.'),
        findsOneWidget);
    // With nothing saved, it explains instead of showing a void.
    expect(find.textContaining('No saved foods yet'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 50));
  });
}
