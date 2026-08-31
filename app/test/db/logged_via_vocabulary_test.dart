import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';

/// The client and the server must agree on what a `logged_via` can be.
///
/// They drifted once, and the drift was invisible and destroyed data: Drift
/// enforces no CHECK, so an unknown value inserted cleanly and the user saw
/// "Logged X"; the upload then failed with 23514, which the connector treats as
/// a poison op and discards; and once the op was gone the next sync checkpoint
/// reconciled the row out of existence. Three weeks of meals logged from
/// recents, saved foods, saved meals, AI estimates and Vita were lost before
/// anyone noticed, because every layer reported success.
///
/// This test is the thing that would have caught it in CI.
void main() {
  /// The vocabulary the LIVE constraint allows, read from the migrations the
  /// same way the database sees them: last definition wins.
  Set<String> serverVocabulary() {
    final dir = Directory('../supabase/migrations');
    expect(dir.existsSync(), isTrue, reason: 'migrations not found');
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    Set<String>? latest;
    for (final f in files) {
      final sql = f.readAsStringSync();
      // The last `logged_via in (...)` / `logged_via = ANY (ARRAY[...])` block
      // in migration order is the one in force.
      final matches = RegExp(
        r'logged_via\s*(?:in|=\s*any)\s*\(\s*(?:array\s*\[)?(.*?)\]?\s*\)',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(sql);
      for (final m in matches) {
        final body = m.group(1)!;
        final values = RegExp(r"'([a-z_]+)'")
            .allMatches(body)
            .map((v) => v.group(1)!)
            .toSet();
        if (values.isNotEmpty) latest = values;
      }
    }
    expect(latest, isNotNull,
        reason: 'no logged_via constraint found in any migration');
    return latest!;
  }

  test('every logged_via the client can write is accepted by the server', () {
    final server = serverVocabulary();
    final client = FoodLogRepository.loggedViaValues.toSet();
    final rejected = client.difference(server);

    expect(rejected, isEmpty,
        reason: 'These values insert fine locally, are rejected on upload with '
            '23514, are then DISCARDED as a poison op, and the row is '
            'reconciled away — the user watches a logged meal disappear with '
            'no error. Add them to a migration widening '
            'food_logs_logged_via_check.');
  });

  test('the guard fires when a client value is missing server-side', () {
    // The test above passes when both sides agree, which is also what it would
    // do if the parsing silently returned everything. Prove it can fail.
    const server = {'search', 'photo'};
    const client = {'search', 'photo', 'meal'};
    expect(client.difference(server), {'meal'});
  });

  test('the vocabulary has no duplicates and no stray casing', () {
    final v = FoodLogRepository.loggedViaValues;
    expect(v.toSet().length, v.length, reason: 'duplicate provenance value');
    for (final s in v) {
      expect(s, matches(RegExp(r'^[a-z_]+$')),
          reason: 'provenance values are lower_snake, matching the SQL');
    }
  });
}
