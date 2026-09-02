import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

/// THE BUG THIS FILE EXISTS FOR, found on a device on 2026-09-02.
///
/// Chat history showed "Could not load your chats: Null check operator used on
/// a null value", and Vita never remembered anything. One cause:
///
///   - `withDefault` writes a DEFAULT into a CREATE TABLE that **Drift** runs.
///     In production Drift runs none — `managedExternally: true`, because
///     PowerSync owns the physical schema.
///   - PowerSync creates those tables from powersync_schema.dart, where every
///     column is nullable and nothing has a default.
///   - `createThread` never wrote `summarized_up_to`, so it was NULL, and the
///     generated mapper reads it with `!`.
///
/// So every read of `chat_threads` threw. The history sheet showed the error;
/// memory extraction read the same row inside a `try` whose `catch` swallows
/// failures on purpose, so it died silently and Vita learned nothing.
///
/// The tests could not catch it because in a test Drift DOES create the tables,
/// with the defaults and NOT NULL. The production schema was never the one
/// under test. That is what this file closes.
void main() {
  test('every defaulted column also has a CLIENT default', () {
    // A SQL default is worthless when nobody runs the CREATE TABLE. A client
    // default is applied by Drift at INSERT, so the value exists whatever
    // created the table.
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    final offenders = <String>[];
    for (final table in db.allTables) {
      for (final column in table.$columns) {
        if (column.defaultValue != null && column.clientDefault == null) {
          offenders.add('${table.actualTableName}.${column.name}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these columns are NULL on device the moment an insert omits '
            'them, and the generated mapper reads them with `!`');
  });

  test('the repair list covers every non-nullable defaulted column', () {
    // The repair heals rows written before the client defaults existed. If a
    // new defaulted column is added and not listed here, old devices keep the
    // crash and nothing says so.
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final repair = SakamaDatabase.defaultsToRepair;

    final missing = <String>[];
    for (final table in db.allTables) {
      for (final column in table.$columns) {
        if (column.defaultValue == null) continue;
        if (column.$nullable) continue;
        final name = table.actualTableName;
        if (repair[name]?.containsKey(column.name) != true) {
          missing.add('$name.${column.name}');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'add these to _defaultsToRepair, or a device that already '
            'wrote NULL never recovers');
  });

  test('the repair fixes rows and is safe to run twice', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    // Drift's own table is NOT NULL, so a NULL cannot be written here — which
    // is precisely why this never showed up in a test before. Rebuild the
    // table the way PowerSync does: nullable, no defaults.
    await db.customStatement('DROP TABLE chat_threads');
    await db.customStatement(
      'CREATE TABLE chat_threads (id TEXT NOT NULL PRIMARY KEY, '
      'user_id TEXT, title TEXT, created_at INTEGER, updated_at INTEGER, '
      'summary TEXT, summarized_up_to INTEGER)',
    );
    await db.customStatement(
      "INSERT INTO chat_threads (id, user_id, title, created_at, updated_at) "
      "VALUES ('t1', 'u1', 'Yesterday', 1, 1)",
    );

    // The shape the user saw: the row exists and reading it throws.
    await expectLater(db.select(db.chatThreads).get(), throwsA(isA<TypeError>()));

    await db.repairMissingDefaults();
    final rows = await db.select(db.chatThreads).get();
    expect(rows.single.summarizedUpTo, 0);
    expect(rows.single.title, 'Yesterday', reason: 'repair must not lose data');

    await db.repairMissingDefaults(); // idempotent
    expect((await db.select(db.chatThreads).get()).single.summarizedUpTo, 0);
  });

  test('a new thread now carries the value, so the NULL cannot recur',
      () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.chatThreads).insert(ChatThreadsCompanion.insert(
          id: 't2', title: 'New', createdAt: 1, updatedAt: 1));
    // The insert omits summarizedUpTo, exactly as createThread does. The client
    // default is what puts a 0 in the statement.
    expect((await db.select(db.chatThreads).get()).single.summarizedUpTo, 0);
  });
}
