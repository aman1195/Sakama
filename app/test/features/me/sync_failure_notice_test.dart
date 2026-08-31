import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/me/presentation/sync_failure_notice.dart';

/// The notice is the whole point of the receipts: without it the table is a
/// diary of losses nobody reads.
///
/// Mounted with the PROVIDERS overridden rather than the database. Routing a
/// widget test through the real database provider deadlocks — work scheduled
/// under a widget test's fake clock never resumes on real Drift I/O — and the
/// first version of this file was deleted for that reason. Overriding the
/// providers is the way the repo's own account_section_test does it, and it
/// runs in under a second.
void main() {
  SyncFailureRow row(String id, String table, String? payload) =>
      SyncFailureRow(
        id: id,
        targetTable: table,
        op: 'put',
        rowId: 'r-$id',
        code: '23514',
        message: 'violates check constraint',
        payload: payload,
        createdAt: 1,
      );

  Future<void> pump(WidgetTester t, List<SyncFailureRow> rows) async {
    await t.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        syncFailureCountProvider.overrideWith((ref) => Stream.value(rows.length)),
        syncFailuresProvider.overrideWith((ref) => Stream.value(rows)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SyncFailureNotice())),
      ),
    ));
    await t.pump();
  }

  testWidgets('stays out of the way when nothing was lost', (t) async {
    await pump(t, const []);
    expect(find.bySemanticsIdentifier('sync-failures-notice'), findsNothing,
        reason: 'a permanent "sync is fine" row would just be noise');
  });

  testWidgets('says how many entries did not save', (t) async {
    await pump(t, [
      row('1', 'food_logs', '{"name":"Butter Chicken"}'),
      row('2', 'water_logs', null),
    ]);
    expect(find.bySemanticsIdentifier('sync-failures-notice'), findsOneWidget);
    expect(find.text("2 entries didn't save"), findsOneWidget);
  });

  testWidgets('singular for one — "1 entries" is a tell nobody read the screen',
      (t) async {
    await pump(t, [row('1', 'food_logs', null)]);
    expect(find.text("1 entry didn't save"), findsOneWidget);
  });

  testWidgets('the sheet names the entry, not just the table and the code',
      (t) async {
    await pump(t, [row('1', 'food_logs', '{"name":"Butter Chicken"}')]);
    await t.tap(find.bySemanticsIdentifier('sync-failures-notice'));
    await t.pumpAndSettle();

    expect(find.bySemanticsIdentifier('sync-failures-sheet'), findsOneWidget);
    // The user recognises the food, not `food_logs` or `23514`.
    expect(find.textContaining('Butter Chicken'), findsOneWidget);
    // The code is still there for whoever has to diagnose it.
    expect(find.textContaining('23514'), findsOneWidget);
    expect(find.bySemanticsIdentifier('sync-failure-0'), findsOneWidget);
  });

  testWidgets('clearing asks first, because it deletes the last copy',
      (t) async {
    await pump(t, [row('1', 'food_logs', '{"name":"Butter Chicken"}')]);
    await t.tap(find.bySemanticsIdentifier('sync-failures-notice'));
    await t.pumpAndSettle();

    await t.tap(find.bySemanticsIdentifier('sync-failures-clear'));
    await t.pumpAndSettle();

    // The row was reconciled off the device; this payload is all that is left.
    expect(find.text('Clear the list?'), findsOneWidget);
    expect(find.textContaining('only remaining copy'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
  });
}
