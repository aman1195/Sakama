import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../domain/nutrition_targets.dart';

/// The record of what the targets WERE, and the resolution that reads it back.
///
/// The bug this exists to fix: every screen scored history against TODAY's
/// targets, so moving a goal re-scored days the user had already lived. Logs
/// are immutable; the number they are judged against must be too.
///
/// Storage is CHANGES, not days: a row says "from `date` onward, these were the
/// targets", and stands until a later row supersedes it. Stable goals cost one
/// row a year. Offline-first like every other repository here — Drift is the
/// source of truth and sync catches up later.
class TargetHistoryRepository {
  TargetHistoryRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;

  final SakamaDatabase _db;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  static const sources = ['computed', 'plan', 'seed'];

  /// Every row, oldest first. The whole table, deliberately: resolving a day
  /// needs the row in force AT that day, which may predate any window the
  /// caller has in view, and the table holds one row per change — not per day.
  Stream<List<TargetHistoryRow>> watchAll() =>
      (_db.select(_db.targetHistory)
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .watch();

  Future<List<TargetHistoryRow>> all() =>
      (_db.select(_db.targetHistory)
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  /// The oldest day with food logged, or null when nothing has been logged.
  /// The seed row is dated here so it covers exactly the history a diary can
  /// show, and not a day more.
  Future<String?> earliestLoggedDate() async {
    final min = _db.foodLogs.date.min();
    final row =
        await (_db.selectOnly(_db.foodLogs)..addColumns([min])).getSingleOrNull();
    return row?.read(min);
  }

  /// The targets in force on [date], or null when history does not reach back
  /// that far.
  ///
  /// NULL IS A REAL ANSWER and callers must render it as "no target", not as
  /// zero and not as today's number. Both of those are the lie this table was
  /// built to stop. [rows] may be in any order.
  static TargetHistoryRow? rowFor(List<TargetHistoryRow> rows, String date) {
    TargetHistoryRow? best;
    for (final r in rows) {
      if (r.date.compareTo(date) > 0) continue; // not yet in force
      if (best == null || r.date.compareTo(best.date) > 0) best = r;
    }
    return best;
  }

  static NutritionTargets? resolve(List<TargetHistoryRow> rows, String date) =>
      toTargets(rowFor(rows, date));

  static NutritionTargets? toTargets(TargetHistoryRow? row) => row == null
      ? null
      : NutritionTargets(
          calories: row.calories,
          proteinG: row.proteinG,
          carbG: row.carbG,
          fatG: row.fatG,
          fiberG: row.fiberG,
          waterMl: row.waterMl,
        );

  /// Record [targets] as in force from [date], unless the row already in force
  /// says exactly the same thing.
  ///
  /// The no-op case is the common one — the app opens, nothing changed — so
  /// this is a read and no write on a normal day. Returns true when a row was
  /// actually written.
  ///
  /// Same-day changes UPDATE that day's row rather than adding a second one:
  /// the server's unique (user_id, date) index says a date has one answer, and
  /// a user who edits their goal twice before lunch lived under the last one.
  Future<bool> recordIfChanged({
    required String date,
    required NutritionTargets targets,
    String source = 'computed',
    String? userId,
  }) async {
    if (!sources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'must be one of $sources');
    }
    // A zero calorie target is never a goal; it is an upstream null that would
    // score every day as "over".
    if (targets.calories <= 0) {
      throw ArgumentError.value(
          targets.calories, 'targets.calories', 'must be positive');
    }

    final rows = await all();
    final inForce = rowFor(rows, date);
    if (inForce != null && _sameTargets(inForce, targets)) return false;

    final at = _now;
    final existingToday =
        rows.where((r) => r.date == date).cast<TargetHistoryRow?>().firstOrNull;

    if (existingToday != null) {
      await (_db.update(_db.targetHistory)
            ..where((t) => t.id.equals(existingToday.id)))
          .write(TargetHistoryCompanion(
        calories: Value(targets.calories),
        proteinG: Value(targets.proteinG),
        carbG: Value(targets.carbG),
        fatG: Value(targets.fatG),
        fiberG: Value(targets.fiberG),
        waterMl: Value(targets.waterMl),
        source: Value(source),
        updatedAt: Value(at),
      ));
      return true;
    }

    await _db.into(_db.targetHistory).insert(TargetHistoryCompanion.insert(
          id: uuid.v4(),
          userId: Value(userId),
          date: date,
          calories: targets.calories,
          proteinG: targets.proteinG,
          carbG: targets.carbG,
          fatG: targets.fatG,
          fiberG: targets.fiberG,
          waterMl: targets.waterMl,
          source: Value(source),
          createdAt: at,
          updatedAt: at,
        ));
    return true;
  }

  /// The one row that covers everything logged before this table existed.
  ///
  /// An honest approximation, and labelled as one. It asserts that the
  /// profile's computed targets applied from [date] — true for the many users
  /// who never changed their profile, and the best available answer for the
  /// rest. It records the only number we have rather than inventing one, tagged
  /// `seed` so the source is auditable, and every real change after it is
  /// recorded exactly. Deliberately COMPUTED targets, never a plan overlay: a
  /// plan active today says nothing about last month.
  ///
  /// No-ops once any row exists, so it runs at most once per device.
  Future<bool> seedIfEmpty({
    required String date,
    required NutritionTargets targets,
    String? userId,
  }) async {
    final existing = await all();
    if (existing.isNotEmpty) return false;
    return recordIfChanged(
        date: date, targets: targets, source: 'seed', userId: userId);
  }

  static bool _sameTargets(TargetHistoryRow row, NutritionTargets t) =>
      row.calories == t.calories &&
      row.proteinG == t.proteinG &&
      row.carbG == t.carbG &&
      row.fatG == t.fatG &&
      row.fiberG == t.fiberG &&
      row.waterMl == t.waterMl;
}

extension _FirstOrNull<E> on Iterable<E?> {
  E? get firstOrNull => isEmpty ? null : first;
}
