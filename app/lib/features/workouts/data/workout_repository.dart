import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../domain/workout_set.dart';

/// Exercise logging (PRD 7.1). Synced, per-user, offline-first like every
/// other log: the UI reads Drift, never the network.
class WorkoutRepository {
  WorkoutRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;
  final SakamaDatabase _db;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  /// The closed vocabulary, in the order a picker should offer it.
  static const kinds = ['strength', 'cardio', 'mobility', 'sport', 'other'];
  static bool isValidKind(String k) => kinds.contains(k);

  Stream<List<WorkoutRow>> watchDay(String date) =>
      (_db.select(_db.workouts)
            ..where((t) => t.date.equals(date))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Stream<List<WorkoutRow>> watchSince(String fromYmd) =>
      (_db.select(_db.workouts)
            ..where((t) => t.date.isBiggerOrEqualValue(fromYmd))
            ..orderBy([
              (t) => OrderingTerm.desc(t.date),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  Future<String> add({
    required String date,
    required String name,
    String kind = 'strength',
    int? durationMin,
    double? energyKcal,
    List<WorkoutSet> sets = const [],
    String? notes,
    String loggedVia = 'manual',
    String? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (!isValidKind(kind)) {
      throw ArgumentError.value(kind, 'kind', 'must be one of $kinds');
    }
    final id = uuid.v4();
    // Read the clock ONCE: created_at and updated_at describe the same event,
    // and two reads can land a millisecond apart.
    final at = _now;
    await _db.into(_db.workouts).insert(WorkoutsCompanion.insert(
          id: id,
          userId: Value(userId),
          date: date,
          name: trimmed,
          kind: Value(kind),
          durationMin: Value(durationMin),
          // Never coerced to 0: an unknown burn is unknown, and a stored 0
          // would feed the calorie target as though it were measured.
          energyKcal: Value(energyKcal),
          sets: Value(WorkoutSet.encode(sets)),
          notes: Value(notes),
          loggedVia: Value(loggedVia),
          createdAt: at,
          updatedAt: at,
        ));
    return id;
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.workouts)..where((t) => t.id.equals(id))).go();

  Future<void> update({
    required String id,
    String? name,
    String? kind,
    int? durationMin,
    double? energyKcal,
    List<WorkoutSet>? sets,
    String? notes,
  }) =>
      (_db.update(_db.workouts)..where((t) => t.id.equals(id)))
          .write(WorkoutsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        kind: kind == null ? const Value.absent() : Value(kind),
        durationMin: Value(durationMin),
        energyKcal: Value(energyKcal),
        sets: sets == null ? const Value.absent() : Value(WorkoutSet.encode(sets)),
        notes: Value(notes),
        // A hand-edited row must not still claim Vita logged it, exactly as a
        // corrected food row is re-marked manual.
        loggedVia: const Value('manual'),
        updatedAt: Value(_now),
      ));

  /// Total burn for a day. Null-safe: workouts with an unknown burn contribute
  /// nothing rather than zero, and the count of those is reported so the UI can
  /// say "plus 2 without an estimate" instead of quietly under-reporting.
  static ({double kcal, int unknown}) dayBurn(List<WorkoutRow> rows) {
    var kcal = 0.0;
    var unknown = 0;
    for (final r in rows) {
      if (r.energyKcal == null) {
        unknown++;
      } else {
        kcal += r.energyKcal!;
      }
    }
    return (kcal: kcal, unknown: unknown);
  }
}
