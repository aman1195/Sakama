import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../domain/meal_item.dart';

/// Saved meals: a named group of saved foods, logged in one tap.
///
/// The largest repetition kill available. People eat the same breakfast for
/// months and re-enter it every morning, which is what makes tracking collapse
/// around week three.
class MealRepository {
  MealRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;
  final SakamaDatabase _db;
  final DateTime Function() _clock;

  static const meals = ['breakfast', 'lunch', 'dinner', 'snack'];

  Stream<List<MealRow>> watchAll({String? userId}) =>
      (_db.select(_db.meals)
            ..where((t) => _owner(t, userId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.useCount),
              (t) => OrderingTerm.desc(t.updatedAt),
            ]))
          .watch();

  Future<String> create({
    required String name,
    required List<MealItem> items,
    String? defaultMeal,
    String? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    // A meal with nothing in it is not a meal, and logging it would silently
    // do nothing while looking like it worked.
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'a meal needs at least one food');
    }
    if (defaultMeal != null && !meals.contains(defaultMeal)) {
      throw ArgumentError.value(defaultMeal, 'defaultMeal', 'unknown meal slot');
    }
    final id = uuid.v4();
    final at = _clock().millisecondsSinceEpoch;
    await _db.into(_db.meals).insert(MealsCompanion.insert(
          id: id,
          userId: Value(userId),
          name: trimmed,
          items: Value(MealItem.encode(items)),
          defaultMeal: Value(defaultMeal),
          createdAt: at,
          updatedAt: at,
        ));
    return id;
  }

  Future<void> markUsed(String id) async {
    final row = await (_db.select(_db.meals)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.meals)..where((t) => t.id.equals(id))).write(
      MealsCompanion(
        useCount: Value(row.useCount + 1),
        updatedAt: Value(_clock().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    return (_db.update(_db.meals)..where((t) => t.id.equals(id))).write(
      MealsCompanion(
        name: Value(trimmed),
        updatedAt: Value(_clock().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> remove(String id) =>
      (_db.delete(_db.meals)..where((t) => t.id.equals(id))).go();

  /// Same strict scoping as every other per-user read: a null owner matches
  /// only pre-auth rows, never everybody.
  Expression<bool> _owner($MealsTable t, String? userId) =>
      userId == null ? t.userId.isNull() : t.userId.equals(userId);
}
