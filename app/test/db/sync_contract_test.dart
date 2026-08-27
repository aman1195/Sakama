import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/db/powersync_schema.dart';

/// The SQL half of the sync contract, checked statically.
///
/// [schema_alignment_test] cross-checks the two DART representations and
/// deliberately leaves the SQL side to human review. That is exactly where a
/// real bug lived: `workouts` shipped with a Drift table, a PowerSync
/// definition, a migration with RLS and a sync stream — and no
/// `alter publication` line. Review caught it; nothing in CI would have.
///
/// The failure that omission produces is the worst shape available. Uploads
/// work, so the feature looks correct on the device that created the row. The
/// row simply never reaches a second device and does not survive a reinstall.
///
/// None of this needs a live Postgres. The migrations are text on disk and the
/// three facts we need are greppable.
void main() {
  final repoRoot = Directory.current.path.endsWith('app')
      ? Directory.current.parent
      : Directory.current;

  String migrationsBlob() {
    final dir = Directory('${repoRoot.path}/supabase/migrations');
    expect(dir.existsSync(), isTrue,
        reason: 'migrations directory not found at ${dir.path}');
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => f.readAsStringSync())
        .join('\n');
  }

  /// Two migrations drive their statements through a `foreach t in array[...]`
  /// loop with `format('%I', t)`, so the table name never sits next to the
  /// keyword. Rewriting them to satisfy a regex would be the test bending the
  /// code, so a table named inside such an array counts as covered by whatever
  /// that block does.
  Set<String> loopCovered(String sql, String keyword) {
    final covered = <String>{};
    final blocks = RegExp(r'do \$\$(.*?)end \$\$;', dotAll: true);
    final arrays = RegExp(r'array\[([^\]]*)\]');
    final quoted = RegExp(r"'([a-z_]+)'");
    for (final block in blocks.allMatches(sql)) {
      final body = block.group(1)!;
      if (!body.contains(keyword)) continue;
      for (final arr in arrays.allMatches(body)) {
        for (final m in quoted.allMatches(arr.group(1)!)) {
          covered.add(m.group(1)!);
        }
      }
    }
    return covered;
  }

  /// Synced tables only. `Table.localOnly` never reaches Postgres, so it has no
  /// migration, no RLS, no stream and no publication membership.
  Set<String> syncedTables() {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final driftNames = db.allTables.map((t) => t.actualTableName).toSet();
    return powersyncSchema.tables
        .where((t) => !t.localOnly)
        .map((t) => t.name)
        .where(driftNames.contains)
        .toSet();
  }

  test('every synced table is added to the PowerSync publication', () {
    final sql = migrationsBlob();
    final looped = loopCovered(sql, 'publication powersync');
    for (final table in syncedTables()) {
      final direct = RegExp(
              'publication\\s+powersync\\s+(add|for)\\s+table\\s+public\\.$table\\b')
          .hasMatch(sql);
      expect(direct || looped.contains(table), isTrue,
          reason: 'Table "$table" syncs but is never added to the powersync '
              'publication. The publication is created `for table ...`, not '
              'FOR ALL TABLES, so membership is opt-in per table. Without it, '
              'uploads work and downloads have nothing to replicate: the row '
              'never reaches a second device and does not survive a reinstall. '
              'Copy the publication block from any existing migration.');
    }
  });

  test('every synced table has row level security enabled', () {
    final sql = migrationsBlob();
    final looped = loopCovered(sql, 'enable row level security');
    for (final table in syncedTables()) {
      final direct = RegExp(
              'alter\\s+table\\s+public\\.$table\\s+enable\\s+row\\s+level\\s+security')
          .hasMatch(sql);
      expect(direct || looped.contains(table), isTrue,
          reason: 'Table "$table" syncs without RLS enabled. RLS is the '
              'primary data-isolation boundary for a health app '
              '(CLAUDE.md rule 2).');
    }
  });

  test('every synced table has a sync-streams entry', () {
    final f = File('${repoRoot.path}/supabase/powersync/sync-streams.yaml');
    expect(f.existsSync(), isTrue, reason: 'sync-streams.yaml not found');
    final yaml = f.readAsStringSync();
    for (final table in syncedTables()) {
      expect(
          RegExp('from\\s+$table\\b', caseSensitive: false).hasMatch(yaml),
          isTrue,
          reason: 'Table "$table" syncs but no stream selects from it, so '
              'nothing is ever served to the client.');
    }
  });

  test('the guard actually fires when the publication line is missing', () {
    // Without this, a regex that silently matches nothing would let the three
    // tests above pass on an empty file and report a contract that is not
    // checked at all.
    const sqlMissingPublication = '''
      create table public.ghost_logs (id text primary key);
      alter table public.ghost_logs enable row level security;
    ''';
    final direct = RegExp(
            'publication\\s+powersync\\s+(add|for)\\s+table\\s+public\\.ghost_logs\\b')
        .hasMatch(sqlMissingPublication);
    expect(direct, isFalse);
    expect(loopCovered(sqlMissingPublication, 'publication powersync'),
        isEmpty);

    // ...and that it recognises both real forms.
    expect(
        RegExp('publication\\s+powersync\\s+(add|for)\\s+table\\s+public\\.food_logs\\b')
            .hasMatch(
                'alter publication powersync add table public.food_logs;'),
        isTrue);
    expect(
        loopCovered(
            r"""do $$ begin
                 foreach t in array array['water_logs','weight_logs'] loop
                   execute format('alter publication powersync add table public.%I', t);
                 end loop;
               end $$;""",
            'publication powersync'),
        containsAll(['water_logs', 'weight_logs']));
  });
}
