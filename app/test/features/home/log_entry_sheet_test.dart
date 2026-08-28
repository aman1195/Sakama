import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/home/presentation/log_entry_sheet.dart';

/// The two edits people make constantly and previously could not: moving an
/// entry to the right day, and saying the portion the way they think about it.
void main() {
  late SakamaDatabase db;

  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<FoodLog> seed({
    String date = '2026-08-28',
    double kcal = 200,
    double? grams,
    String? label,
    double? qty,
  }) async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'fl',
          date: date,
          meal: 'dinner',
          name: 'dal',
          energyKcal: kcal,
          proteinG: const Value(10),
          grams: Value(grams),
          servingLabel: Value(label),
          servingQty: Value(qty),
          createdAt: 1,
          updatedAt: 1,
        ));
    return db.select(db.foodLogs).getSingle();
  }

  Future<void> pump(WidgetTester t, FoodLog entry) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp(home: Scaffold(body: LogEntrySheet(entry: entry))),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the date is shown and is changeable', (t) async {
    final entry = await seed(date: '2026-08-28');
    await pump(t, entry);
    // The control exists at all, which it did not before.
    expect(find.bySemanticsLabel(RegExp('.*')), findsWidgets);
    expect(find.text('Change'), findsOneWidget);
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
    // A picker opens rather than the tap doing nothing.
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('stepping the portion scales the numbers with it', (t) async {
    final entry = await seed(kcal: 200, grams: 100, label: 'katori', qty: 1);
    await pump(t, entry);

    expect(find.text('1'), findsWidgets);
    await t.tap(find.byTooltip('Larger portion'));
    await t.pump();

    // 1 -> 1.5 katori, so everything derived from the portion moves with it.
    // A portion control that changed only the label would be a lie.
    expect(find.text('1.5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '300'), findsOneWidget); // kcal
    expect(find.widgetWithText(TextField, '150'), findsOneWidget); // grams
  });

  testWidgets('the portion cannot be stepped below zero', (t) async {
    final entry = await seed(kcal: 200, label: 'katori', qty: 0.5);
    await pump(t, entry);
    await t.tap(find.byTooltip('Smaller portion'));
    await t.pump();
    // 0.5 - 0.5 = 0, which is not a portion, so nothing moves.
    expect(find.text('0.5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '200'), findsOneWidget);
  });

  testWidgets('an entry with no stated portion shows a dash, not a fake 1',
      (t) async {
    final entry = await seed(grams: 150);
    await pump(t, entry);
    // Every row logged before this feature has no portion. Showing "1" would
    // claim the user said something they did not.
    expect(find.text('—'), findsOneWidget);
  });
}
