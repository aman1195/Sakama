import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/plans/data/plan_repository.dart';
import 'package:sakama/features/plans/presentation/plan_import_page.dart';

const _validPlan = '{"schema_version":1,"id":"p","name":"Reset","goal":"detox",'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal"}}}';

/// Bounded pump — pumpAndSettle never idles against a spinner (dashboard_test
/// convention).
Future<void> _pumpFrames(WidgetTester tester, [int frames = 25]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Drift I/O runs on real timers, which the widget-test fake clock does not
// drive; DB access inside testWidgets must go through tester.runAsync.
Future<List<UserPlanRow>> _allPlans(WidgetTester tester, SakamaDatabase db) async =>
    (await tester.runAsync(() => PlanRepository(db).watchAll().first))!;

void main() {
  testWidgets('a valid paste saves an active plan and pops', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    // Host so pop() has somewhere to return to, and we can assert it happened.
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PlanImportPage())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _pumpFrames(tester);
    expect(find.byType(PlanImportPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), _validPlan);
    await tester.tap(find.text('Apply plan'));
    await _pumpFrames(tester);

    // Popped back to the host, page gone.
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(PlanImportPage), findsNothing);

    // The plan was persisted and is active.
    final plans = await _allPlans(tester, db);
    expect(plans.length, 1);
    expect(plans.single.name, 'Reset');
    expect(plans.single.active, isTrue);
  });

  testWidgets('malformed JSON shows an error and saves nothing', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const MaterialApp(home: PlanImportPage()),
    ));
    await _pumpFrames(tester, 4);

    await tester.enterText(find.byType(TextField), '{ not json');
    await tester.tap(find.text('Apply plan'));
    await _pumpFrames(tester, 4);

    expect(find.textContaining('valid JSON'), findsOneWidget);
    expect(find.byType(PlanImportPage), findsOneWidget); // still here
    expect(await _allPlans(tester, db), isEmpty);
  });

  testWidgets('a too-new schema version is rejected, saving nothing (note 2)',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const MaterialApp(home: PlanImportPage()),
    ));
    await _pumpFrames(tester, 4);

    await tester.enterText(
        find.byType(TextField),
        '{"schema_version":99,"id":"p","name":"X",'
        '"day_types":{"normal":{"label":"n"}},'
        '"schedule":{"type":"weekly","map":{"mon":"normal"}}}');
    await tester.tap(find.text('Apply plan'));
    await _pumpFrames(tester, 4);

    expect(find.textContaining('newer version'), findsOneWidget);
    expect(await _allPlans(tester, db), isEmpty);
  });
}
