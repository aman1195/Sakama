import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/plans/data/plan_repository.dart';
import 'package:sakama/features/plans/presentation/plans_page.dart';

const _config = '{"schema_version":1,"id":"p","name":"Reset",'
    '"day_types":{"normal":{"label":"Normal day"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"normal",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _seed(WidgetTester tester, SakamaDatabase db,
        {required String id, required String name, required bool active}) =>
    tester.runAsync(() => db.into(db.userPlans).insert(UserPlansCompanion.insert(
          id: id, name: name, config: _config,
          active: Value(active), createdAt: 1, updatedAt: 1)));

Future<void> _mount(WidgetTester tester, SakamaDatabase db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: const MaterialApp(home: PlansPage()),
  ));
  await _pumpFrames(tester);
}

Future<List<UserPlanRow>> _all(WidgetTester tester, SakamaDatabase db) async =>
    (await tester.runAsync(() => PlanRepository(db).watchAll().first))!;

/// Replace the tree so the page's drift-stream subscriptions are disposed and
/// their pending query timers cancelled before the framework's end-of-test
/// invariant check (dashboard_test convention).
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('lists saved plans and marks the active one', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db, id: 'a', name: 'Alpha', active: true);
    await _seed(tester, db, id: 'b', name: 'Beta', active: false);
    await _mount(tester, db);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // Active plan's day-type label surfaces in the "Today" card.
    expect(find.text('Normal day'), findsOneWidget);
    // Alpha (active) shows the Active badge; Beta offers a Use button.
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('empty state when there are no plans', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db);

    expect(find.textContaining('No saved plans yet'), findsOneWidget);
    expect(find.textContaining('using your maintenance targets'), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('tapping Use switches the active plan', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db, id: 'a', name: 'Alpha', active: true);
    await _seed(tester, db, id: 'b', name: 'Beta', active: false);
    await _mount(tester, db);

    await tester.tap(find.bySemanticsIdentifier('plan-activate-b'));
    await _pumpFrames(tester);

    final rows = await _all(tester, db);
    expect(rows.firstWhere((r) => r.id == 'b').active, isTrue);
    expect(rows.firstWhere((r) => r.id == 'a').active, isFalse,
        reason: 'single-active invariant holds after a switch');
    await _disposeTree(tester);
  });

  testWidgets('delete asks to confirm, then removes the plan', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db, id: 'a', name: 'Alpha', active: false);
    await _mount(tester, db);

    await tester.tap(find.bySemanticsIdentifier('plan-delete-a'));
    await _pumpFrames(tester, 6);
    expect(find.text('Delete "Alpha"?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await _pumpFrames(tester);

    expect(await _all(tester, db), isEmpty);
    expect(find.textContaining('No saved plans yet'), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('cancelling delete keeps the plan', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db, id: 'a', name: 'Alpha', active: false);
    await _mount(tester, db);

    await tester.tap(find.bySemanticsIdentifier('plan-delete-a'));
    await _pumpFrames(tester, 6);
    await tester.tap(find.text('Cancel'));
    await _pumpFrames(tester);

    expect((await _all(tester, db)).length, 1);
    await _disposeTree(tester);
  });
}
