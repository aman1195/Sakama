import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/home/presentation/log_entry_sheet.dart';

/// A logged row was write-only: no macros visible, no way to fix a wrong
/// estimate, no way to delete a mistake (`delete()` had no UI caller at all).
Future<void> _pumpFrames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FoodLogsCompanion _row({String via = 'vita'}) => FoodLogsCompanion.insert(
      id: 'e1',
      date: '2026-08-05',
      meal: 'dinner',
      name: 'Chana Masala',
      energyKcal: 200,
      proteinG: const Value(0),
      carbG: const Value(0),
      fatG: const Value(0),
      loggedVia: Value(via),
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _open(WidgetTester tester, SakamaDatabase db) async {
  await tester.binding.setSurfaceSize(const Size(500, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final entry = (await tester.runAsync(() => db.select(db.foodLogs).getSingle()))!;
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: MaterialApp(home: Scaffold(body: LogEntrySheet(entry: entry))),
  ));
  await _pumpFrames(tester);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('shows where the row came from, so a bad number is explicable',
      (tester) async {
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row()));
    await _open(tester, db);

    expect(find.textContaining('Logged by Vita'), findsOneWidget,
        reason: 'provenance (rule 7) is only useful if the user can see it');
    await _dispose(tester);
  });

  testWidgets('editing corrects the row AND re-marks it manual', (tester) async {
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row()));
    await _open(tester, db);

    // The exact repair the device report needed: zero macros -> real ones.
    await tester.enterText(find.bySemanticsIdentifier('log-edit-protein'), '9');
    await tester.enterText(find.bySemanticsIdentifier('log-edit-carb'), '35');
    await tester.enterText(find.bySemanticsIdentifier('log-edit-fat'), '9');
    await tester.enterText(find.bySemanticsIdentifier('log-edit-kcal'), '250');
    await tester.tap(find.bySemanticsIdentifier('log-edit-save'));
    await _pumpFrames(tester);

    final row = (await tester.runAsync(() => db.select(db.foodLogs).getSingle()))!;
    expect(row.proteinG, 9);
    expect(row.carbG, 35);
    expect(row.energyKcal, 250);
    expect(row.loggedVia, 'manual',
        reason: 'a hand-corrected row must not still claim Vita logged it');
    await _dispose(tester);
  });

  testWidgets('the meal slot can be corrected too', (tester) async {
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row()));
    await _open(tester, db);

    await tester.tap(find.text('Lunch'));
    await _pumpFrames(tester, 4);
    await tester.tap(find.bySemanticsIdentifier('log-edit-save'));
    await _pumpFrames(tester);

    final row = (await tester.runAsync(() => db.select(db.foodLogs).getSingle()))!;
    expect(row.meal, 'lunch',
        reason: 'the #98 nit: a wrongly-slotted entry needs a way back');
    await _dispose(tester);
  });

  testWidgets('remove asks first, then deletes', (tester) async {
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row()));
    await _open(tester, db);

    await tester.tap(find.bySemanticsIdentifier('log-edit-delete'));
    await _pumpFrames(tester, 6);
    expect(find.textContaining('Remove Chana Masala?'), findsOneWidget);

    // "Remove" is both the sheet button and the dialog's confirm — scope it.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Remove')));
    await _pumpFrames(tester);

    expect(await tester.runAsync(() => db.select(db.foodLogs).get()), isEmpty);
    await _dispose(tester);
  });

  testWidgets('a barcode row cannot be saved as a food (ODbL, rule 5)',
      (tester) async {
    // A barcode row's macros are Open Food Facts values copied into food_logs
    // (ADR 0014). Saving them here would write ODbL-derived nutrition into
    // `user_foods`, which syncs to our server — the merge the pointer scheme
    // exists to prevent. It cannot be pointer-saved either: food_logs keeps no
    // off_foods id. So the offer is withdrawn; saving happens at scan time.
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row(via: 'barcode')));
    await _open(tester, db);

    expect(find.bySemanticsIdentifier('log-edit-keep'), findsNothing);
    expect(find.text('Save food'), findsNothing);
    // Everything else about the row stays fully editable.
    expect(find.bySemanticsIdentifier('log-edit-save'), findsOneWidget);
    expect(find.bySemanticsIdentifier('log-edit-delete'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('a non-barcode row still offers the save', (tester) async {
    // The guard must be narrow: photo/manual/search/vita are all our own or
    // permissively licensed, so withdrawing the offer from them would be a
    // silent feature loss with no licence justification.
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row(via: 'photo')));
    await _open(tester, db);

    expect(find.bySemanticsIdentifier('log-edit-keep'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('log-edit-keep'));
    await _pumpFrames(tester);

    final saved = (await tester.runAsync(() => db.select(db.userFoods).get()))!;
    expect(saved, hasLength(1));
    expect(saved.single.kind, 'custom');
    await _dispose(tester);
  });

  testWidgets('an empty name or zero calories will not save', (tester) async {
    await tester.runAsync(() => db.into(db.foodLogs).insert(_row()));
    await _open(tester, db);

    await tester.enterText(find.bySemanticsIdentifier('log-edit-kcal'), '0');
    await tester.tap(find.bySemanticsIdentifier('log-edit-save'));
    await _pumpFrames(tester);

    final row = (await tester.runAsync(() => db.select(db.foodLogs).getSingle()))!;
    expect(row.energyKcal, 200, reason: 'the invalid edit was refused');
    await _dispose(tester);
  });
}
