import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/presentation/quick_add_page.dart';
import 'package:sakama/features/foods/data/user_food_repository.dart';

Future<void> _pumpFrames(WidgetTester tester, [int n = 18]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(WidgetTester tester, SakamaDatabase db) async {
  await tester.binding.setSurfaceSize(const Size(500, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: const MaterialApp(home: QuickAddPage()),
  ));
  await _pumpFrames(tester);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late SakamaDatabase db;
  late UserFoodRepository foods;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    foods = UserFoodRepository(db);
  });
  tearDown(() => db.close());

  testWidgets('a saved food logs at YOUR portion, with saved provenance',
      (tester) async {
    // 140 kcal/100 g, saved portion 200 g -> 280 kcal for the entry.
    final id = await tester.runAsync(() => foods.addCustom(
          name: "mum's rajma",
          energyKcal: 140,
          proteinG: 8,
          carbG: 20,
          fatG: 3,
          servingGrams: 200,
        ));
    await _mount(tester, db);

    expect(find.textContaining("mum's rajma"), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('qa-favourite-$id'));
    await _pumpFrames(tester, 6);
    await tester.tap(find.bySemanticsIdentifier('qa-save'));
    await _pumpFrames(tester);

    final row = (await tester.runAsync(() => db.select(db.foodLogs).getSingle()))!;
    expect(row.name, "mum's rajma");
    expect(row.energyKcal, 280, reason: 'scaled from per-100g by YOUR portion');
    expect(row.proteinG, 16);
    expect(row.grams, 200);
    expect(row.loggedVia, 'saved',
        reason: 'provenance must say where it came from (rule 7)');
    await _dispose(tester);
  });

  testWidgets('logging a saved food bumps its use count (most-used ordering)',
      (tester) async {
    final id = await tester.runAsync(() => foods.addCustom(
        name: 'A', energyKcal: 100, servingGrams: 100));
    await _mount(tester, db);
    await tester.tap(find.bySemanticsIdentifier('qa-favourite-$id'));
    await _pumpFrames(tester, 6);
    await tester.tap(find.bySemanticsIdentifier('qa-save'));
    await _pumpFrames(tester);

    final row = (await tester.runAsync(
        () => (db.select(db.userFoods)..where((t) => t.id.equals(id!))).getSingle()))!;
    expect(row.useCount, 1);
    await _dispose(tester);
  });

  testWidgets('a saved food whose source vanished leaves the numbers blank',
      (tester) async {
    // A pointer to a corpus row that is no longer there (reseeded away).
    final id = await tester.runAsync(() => foods.addPointer(
          name: 'ghost dal',
          sourceTable: UserFoodRepository.sourceFoods,
          sourceId: 'gone',
          servingGrams: 150,
        ));
    await _mount(tester, db);

    // Still offered, and tapping does not put a silent zero in the form.
    await tester.tap(find.bySemanticsIdentifier('qa-favourite-$id'));
    await _pumpFrames(tester, 6);

    final kcal = tester.widget<TextField>(
        find.descendant(
            of: find.bySemanticsIdentifier('qa-kcal'),
            matching: find.byType(TextField)));
    expect(kcal.controller!.text, isEmpty,
        reason: 'blank for the user to complete — never a silent zero');
    await _dispose(tester);
  });

  testWidgets('no saved foods means no Saved section', (tester) async {
    await _mount(tester, db);
    expect(find.text('Saved'), findsNothing);
    await _dispose(tester);
  });
}
