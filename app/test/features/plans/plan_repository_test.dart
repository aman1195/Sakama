import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/plans/data/plan_repository.dart';
import 'package:sakama/features/plans/domain/plan.dart';

const _planJson = '''
{"schema_version":1,"id":"p","name":"Reset","goal":"detox",
 "day_types":{"normal":{"label":"n"}},
 "schedule":{"type":"weekly","map":{"mon":"normal"}}}
''';

void main() {
  late SakamaDatabase db;
  late PlanRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = PlanRepository(db);
  });
  tearDown(() => db.close());

  test('save creates an active plan; watchActivePlan decodes it', () async {
    await repo.savePlan(name: 'Reset', config: _planJson);
    final plan = await repo.watchActivePlan().first;
    expect(plan, isNotNull);
    expect(plan!.name, 'Reset');
    expect(plan.goal, 'detox');
  });

  test('single-active invariant: saving a second active plan deactivates the first',
      () async {
    final first = await repo.savePlan(name: 'A', config: _planJson);
    await repo.savePlan(name: 'B', config: _planJson);

    final rows = await repo.watchAll().first;
    expect(rows.length, 2);
    final active = rows.where((r) => r.active).toList();
    expect(active.length, 1, reason: 'exactly one plan may be active');
    expect(active.single.name, 'B');
    // The first is retained as history, just inactive.
    expect(rows.firstWhere((r) => r.id == first).active, isFalse);
  });

  test('setActive switches the active plan; others deactivate', () async {
    final a = await repo.savePlan(name: 'A', config: _planJson);
    await repo.savePlan(name: 'B', config: _planJson); // B now active
    await repo.setActive(a);

    final rows = await repo.watchAll().first;
    expect(rows.where((r) => r.active).map((r) => r.id), [a]);
  });

  test('save with activate:false leaves no active plan', () async {
    await repo.savePlan(name: 'draft', config: _planJson, activate: false);
    expect(await repo.watchActivePlan().first, isNull);
    expect(await repo.getActiveRow(), isNull);
  });

  test('clearActive reverts to no active plan (computed default)', () async {
    await repo.savePlan(name: 'A', config: _planJson);
    await repo.clearActive();
    expect(await repo.watchActivePlan().first, isNull);
  });

  test('delete removes a plan', () async {
    final a = await repo.savePlan(name: 'A', config: _planJson, activate: false);
    await repo.deletePlan(a);
    expect(await repo.watchAll().first, isEmpty);
  });

  test('a stored config that is unparseable yields null, not a crash', () async {
    // Persist a row with a garbage config directly, then read it back.
    await repo.savePlan(name: 'bad', config: 'not json at all {{{');
    expect(await repo.watchActivePlan().first, isNull,
        reason: 'tryParse guards malformed JSON (review #68 note 1)');
  });

  group('split-brain active state (two devices activated offline, review #69)', () {
    // Insert two active rows DIRECTLY, bypassing savePlan's single-active
    // enforcement — this is exactly what sync merges from two offline devices.
    // Config name matches the row name so newest-wins is provable at the plan
    // level (the decoded Plan.name comes from the JSON, not the row column).
    Future<void> insertActive(String id, String name, int updatedAt) =>
        db.into(db.userPlans).insert(UserPlansCompanion.insert(
              id: id,
              name: name,
              config: '{"schema_version":1,"id":"$id","name":"$name",'
                  '"day_types":{"normal":{"label":"n"}},'
                  '"schedule":{"type":"weekly","map":{"mon":"normal"}}}',
              active: const Value(true),
              createdAt: 1,
              updatedAt: updatedAt,
            ));

    test('readers never throw on >1 active; newest-activated wins', () async {
      await insertActive('older', 'Older', 100);
      await insertActive('newer', 'Newer', 200);

      // Would throw with watchSingleOrNull on two rows before the fix.
      final plan = await repo.watchActivePlan().first;
      final row = await repo.getActiveRow();
      expect(row?.id, 'newer', reason: 'most-recently-activated wins (LWW)');
      expect(plan?.name, 'Newer');
    });

    test('reconcileActive collapses to the newest single active row', () async {
      await insertActive('older', 'Older', 100);
      await insertActive('newer', 'Newer', 200);

      await repo.reconcileActive();

      final rows = await repo.watchAll().first;
      final active = rows.where((r) => r.active).toList();
      expect(active.map((r) => r.id), ['newer']);
      // The loser is retained as history, just deactivated.
      expect(rows.firstWhere((r) => r.id == 'older').active, isFalse);
    });

    test('reconcileActive is a no-op with one active plan', () async {
      await repo.savePlan(name: 'solo', config: _planJson);
      await repo.reconcileActive();
      expect((await repo.watchAll().first).where((r) => r.active).length, 1);
    });
  });

  group('Plan.tryParse (string guard)', () {
    test('malformed JSON returns null', () {
      expect(Plan.tryParse('{ not valid'), isNull);
    });
    test('a non-object top level returns null', () {
      expect(Plan.tryParse('[1,2,3]'), isNull);
      expect(Plan.tryParse('"a string"'), isNull);
    });
    test('a valid object parses', () {
      expect(Plan.tryParse(_planJson)?.name, 'Reset');
    });
  });
}
