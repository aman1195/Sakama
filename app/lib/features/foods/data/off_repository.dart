import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../domain/food.dart';
import '../domain/food_serving.dart';
import 'off_client.dart';

/// Barcode lookup against Open Food Facts, cache-first.
///
/// ODbL CONTAINMENT (CLAUDE.md rule 5 — the biggest legal risk in the stack):
/// every row written here goes into `off_foods` and ONLY `off_foods`, tagged
/// source='openfoodfacts', licence='ODbL'. Nothing in this class may write to
/// the proprietary `foods` table; keeping the boundary structural is the whole
/// point of the separate table.
///
/// Offline-first (rule 1): a previously scanned barcode resolves from the local
/// cache with no network. A brand-new barcode needs connectivity — an accepted
/// limit of the live-lookup posture, and it does NOT affect the diary, because
/// logging copies the values into food_logs (our own data).
class OffRepository {
  OffRepository(this._db, this._client);
  final SakamaDatabase _db;
  final OffClient _client;

  /// OFF-sourced rows are third-party crowd data of variable quality, so they
  /// sit below verified reference data but at/above the unverified floor.
  static const double _offConfidence = 0.6;

  /// In-flight lookups keyed by barcode. A rapid camera can emit the same code
  /// many times before the first request returns; without this, each emission
  /// fires its own network call. Concurrent identical scans share one future.
  final _inFlight = <String, Future<Food?>>{};

  /// Resolve [barcode]. Returns null when neither the cache nor OFF knows it.
  /// Rethrows [OffLookupException] only when the cache missed AND the network
  /// failed, so the caller can distinguish "not found" from "offline".
  Future<Food?> lookup(String barcode) => _inFlight.putIfAbsent(barcode, () async {
        try {
          return await _lookup(barcode);
        } finally {
          _inFlight.remove(barcode);
        }
      });

  Future<Food?> _lookup(String barcode) async {
    final cached = await _cached(barcode);
    if (cached != null) return cached;

    final product = await _client.fetch(barcode); // may throw
    if (product == null) return null;

    await _cache(product);
    return _toFood(
      id: _idFor(product.barcode),
      name: product.displayName,
      kcal: product.energyKcal,
      protein: product.proteinG,
      carb: product.carbG,
      fat: product.fatG,
      fiber: product.fiberG,
      servingLabel: product.servingLabel,
      servingGrams: product.servingGrams,
    );
  }

  String _idFor(String barcode) => 'off-$barcode';

  Future<Food?> _cached(String barcode) async {
    final row = await (_db.select(_db.offFoods)
          ..where((t) => t.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return _toFood(
      id: row.id,
      name: row.name,
      kcal: row.energyKcal,
      protein: row.proteinG,
      carb: row.carbG,
      fat: row.fatG,
      fiber: row.fiberG,
      servingLabel: row.defaultServingLabel,
      servingGrams: row.defaultServingGrams,
    );
  }

  Future<void> _cache(OffProduct p) async {
    // View-safe upsert (PowerSync tables are views; SQLite cannot UPSERT a
    // view — SAK-34), inside a TRANSACTION so the select-then-write is atomic
    // independent of the in-flight dedupe guard (PR #49 review).
    final id = _idFor(p.barcode);
    await _db.transaction(() async {
    final exists = await (_db.select(_db.offFoods)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    final row = OffFoodsCompanion.insert(
            id: id,
            name: p.displayName,
            barcode: Value(p.barcode),
            type: 'branded',
            energyKcal: p.energyKcal,
            proteinG: p.proteinG,
            carbG: p.carbG,
            fatG: p.fatG,
            fiberG: Value(p.fiberG),
            defaultServingLabel: Value(p.servingLabel),
            defaultServingGrams: Value(p.servingGrams),
            source: 'openfoodfacts', // ODbL — never merged into `foods`
            licence: 'ODbL',
            confidence: _offConfidence,
            sourceRef: Value('OFF:${p.barcode}'),
          );
    if (exists != null) {
      await (_db.update(_db.offFoods)..where((t) => t.id.equals(id)))
          .write(row);
    } else {
      await _db.into(_db.offFoods).insert(row);
    }
    });
  }

  Food _toFood({
    required String id,
    required String name,
    required double kcal,
    required double protein,
    required double carb,
    required double fat,
    double? fiber,
    String? servingLabel,
    double? servingGrams,
  }) =>
      Food(
        id: id,
        name: name,
        type: 'branded',
        per100g: Macros(
          energyKcal: kcal,
          proteinG: protein,
          carbG: carb,
          fatG: fat,
          fiberG: fiber,
        ),
        source: 'openfoodfacts',
        licence: 'ODbL',
        confidence: _offConfidence,
        defaultServingLabel: servingLabel,
        defaultServingGrams: servingGrams,
      );
}
