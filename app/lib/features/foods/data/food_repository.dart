import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/database.dart';
import '../domain/food.dart';
import '../domain/food_search.dart';
import '../domain/food_serving.dart';
import 'food_seed.dart';

/// Reads the local `foods` reference table (offline-first, CLAUDE.md rule 1).
/// Search is a broad SQL LIKE fetch ranked in Dart by [rankFoods]; seeding is
/// version-gated so shipped data updates reach existing installs.
class FoodRepository {
  FoodRepository(this._db);
  final SakamaDatabase _db;

  static const int _fetchCap = 200; // broad candidates, then rank + trim

  /// Bump when the bundled seed data changes so existing installs reload.
  ///   1 = M2.1 Indian sample only
  ///   2 = M2.2a + USDA SR Legacy (CC0)
  static const int seedVersion = 2;
  static const _seedVersionKey = 'foods.seed_version';

  /// Populate `foods` from [source] when the install's loaded seed version is
  /// behind [seedVersion]. Idempotent within a version. On a version bump the
  /// table is cleared and reloaded — safe because `foods` is reference data,
  /// never user data. No schema migration: only rows change, not columns.
  Future<void> ensureSeeded(FoodSeedSource source) async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(_seedVersionKey) ?? 0) >= seedVersion) return;

    final entries = await source.load();
    await _db.transaction(() async {
      await _db.delete(_db.foods).go(); // clean reload; reference data only
      await _db.batch((b) {
        b.insertAll(_db.foods, [
          for (final e in entries)
            FoodsCompanion.insert(
              id: e.id,
              name: e.name,
              nameHi: Value(e.nameHi),
              type: e.type,
              cuisineRegion: const Value.absent(),
              foodGroup: Value(e.foodGroup),
              energyKcal: e.energyKcal,
              proteinG: e.proteinG,
              carbG: e.carbG,
              fatG: e.fatG,
              fiberG: Value(e.fiberG),
              defaultServingLabel: Value(e.servingLabel),
              defaultServingGrams: Value(e.servingGrams),
              source: e.source,
              licence: e.licence,
              confidence: e.confidence,
              sourceRef: Value(e.sourceRef),
            ),
        ]);
      });
    });
    await prefs.setInt(_seedVersionKey, seedVersion);
  }

  /// Ranked search results for [query]. Empty query => no results.
  Future<List<Food>> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${q.toLowerCase()}%';
    final rows = await (_db.select(_db.foods)
          ..where((t) => t.name.lower().like(like))
          ..limit(_fetchCap))
        .get();
    final foods = rows.map(_toFood).toList();
    final ranked = rankFoods(q, foods);
    return ranked.take(limit).toList();
  }

  Food _toFood(FoodRow r) => Food(
        id: r.id,
        name: r.name,
        nameHi: r.nameHi,
        type: r.type,
        per100g: Macros(
          energyKcal: r.energyKcal,
          proteinG: r.proteinG,
          carbG: r.carbG,
          fatG: r.fatG,
          fiberG: r.fiberG,
        ),
        source: r.source,
        licence: r.licence,
        confidence: r.confidence,
        defaultServingLabel: r.defaultServingLabel,
        defaultServingGrams: r.defaultServingGrams,
      );
}
