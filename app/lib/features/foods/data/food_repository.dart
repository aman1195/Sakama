import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../domain/food.dart';
import '../domain/food_search.dart';
import '../domain/food_serving.dart';
import 'food_seed.dart';

/// Reads the local `foods` reference table (offline-first, CLAUDE.md rule 1).
/// Search is a broad SQL LIKE fetch ranked in Dart by [rankFoods]; seeding is
/// idempotent (runs once, when the table is empty).
class FoodRepository {
  FoodRepository(this._db);
  final SakamaDatabase _db;

  static const int _fetchCap = 200; // broad candidates, then rank + trim
  static const double _sampleConfidence = 0.5;

  /// Populate the reference table from the labelled sample if it is empty.
  /// Idempotent: a second call is a no-op. Replaced by real ingestion in M2.2.
  Future<void> ensureSeeded() async {
    final countExp = _db.foods.id.count();
    final count = await (_db.selectOnly(_db.foods)..addColumns([countExp]))
        .map((r) => r.read(countExp)!)
        .getSingle();
    if (count > 0) return;
    await _db.batch((b) {
      b.insertAll(_db.foods, [
        for (final s in kFoodSeed)
          FoodsCompanion.insert(
            id: s.id,
            name: s.name,
            nameHi: Value(s.nameHi),
            type: s.type,
            cuisineRegion: const Value.absent(),
            foodGroup: Value(s.group),
            energyKcal: s.kcal,
            proteinG: s.protein,
            carbG: s.carb,
            fatG: s.fat,
            defaultServingLabel: Value(s.servingLabel),
            defaultServingGrams: Value(s.servingGrams),
            source: 'sample',
            licence: 'CC0',
            confidence: _sampleConfidence,
          ),
      ]);
    });
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
