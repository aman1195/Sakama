import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// The one place food_logs are written and read, so the dashboard and capture
/// share persistence (offline-first: local Drift; sync carries it up).
class FoodLogRepository {
  FoodLogRepository(this._db);
  final SakamaDatabase _db;

  /// Every provenance a food_logs row can carry — THE source of truth.
  ///
  /// It is a list rather than scattered literals because the server enforces
  /// the same vocabulary as a CHECK constraint, and the two silently drifted
  /// apart: the client learned `recent`, `saved`, `manual`, `meal`,
  /// `ai_estimate` and `vita` as new logging paths shipped, while the
  /// migration still allowed only the original six.
  ///
  /// The failure was invisible and it destroyed data. Drift enforces no CHECK,
  /// so the local insert succeeded and the user saw "Logged X". The upload then
  /// failed with 23514, which matches the connector's fatal set, so the op was
  /// discarded — and once the op is gone, the next sync checkpoint reconciles
  /// the local database back to what the server holds and the row disappears.
  /// A logged meal vanished minutes later with no error anywhere.
  ///
  /// A new value here MUST ship with a migration widening the constraint;
  /// `logged_via_vocabulary_test.dart` fails the build otherwise.
  static const loggedViaValues = [
    'search',
    'photo',
    'voice',
    'barcode',
    'template',
    'quick_add',
    'recent',
    'saved',
    'manual',
    'meal',
    'ai_estimate',
    'vita',
  ];

  Stream<List<FoodLog>> watchDay(String date) => _db.watchDay(date);

  /// Every log from [fromYmd] onward, newest day first.
  ///
  /// One query for the whole window rather than N per-day watches: the Diary
  /// shows a month at a time, and thirty live streams to render one list is
  /// how a scroll turns into a battery complaint.
  Stream<List<FoodLog>> watchSince(String fromYmd) =>
      (_db.select(_db.foodLogs)
            ..where((t) => t.date.isBiggerOrEqualValue(fromYmd))
            ..orderBy([
              (t) => OrderingTerm.desc(t.date),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

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
    // Fail loudly HERE rather than silently on upload three seconds later.
    // The local database has no CHECK, so an unknown value would insert
    // cleanly, show a success snackbar, and then be reconciled away.
    if (!loggedViaValues.contains(loggedVia)) {
      throw ArgumentError.value(
          loggedVia, 'loggedVia', 'must be one of $loggedViaValues');
    }
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
  /// Edit an entry.
  ///
  /// [date] moves it to another day. Logging dinner just after midnight puts it
  /// on tomorrow, and remembering yesterday's lunch this morning puts it on
  /// today; without this the only repair was delete and re-add, which threw
  /// away the entry and its provenance to fix a one-character mistake.
  ///
  /// [servingLabel] and [servingQty] record how the portion was EXPRESSED.
  /// Grams stay the truth.
  ///
  /// The nullable columns take `Value`, not a bare nullable, because `null`
  /// has to mean two different things: `Value.absent()` (the default) leaves
  /// the column alone, `Value(null)` clears it. Written as `Value(grams)` they
  /// were full-replace, so a caller passing only `date` — a "move to
  /// yesterday" swipe, say — would silently blank the grams and the portion.
  /// No such caller exists yet, which is exactly why it was worth fixing now.
  /// Same latent bug as `WorkoutRepository.update` (#130 review).
  Future<void> update({
    required String id,
    required String meal,
    required String name,
    required double energyKcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    Value<double?> grams = const Value.absent(),
    String? date,
    Value<String?> servingLabel = const Value.absent(),
    Value<double?> servingQty = const Value.absent(),
  }) async {
    if (date != null && !_isYmd(date)) {
      throw ArgumentError.value(date, 'date', 'must be yyyy-MM-dd');
    }
    // Both present, both absent, or both explicitly cleared. Editing one
    // without the other would leave the row half-written, and the server CHECK
    // rejects that at sync time — a failure the user never sees.
    if (servingLabel.present != servingQty.present) {
      throw ArgumentError('servingLabel and servingQty must be set together');
    }
    final label = servingLabel.present ? servingLabel.value?.trim() : null;
    final qty = servingQty.present ? servingQty.value : null;
    if (servingLabel.present) {
      final hasLabel = label != null && label.isNotEmpty;
      final hasQty = qty != null;
      if (hasLabel != hasQty) {
        throw ArgumentError('servingLabel and servingQty must be set together');
      }
      if (hasQty && (!qty.isFinite || qty <= 0 || qty > 100)) {
        throw ArgumentError.value(qty, 'servingQty', 'must be 0 < q <= 100');
      }
    }

    await (_db.update(_db.foodLogs)..where((t) => t.id.equals(id))).write(
      FoodLogsCompanion(
        date: date == null ? const Value.absent() : Value(date),
        meal: Value(meal),
        name: Value(name),
        energyKcal: Value(energyKcal),
        proteinG: Value(proteinG),
        carbG: Value(carbG),
        fatG: Value(fatG),
        grams: grams,
        servingLabel: servingLabel.present
            ? Value(label != null && label.isNotEmpty ? label : null)
            : const Value.absent(),
        servingQty: servingQty,
        loggedVia: const Value('manual'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch), // LWW
      ),
    );
  }

  /// yyyy-MM-dd, and a real date. A string like '2026-13-45' passes a regex and
  /// would sort into the diary between December and nothing.
  static bool _isYmd(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
    final d = DateTime.tryParse(s);
    return d != null && s == _fmt(d);
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> delete(String id) async =>
      (_db.delete(_db.foodLogs)..where((t) => t.id.equals(id))).go();
}
