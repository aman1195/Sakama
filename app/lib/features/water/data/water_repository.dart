import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

class WaterRepository {
  WaterRepository(this._db);
  final SakamaDatabase _db;

  /// Live total ml for a day (0 when none).
  Stream<int> watchDayTotalMl(String date) {
    final q = _db.selectOnly(_db.waterLogs)
      ..addColumns([_db.waterLogs.amountMl.sum()])
      ..where(_db.waterLogs.date.equals(date));
    return q
        .map((r) => r.read(_db.waterLogs.amountMl.sum()) ?? 0)
        .watchSingle();
  }

  Future<String> add(
      {required String date, required int amountMl, String? userId}) async {
    final id = uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.waterLogs).insert(WaterLogsCompanion.insert(
          id: id, userId: Value(userId), date: date, amountMl: amountMl,
          createdAt: now, updatedAt: now));
    return id;
  }

  /// Undo the most recent entry for the day (for the water chip's "−").
  Future<void> removeLast(String date) async {
    final last = await (_db.select(_db.waterLogs)
          ..where((t) => t.date.equals(date))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (last != null) {
      await (_db.delete(_db.waterLogs)..where((t) => t.id.equals(last.id))).go();
    }
  }
}
