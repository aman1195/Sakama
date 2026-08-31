import '../../../core/db/database.dart';
import '../../capture/data/food_log_repository.dart';
import '../../foods/data/user_food_repository.dart';
import '../domain/meal_item.dart';
import 'meal_repository.dart';

/// What one tap actually did — said out loud, never assumed.
///
/// [skipped] counts items that could not become diary rows: the saved food was
/// deleted, or a pointer's source vanished, or it has no portion weight.
/// Logging 2 of 3 silently would leave the user certain they ate what the meal
/// says, which is the quiet wrongness this codebase keeps refusing.
class MealLogResult {
  const MealLogResult({required this.logged, required this.skipped, required this.kcal});
  final int logged;
  final int skipped;
  final double kcal;
}

/// Turns a saved meal into diary rows.
///
/// THE LICENCE BOUNDARY RUNS THROUGH THIS CLASS, so the rule it obeys is worth
/// stating where the code is: nutrition resolved from `user_foods` is written
/// to **`food_logs` and nowhere else**. A food_logs row is a historical record
/// of one eating event, private behind RLS — the copy ADR 0014 permits.
/// Writing resolved values back onto the meal (caching them to skip the joins
/// on the next tap) would turn `meals` into the OFF-derived branded-food
/// catalogue docs/architecture/08 §3 exists to prevent. This service takes the
/// meals repository ONLY to call [MealRepository.markUsed]; it must never gain
/// a write that carries nutrition.
class MealLogService {
  const MealLogService({
    required this.meals,
    required this.userFoods,
    required this.foodLogs,
  });

  final MealRepository meals;
  final UserFoodRepository userFoods;
  final FoodLogRepository foodLogs;

  /// Log every resolvable item of [meal] into [mealSlot] on [date].
  ///
  /// `logged_via: 'meal'` — which the confidence badge degrades to no badge,
  /// deliberately. A meal mixes pointer items (database numbers) and custom
  /// items (the user's own numbers) under one tap, and the same food logged
  /// through the favourites path is tagged 'saved' with no badge; a shortcut
  /// must not confer more trust than the long way round.
  Future<MealLogResult> log(
    MealRow meal, {
    required String date,
    required String mealSlot,
    String? userId,
  }) async {
    var logged = 0;
    var skipped = 0;
    var kcal = 0.0;

    for (final item in MealItem.decode(meal.items)) {
      final row = await userFoods.byId(item.userFoodId);
      if (row == null) {
        skipped++; // the saved food was deleted; the meal keeps its id
        continue;
      }
      final resolved = await userFoods.resolve(row);
      final grams = row.servingGrams;
      // No nutrition or no portion weight means no diary row. Inventing either
      // would put a number nobody measured into a calorie total.
      if (resolved.nutritionMissing || grams == null || grams <= 0) {
        skipped++;
        continue;
      }

      final g = grams * item.servingQty;
      final entryKcal = resolved.energyKcal! * g / 100;
      await foodLogs.add(
        date: date,
        meal: mealSlot,
        name: row.name,
        energyKcal: entryKcal,
        proteinG: (resolved.proteinG ?? 0) * g / 100,
        carbG: (resolved.carbG ?? 0) * g / 100,
        fatG: (resolved.fatG ?? 0) * g / 100,
        grams: g,
        loggedVia: 'meal',
        userId: userId,
      );
      logged++;
      kcal += entryKcal;
    }

    // Most-used ordering reflects meals that actually logged something. A tap
    // that produced zero rows should not promote the meal that failed.
    if (logged > 0) await meals.markUsed(meal.id);

    return MealLogResult(logged: logged, skipped: skipped, kcal: kcal);
  }
}
