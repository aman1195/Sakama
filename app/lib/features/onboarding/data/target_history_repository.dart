import 'package:drift/drift.dart';

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
  ///
  /// Ordered by `date` then `updated_at` so the sequence is TOTAL. Date alone
  /// leaves same-date rows in whatever order SQLite returns, and a second
  /// device can legitimately deliver a row for a date this one already has —
  /// which would make two screens reading the same table disagree.
  Stream<List<TargetHistoryRow>> watchAll() => _ordered().watch();

  Future<List<TargetHistoryRow>> all() => _ordered().get();

  SimpleSelectStatement<$TargetHistoryTable, TargetHistoryRow> _ordered() =>
      _db.select(_db.targetHistory)
        ..orderBy([
          (t) => OrderingTerm.asc(t.date),
          (t) => OrderingTerm.asc(t.updatedAt),
        ]);

  /// The oldest day with food logged, or null when nothing has been logged.
  /// History has to reach back at least this far or the diary is scoring days
  /// it has no ruler for.
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
  ///
  /// Ties on `date` are broken by `updatedAt`, so two rows for one day — which
  /// the server's unique index forbids but a mid-sync device can briefly hold —
  /// still resolve to one deterministic answer everywhere.
  static TargetHistoryRow? rowFor(List<TargetHistoryRow> rows, String date) {
    TargetHistoryRow? best;
    for (final r in rows) {
      if (r.date.compareTo(date) > 0) continue; // not yet in force
      if (best == null) {
        best = r;
        continue;
      }
      final byDate = r.date.compareTo(best.date);
      if (byDate > 0 || (byDate == 0 && r.updatedAt > best.updatedAt)) best = r;
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
  /// this reads and does not write on a normal day. Returns true when a row was
  /// actually written.
  ///
  /// TRANSACTIONAL read-modify-write, for the reason ProfileRepository.save is:
  /// the recorder fires from three listeners, and a date rollover that also
  /// changes the plan's day type fires two of them in the same turn. Without
  /// the transaction both passes see no row for today and both INSERT, leaving
  /// one date holding two answers — after which the diary and Vita can resolve
  /// the same day differently, and the server's unique (user_id, date) index
  /// rejects the loser as a poison op that is dropped and never retried.
  Future<bool> recordIfChanged({
    required String date,
    required NutritionTargets targets,
    String source = 'computed',
    String? userId,
  }) {
    if (!sources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'must be one of $sources');
    }
    // A zero calorie target is never a goal; it is an upstream null that would
    // score every day as "over".
    if (targets.calories <= 0) {
      throw ArgumentError.value(
          targets.calories, 'targets.calories', 'must be positive');
    }

    return _db.transaction(() async {
      final rows = await all();
      final inForce = rowFor(rows, date);
      if (inForce != null && _sameTargets(inForce, targets)) return false;

      // Same-day changes UPDATE that day's row rather than adding a second one:
      // the server says a date has one answer, and a user who edits their goal
      // twice before lunch lived under the last one.
      final existingToday = rows.where((r) => r.date == date).toList();
      if (existingToday.isNotEmpty) {
        await (_db.update(_db.targetHistory)
              ..where((t) => t.id.equals(existingToday.last.id)))
            .write(_companionFor(targets, source));
        return true;
      }

      await _insert(date: date, targets: targets, source: source, userId: userId);
      return true;
    });
  }

  /// Make sure recorded history reaches back to [earliestLogged], writing one
  /// `seed` row if it does not.
  ///
  /// COVERAGE IS RE-CHECKED, not done once. The obvious version — seed only
  /// when the table is empty — locks itself out on a fresh install of an
  /// existing account: the recorder's first pass runs before PowerSync has
  /// delivered the food logs, writes today's row, and then no seed can ever
  /// land. Sixty days of real history would arrive with no ruler behind them,
  /// and the same account on the older phone would score them differently.
  ///
  /// The seed is an honest approximation and is labelled as one. It asserts
  /// the profile's computed targets applied from [earliestLogged] — true for
  /// everyone who never changed their profile, and the best available answer
  /// for the rest. It records the only number we have rather than inventing
  /// one. Deliberately COMPUTED targets, never a plan overlay: a plan active
  /// today says nothing about last month.
  ///
  /// Only ever inserts BEFORE the oldest recorded row, so it can never
  /// overwrite something really recorded.
  Future<bool> backfillIfUncovered({
    required String earliestLogged,
    required NutritionTargets targets,
    String? userId,
  }) {
    if (targets.calories <= 0) {
      throw ArgumentError.value(
          targets.calories, 'targets.calories', 'must be positive');
    }
    return _db.transaction(() async {
      final rows = await all();
      if (rows.isNotEmpty &&
          rows.first.date.compareTo(earliestLogged) <= 0) {
        return false; // history already reaches back far enough
      }
      await _insert(
          date: earliestLogged, targets: targets, source: 'seed', userId: userId);
      return true;
    });
  }

  /// The id for a date, DERIVED rather than random.
  ///
  /// Two devices that write the same date must produce the same id. With a
  /// random uuid they do not: both rows reach the server, the second violates
  /// the unique (user_id, date) index with a 23505, and that code IS in the
  /// connector's fatal set — so the op is discarded and, as its comment says,
  /// "the row stays locally". That device then holds two rows for one date
  /// (its own ghost plus the winner's) and resolves the day to whichever is
  /// newer, while the other device resolves it to the winner. Two devices, two
  /// verdicts on the same past week, permanently, curable only by reinstall —
  /// precisely the divergence this table exists to prevent.
  ///
  /// Derived, the same write from both devices is the same row, and the
  /// connector's upsert-on-id makes the second one a harmless last-write-wins.
  ///
  /// The user id is part of the key because `id` is the PRIMARY KEY server-side
  /// and is therefore global: date alone would collide across accounts. The
  /// pre-auth `local:` form never reaches the server anyway (a null user_id
  /// cannot satisfy the not-null column), so it cannot collide there.
  static String idFor({String? userId, required String date}) =>
      '${userId ?? 'local'}:$date';

  Future<void> _insert({
    required String date,
    required NutritionTargets targets,
    required String source,
    String? userId,
  }) async {
    // Read the clock ONCE: created_at and updated_at describe the same event.
    final at = _now;
    await _db.into(_db.targetHistory).insert(TargetHistoryCompanion.insert(
          id: idFor(userId: userId, date: date),
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
  }

  TargetHistoryCompanion _companionFor(NutritionTargets t, String source) =>
      TargetHistoryCompanion(
        calories: Value(t.calories),
        proteinG: Value(t.proteinG),
        carbG: Value(t.carbG),
        fatG: Value(t.fatG),
        fiberG: Value(t.fiberG),
        waterMl: Value(t.waterMl),
        source: Value(source),
        updatedAt: Value(_now),
      );

  static bool _sameTargets(TargetHistoryRow row, NutritionTargets t) =>
      row.calories == t.calories &&
      row.proteinG == t.proteinG &&
      row.carbG == t.carbG &&
      row.fatG == t.fatG &&
      row.fiberG == t.fiberG &&
      row.waterMl == t.waterMl;
}
