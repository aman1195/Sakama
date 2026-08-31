import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// A user food resolved for display: the user's name and portion, plus the
/// nutrition read from wherever it actually lives.
///
/// [nutritionMissing] is true when a pointer's target has gone (the OFF cache
/// is a live-lookup cache per ADR 0014, and the corpus is reseeded on version
/// bumps). The row still shows, tappable and completable by hand — never a
/// crash, never a silent zero.
class ResolvedUserFood {
  const ResolvedUserFood({
    required this.row,
    this.energyKcal,
    this.proteinG,
    this.carbG,
    this.fatG,
    this.fiberG,
  });

  final UserFoodRow row;

  /// Per 100 g, or null when a pointer's source has vanished.
  final double? energyKcal, proteinG, carbG, fatG, fiberG;

  bool get nutritionMissing => energyKcal == null;

  /// Calories for the user's saved portion, when both are known.
  double? get portionKcal => (energyKcal == null || row.servingGrams == null)
      ? null
      : energyKcal! * row.servingGrams! / 100;
}

/// Favourites and custom foods (docs/architecture/08-user-foods.md).
///
/// LICENCE, enforced by the shape of this API rather than by discipline
/// (CLAUDE.md rule 5): [addPointer] accepts **no nutrition arguments at all**,
/// so a caller cannot copy Open Food Facts values into this synced table even
/// by accident — there is nowhere to put them. [addCustom] is the only method
/// that takes nutrition, and by definition those numbers are the user's own.
/// A matching CHECK constraint enforces the same thing server-side.
class UserFoodRepository {
  UserFoodRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;
  final SakamaDatabase _db;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  static const pointer = 'pointer';
  static const custom = 'custom';
  static const sourceFoods = 'foods';
  static const sourceOffFoods = 'off_foods';

  /// Keep a food that already exists in a source table.
  ///
  /// Takes NO nutrition: the values stay where they are and are read at display
  /// time. That is what keeps ODbL data out of this table (see the class doc).
  Future<String> addPointer({
    required String name,
    required String sourceTable,
    required String sourceId,
    String? servingLabel,
    double? servingGrams,
    String? userId,
  }) async {
    final id = uuid.v4();
    final now = _now;
    await _db.into(_db.userFoods).insert(UserFoodsCompanion.insert(
          id: id,
          userId: Value(userId),
          name: name.trim(),
          kind: pointer,
          sourceTable: Value(sourceTable),
          sourceId: Value(sourceId),
          servingLabel: Value(servingLabel),
          servingGrams: Value(servingGrams),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  /// Create a food that exists nowhere else — "mum's rajma". Nutrition is per
  /// 100 g, the canonical unit used everywhere in the app.
  Future<String> addCustom({
    required String name,
    required double energyKcal,
    double proteinG = 0,
    double carbG = 0,
    double fatG = 0,
    double? fiberG,
    String? servingLabel,
    double? servingGrams,
    String? userId,
  }) async {
    final id = uuid.v4();
    final now = _now;
    await _db.into(_db.userFoods).insert(UserFoodsCompanion.insert(
          id: id,
          userId: Value(userId),
          name: name.trim(),
          kind: custom,
          energyKcal: Value(energyKcal),
          proteinG: Value(proteinG),
          carbG: Value(carbG),
          fatG: Value(fatG),
          fiberG: Value(fiberG),
          servingLabel: Value(servingLabel),
          servingGrams: Value(servingGrams),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  /// Saved foods, most-used first (the point is to shorten the common path).
  Stream<List<UserFoodRow>> watchAll(String? userId) =>
      (_db.select(_db.userFoods)
            ..where((t) => _ownedBy(t, userId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.useCount),
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.id), // deterministic tiebreak
            ]))
          .watch();

  /// Resolve nutrition for one row, following the pointer to its source.
  ///
  /// A pointer FOLLOWS its source and never freezes it: freezing would mean
  /// copying the values in, which for an OFF row is precisely the ODbL merge
  /// this design exists to prevent (docs/architecture/08 §8).
  Future<ResolvedUserFood> resolve(UserFoodRow row) async {
    if (row.kind == custom) {
      return ResolvedUserFood(
        row: row,
        energyKcal: row.energyKcal,
        proteinG: row.proteinG,
        carbG: row.carbG,
        fatG: row.fatG,
        fiberG: row.fiberG,
      );
    }
    final id = row.sourceId;
    if (id == null) return ResolvedUserFood(row: row);

    if (row.sourceTable == sourceFoods) {
      final f = await (_db.select(_db.foods)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (f == null) return ResolvedUserFood(row: row); // reseeded away
      return ResolvedUserFood(
        row: row, energyKcal: f.energyKcal, proteinG: f.proteinG,
        carbG: f.carbG, fatG: f.fatG, fiberG: f.fiberG,
      );
    }
    if (row.sourceTable == sourceOffFoods) {
      final f = await (_db.select(_db.offFoods)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (f == null) return ResolvedUserFood(row: row); // cache evicted
      return ResolvedUserFood(
        row: row, energyKcal: f.energyKcal, proteinG: f.proteinG,
        carbG: f.carbG, fatG: f.fatG, fiberG: f.fiberG,
      );
    }
    return ResolvedUserFood(row: row); // unknown source: degrade, never crash
  }

  Future<List<ResolvedUserFood>> resolveAll(List<UserFoodRow> rows) async =>
      [for (final r in rows) await resolve(r)];

  /// One saved food by id, or null when it has been removed.
  ///
  /// Meals hold user_foods IDS (docs/architecture/08 §3), so meal logging
  /// looks rows up at log time rather than carrying values of its own. A null
  /// here is a normal state — the user deleted a saved food a meal still
  /// references — and the caller degrades, it does not crash.
  Future<UserFoodRow?> byId(String id) =>
      (_db.select(_db.userFoods)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Record a use, so most-used ordering reflects reality.
  Future<void> markUsed(String id) async {
    await _db.customUpdate(
      'UPDATE user_foods SET use_count = use_count + 1, updated_at = ? '
      'WHERE id = ?',
      variables: [Variable.withInt(_now), Variable.withString(id)],
      updates: {_db.userFoods},
    );
  }

  Future<void> rename(String id, String name) async {
    await (_db.update(_db.userFoods)..where((t) => t.id.equals(id))).write(
        UserFoodsCompanion(
            name: Value(name.trim()), updatedAt: Value(_now)));
  }

  Future<void> remove(String id) async {
    await (_db.delete(_db.userFoods)..where((t) => t.id.equals(id))).go();
  }

  /// Same strict scoping as every other per-user read: a null owner matches
  /// only pre-auth rows, never "everybody".
  Expression<bool> _ownedBy($UserFoodsTable t, String? userId) =>
      userId == null ? t.userId.isNull() : t.userId.equals(userId);
}
