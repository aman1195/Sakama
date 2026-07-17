import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/db/powersync_schema.dart';

/// Drift-vs-PowerSync schema alignment (PR #10 review, should-fix 4).
///
/// A synced table lives in THREE places: the Drift table (client reads), the
/// PowerSync Schema (physical storage + sync), and supabase/migrations/
/// (server). The #9 migration harness cannot protect PowerSync-managed tables
/// (managedExternally skips Drift DDL), so the two DART representations are
/// cross-checked here — if a column is added to one and not the other, this
/// fails in CI instead of surfacing as a runtime "no such column" mid-sync.
/// The SQL side stays human-reviewed (it is not introspectable in a unit test
/// without a live Postgres; the RLS negative test will cover it — issue #11).
void main() {
  test('every Drift synced table matches its PowerSync definition', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    final psTables = {for (final t in powersyncSchema.tables) t.name: t};

    for (final driftTable in db.allTables) {
      final ps = psTables.remove(driftTable.actualTableName);
      expect(ps, isNotNull,
          reason: 'Drift table "${driftTable.actualTableName}" has no '
              'PowerSync definition in powersync_schema.dart');

      final driftCols = driftTable.$columns.map((c) => c.$name).toSet();
      // PowerSync stores `id` implicitly; it never appears in Column lists.
      final psCols = {...ps!.columns.map((c) => c.name), 'id'};
      expect(driftCols, psCols,
          reason: 'Column mismatch for "${driftTable.actualTableName}" — '
              'a synced-schema change must touch database.dart, '
              'powersync_schema.dart AND supabase/migrations/ together');
    }

    expect(psTables, isEmpty,
        reason: 'PowerSync defines tables Drift does not know: '
            '${psTables.keys.toList()}');
  });
}
