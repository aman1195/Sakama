import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/presentation/quick_add_page.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _seed(WidgetTester tester, SakamaDatabase db) =>
    tester.runAsync(() => db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'r1',
          date: '2026-08-04',
          meal: 'dinner',
          name: 'paneer bhurji',
          energyKcal: 320,
          proteinG: const Value(18),
          carbG: const Value(9),
          fatG: const Value(24),
          grams: const Value(180),
          createdAt: 1,
          updatedAt: 1,
        )));

Future<void> _mount(WidgetTester tester, SakamaDatabase db) async {
  await tester.binding.setSurfaceSize(const Size(500, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: const MaterialApp(home: QuickAddPage()),
  ));
  await _pumpFrames(tester);
}

void main() {
  testWidgets('a recent food is offered and re-logs the SAME portion',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db);
    await _mount(tester, db);

    // Offered as a one-tap chip.
    expect(find.textContaining('paneer bhurji'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('qa-recent-r1'));
    await _pumpFrames(tester, 6);

    await tester.tap(find.bySemanticsIdentifier('qa-save'));
    await _pumpFrames(tester);

    final rows = (await tester.runAsync(() => db.select(db.foodLogs).get()))!;
    final fresh = rows.firstWhere((r) => r.id != 'r1');
    expect(fresh.name, 'paneer bhurji');
    expect(fresh.energyKcal, 320, reason: 'the portion eaten is reused as-is');
    expect(fresh.grams, 180);
    expect(fresh.proteinG, 18);
    expect(fresh.meal, 'dinner', reason: 'the meal slot comes along too');
    expect(fresh.loggedVia, 'recent',
        reason: 'provenance must say where it really came from (rule 7)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('editing after picking a recent drops the provenance to manual',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db);
    await _mount(tester, db);

    await tester.tap(find.bySemanticsIdentifier('qa-recent-r1'));
    await _pumpFrames(tester, 6);
    // A hand edit means it is no longer the thing you logged before.
    await tester.enterText(find.bySemanticsIdentifier('qa-kcal'), '500');
    await tester.tap(find.bySemanticsIdentifier('qa-save'));
    await _pumpFrames(tester);

    final rows = (await tester.runAsync(() => db.select(db.foodLogs).get()))!;
    final fresh = rows.firstWhere((r) => r.id != 'r1');
    expect(fresh.loggedVia, 'manual',
        reason: 'an edited entry must not claim to be the remembered one');
    expect(fresh.energyKcal, 500);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('no history means no Recent section at all', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db);

    expect(find.text('Recent'), findsNothing,
        reason: 'an empty section is noise on a first-run screen');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
