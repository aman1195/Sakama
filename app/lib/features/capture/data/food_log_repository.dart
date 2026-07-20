import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// The one place food_logs are written and read, so the dashboard and capture
/// share persistence (offline-first: local Drift; sync carries it up).
class FoodLogRepository {
  FoodLogRepository(this._db);
  final SakamaDatabase _db;

  Stream<List<FoodLog>> watchDay(String date) => _db.watchDay(date);

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

  Future<void> delete(String id) async =>
      (_db.delete(_db.foodLogs)..where((t) => t.id.equals(id))).go();
}
