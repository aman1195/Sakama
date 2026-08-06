import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// The one place food_logs are written and read, so the dashboard and capture
/// share persistence (offline-first: local Drift; sync carries it up).
class FoodLogRepository {
  FoodLogRepository(this._db);
  final SakamaDatabase _db;

  Stream<List<FoodLog>> watchDay(String date) => _db.watchDay(date);

  /// The foods you actually eat, newest first, one row per distinct name.
  ///
  /// Repeat eating is the norm — most people cycle the same few dishes — so
  /// re-entering name and macros every time is the main friction in a food
  /// diary. This is derived from `food_logs`, so it needs NO new table and no
  /// migration (the user_foods library in #35 is a separate, later slice).
  ///
  /// Dedupe is by case-insensitive name and happens in Dart rather than SQL:
  /// the candidate window is small and an explicit fold is obviously correct,
  /// where a GROUP BY relying on SQLite's bare-column behaviour is not.
  Future<List<FoodLog>> recentDistinct({int limit = 12}) async {
    final rows = await (_db.select(_db.foodLogs)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id), // deterministic within a millisecond
          ])
          ..limit(limit * 20)) // enough history to fill `limit` distinct names
        .get();

    final seen = <String>{};
    final out = <FoodLog>[];
    for (final r in rows) {
      if (seen.add(r.name.trim().toLowerCase())) {
        out.add(r);
        if (out.length == limit) break;
      }
    }
    return out;
  }

  /// Add one logged food. Returns the new row id. userId is the session uid
  /// (null when signed out — the server default fills it on sync).
  Future<String> add({
    required String date,
    required String meal,
    required String name,
    required double energyKcal,
    double proteinG = 0,
    double carbG = 0,
    double fatG = 0,
    double? grams,
    String loggedVia = 'quick_add',
    String? userId,
  }) async {
    final id = uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.foodLogs).insert(FoodLogsCompanion.insert(
          id: id,
          userId: Value(userId),
          date: date,
          meal: meal,
          name: name,
          grams: Value(grams),
          energyKcal: energyKcal,
          proteinG: Value(proteinG),
          carbG: Value(carbG),
          fatG: Value(fatG),
          loggedVia: Value(loggedVia),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  /// Correct an entry in place. An edited row records `manual` provenance: it
  /// is no longer the AI estimate / corpus match / remembered portion it
  /// started as, and the diary must not claim otherwise (rule 7).
  Future<void> update({
    required String id,
    required String meal,
    required String name,
    required double energyKcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    double? grams,
  }) async {
    await (_db.update(_db.foodLogs)..where((t) => t.id.equals(id))).write(
      FoodLogsCompanion(
        meal: Value(meal),
        name: Value(name),
        energyKcal: Value(energyKcal),
        proteinG: Value(proteinG),
        carbG: Value(carbG),
        fatG: Value(fatG),
        grams: Value(grams),
        loggedVia: const Value('manual'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch), // LWW
      ),
    );
  }

  Future<void> delete(String id) async =>
      (_db.delete(_db.foodLogs)..where((t) => t.id.equals(id))).go();
}
