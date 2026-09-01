import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/sync/sync_failure_repository.dart';

/// A receipt exists so that a discarded write stops being invisible. These
/// pin the part the user sees: that it is counted, that it is named in words
/// they recognise, and that it can be cleared.
void main() {
  late SakamaDatabase db;
  late SyncFailureRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = SyncFailureRepository(db);
  });
  tearDown(() => db.close());

  Future<void> record({
    String table = 'food_logs',
    String? payload,
    String? code = '23514',
    String? message = 'violates check constraint',
    int at = 1,
  }) =>
      db.into(db.syncFailures).insert(SyncFailuresCompanion.insert(
            id: 'f$at',
            targetTable: table,
            op: 'put',
            rowId: 'row-$at',
            code: Value(code),
            message: Value(message),
            payload: Value(payload),
            createdAt: at,
          ));

  test('counts what was thrown away', () async {
    expect(await repo.all(), isEmpty);
    await record(at: 1);
    await record(at: 2);
    expect((await repo.all()).length, 2);
  });

  test('newest first — the most recent loss is the one being asked about',
      () async {
    await record(at: 1);
    await record(at: 5);
    expect((await repo.all()).first.rowId, 'row-5');
  });

  test('names the entry from the payload, not the table', () async {
    // "food_logs / 23514" tells the user nothing about what they lost.
    await record(payload: jsonEncode({'name': 'Butter Chicken', 'meal': 'lunch'}));
    final row = (await repo.all()).single;
    expect(SyncFailureRepository.describe(row), 'A food entry · Butter Chicken');
  });

  test('falls back to the kind of thing when the payload has no name',
      () async {
    await record(table: 'water_logs', payload: jsonEncode({'amount_ml': 250}));
    expect(SyncFailureRepository.describe((await repo.all()).single),
        'A water entry');
  });

  test('a malformed payload does not break the list', () async {
    // A receipt that crashes the screen showing receipts would be its own bug.
    await record(payload: 'not json at all');
    expect(SyncFailureRepository.describe((await repo.all()).single),
        'A food entry');
  });

  test('an unknown table still describes something', () async {
    await record(table: 'something_new');
    expect(SyncFailureRepository.describe((await repo.all()).single),
        'An entry');
  });

  test('clear empties the list', () async {
    await record(at: 1);
    await record(at: 2);
    await repo.clear();
    expect(await repo.all(), isEmpty);
  });

  test('dismiss removes one without touching the rest', () async {
    await record(at: 1);
    await record(at: 2);
    await repo.dismiss('f1');
    expect((await repo.all()).single.id, 'f2');
  });

  test('the payload is kept, which is what makes recovery possible later',
      () async {
    final sent = {'name': 'dal', 'energy_kcal': 180, 'logged_via': 'recent'};
    await record(payload: jsonEncode(sent));
    final row = (await repo.all()).single;
    expect(jsonDecode(row.payload!), sent,
        reason: 'without the payload, "3 entries failed" is only an apology');
  });

  group('the recording statement', () {
    /// THE STATEMENT THE CONNECTOR RUNS, exercised against the real schema.
    ///
    /// It is the one write in the system whose failure is swallowed by a catch
    /// and logged where nobody reads. A wrong column name or a miscounted
    /// placeholder would make the whole feature a silent no-op — the exact
    /// shape of bug it exists to expose. The first version could not be tested
    /// at all because it called PowerSync's SQL `uuid()`.
    test('inserts a row that matches the columns it names', () async {
      final stmt = SyncFailureStatement.build(
        clientId: 42,
        table: 'food_logs',
        op: 'put',
        rowId: 'row-1',
        code: '23514',
        message: 'violates check constraint',
        payload: {'name': 'Butter Chicken', 'logged_via': 'recent'},
        at: 1700,
      );
      await db.customStatement(stmt.sql, stmt.params);

      final row = (await repo.all()).single;
      expect(row.id, '42');
      expect(row.targetTable, 'food_logs');
      expect(row.op, 'put');
      expect(row.rowId, 'row-1');
      expect(row.code, '23514');
      expect(row.createdAt, 1700);
      expect(jsonDecode(row.payload!)['name'], 'Butter Chicken');
    });

    test('a retry of the same op updates its receipt instead of adding one',
        () async {
      // A transaction holding a poison op AND a transient failure never
      // completes, so it retries every 30s. With a fresh uuid each time that
      // is "121 entries didn't save" for one lost entry, and the count the
      // user reads is the thing that goes wrong.
      for (var i = 0; i < 5; i++) {
        final stmt = SyncFailureStatement.build(
          clientId: 7,
          table: 'food_logs',
          op: 'put',
          rowId: 'row-1',
          code: '23514',
          at: 1700 + i,
        );
        await db.customStatement(stmt.sql, stmt.params);
      }
      final rows = await repo.all();
      expect(rows.length, 1, reason: 'one lost entry is one receipt');
      expect(rows.single.createdAt, 1704, reason: 'refreshed, not duplicated');
    });

    test('two different ops keep two receipts', () async {
      for (final id in [1, 2]) {
        final stmt = SyncFailureStatement.build(
          clientId: id, table: 'food_logs', op: 'put', rowId: 'r$id', at: id);
        await db.customStatement(stmt.sql, stmt.params);
      }
      expect((await repo.all()).length, 2);
    });

    test('a null payload is allowed — a delete carries no row', () async {
      final stmt = SyncFailureStatement.build(
        clientId: 9, table: 'food_logs', op: 'delete', rowId: 'r', at: 1);
      await db.customStatement(stmt.sql, stmt.params);
      expect((await repo.all()).single.payload, isNull);
    });
  });
}
