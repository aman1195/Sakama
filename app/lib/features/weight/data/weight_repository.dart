import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

class WeightRepository {
  WeightRepository(this._db);
  final SakamaDatabase _db;

  /// All entries oldest-first — the shape the chart wants.
  Stream<List<WeightLog>> watchAll() => (_db.select(_db.weightLogs)
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .watch();

  Stream<WeightLog?> watchLatest() => (_db.select(_db.weightLogs)
        // Secondary createdAt tiebreak (PR #22 review): two weigh-ins on the
        // same day would otherwise make "latest" nondeterministic.
        ..orderBy([
          (t) => OrderingTerm.desc(t.date),
          (t) => OrderingTerm.desc(t.createdAt),
        ])
        ..limit(1))
      .watchSingleOrNull();

  Future<String> add({
    required String date,
    required double weightKg,
    String? note,
    String? userId,
  }) async {
    final id = uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.weightLogs).insert(WeightLogsCompanion.insert(
          id: id, userId: Value(userId), date: date, weightKg: weightKg,
          note: Value(note), createdAt: now, updatedAt: now));
    return id;
  }
}
