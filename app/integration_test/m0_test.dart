import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:powersync/powersync.dart' show uuid;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/env/env.dart';
import 'package:sakama/core/sync/sync_service.dart';

/// The M0 exit test + the two-account isolation test, run as three phases on
/// real devices (no UI driving needed — this exercises the same code paths):
///
///   PHASE=seed       (device 1, tester-a): write rows LOCALLY while signed out
///                    and disconnected (the offline write path), then sign in,
///                    connect, and prove the upload queue drains.
///   PHASE=sync-down  (device 2, tester-a): fresh install syncs the row DOWN.
///                    -> M0 exit test complete.
///   PHASE=isolation  (device 2, tester-b): after clear + sign-in as B, B must
///                    see ZERO rows. -> the hard gate from the #13 review.
///
/// Run:
///   flutter test integration_test/m0_test.dart -d DEVICE \
///     --dart-define=PHASE=seed --dart-define=EMAIL=... --dart-define=PASSWORD=...
const phase = String.fromEnvironment('PHASE');
const email = String.fromEnvironment('EMAIL');
const password = String.fromEnvironment('PASSWORD');
const marker = String.fromEnvironment('MARKER'); // REQUIRED, unique per run

Future<void> _retry(Future<bool> Function() check, String what,
    {int seconds = 60}) async {
  for (var i = 0; i < seconds * 2; i++) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('timed out waiting for: $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('m0 phase: $phase', () async {
    expect(Env.isConfigured, isTrue, reason: 'real .env required');
    // A reused marker lets a re-run pass on a STALE server row from an earlier
    // execution while this run's upload silently failed (review f5fdb22 #1).
    expect(marker, isNotEmpty,
        reason: 'pass a unique --dart-define=MARKER=<run-id> per run');
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    final sync = SyncService();
    final db = await sync.open();
    final auth = Supabase.instance.client.auth;

    switch (phase) {
      case 'seed':
        // Clean slate for repeatable runs.
        await sync.disconnectAndClear();
        expect(auth.currentSession, isNull);

        // OFFLINE WRITE PATH: signed out, replication not connected. Two rows:
        // one pre-auth (userId null -> tests the #10 null-omission bet) and,
        // after sign-in, one with the uid set (the row that MUST sync).
        final now = DateTime.now().millisecondsSinceEpoch;
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
              id: uuid.v4(), date: today, meal: 'lunch',
              name: '$marker-preauth', energyKcal: 111,
              createdAt: now, updatedAt: now,
            ));

        await auth.signInWithPassword(email: email, password: password);
        final uid = auth.currentSession!.user.id;
        final authedId = uuid.v4();
        await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
              id: authedId, date: today, meal: 'lunch',
              name: '$marker-authed', energyKcal: 222,
              userId: Value(uid), createdAt: now, updatedAt: now,
            ));

        // Now attach replication and prove the queue drains.
        await sync.connect();
        await _retry(() async => await sync.uploadQueueCount() == 0,
            'upload queue to drain', seconds: 90);

        // Server-side proof via REST as tester-a (RLS-scoped).
        final rows = await Supabase.instance.client
            .from('food_logs').select('id,name,user_id');
        // Assert on the exact id inserted THIS run — name-matching would pass
        // vacuously on a stale row from a previous execution.
        expect([for (final r in rows) r['id'] as String], contains(authedId),
            reason: 'THIS run\'s authed row must reach Postgres');
        final names = [for (final r in rows) r['name'] as String];
        // The pre-auth row: PASS either way, but RECORD the answer to the bet.
        // ignore: avoid_print
        print('NULL-USERID-BET: preauth row synced = '
            '${names.contains('$marker-preauth')} (server rows: $names)');

      case 'sync-down':
        await sync.disconnectAndClear();
        await auth.signInWithPassword(email: email, password: password);
        await sync.connect();
        await sync.waitForFirstSync();
        await _retry(() async {
          final rows = await db.select(db.foodLogs).get();
          return rows.any((r) => r.name == '$marker-authed');
        }, 'marker row to sync down to a fresh device');
        // ignore: avoid_print
        print('SYNC-DOWN: marker row present on second device');

      case 'isolation':
        await sync.disconnectAndClear();
        await auth.signInWithPassword(email: email, password: password);
        await sync.connect();
        await sync.waitForFirstSync();
        // Give any (wrong) data a moment to arrive before asserting zero.
        await Future<void>.delayed(const Duration(seconds: 5));
        final rows = await db.select(db.foodLogs).get();
        expect(rows, isEmpty,
            reason: 'ISOLATION FAILURE: user B can see rows: '
                '${[for (final r in rows) "${r.name}/${r.userId}"]}');
        // ignore: avoid_print
        print('ISOLATION: user B sees zero rows — gate passed');

      default:
        fail('unknown PHASE "$phase"');
    }
    await auth.signOut();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
