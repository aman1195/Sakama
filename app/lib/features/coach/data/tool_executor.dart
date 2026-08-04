import '../../capture/data/food_log_repository.dart';
import '../../water/data/water_repository.dart';
import '../../weight/data/weight_repository.dart';
import '../domain/tool_draft.dart';

/// Performs a draft the user has CONFIRMED. Nothing here validates: by the time
/// a [ToolDraft] exists, [ToolCallParser] has already bounds-checked every
/// argument, so this layer only writes.
///
/// Every row is tagged `logged_via: 'vita'` so an AI-created entry stays
/// auditable — "why does my diary say I ate this?" must be answerable.
class ToolExecutor {
  const ToolExecutor({
    required this.foodLogs,
    required this.water,
    required this.weight,
    this.userId,
  });

  final FoodLogRepository foodLogs;
  final WaterRepository water;
  final WeightRepository weight;
  final String? userId;

  static const loggedVia = 'vita';

  /// Writes [draft] for [date] (yyyy-MM-dd) and returns a short confirmation
  /// line for the transcript.
  Future<String> execute(ToolDraft draft, {required String date}) async {
    switch (draft) {
      case LogFoodDraft d:
        await foodLogs.add(
          date: date,
          meal: d.meal.key,
          name: d.name,
          energyKcal: d.energyKcal,
          proteinG: d.proteinG,
          carbG: d.carbG,
          fatG: d.fatG,
          grams: d.grams,
          loggedVia: loggedVia,
          userId: userId,
        );
      case LogWaterDraft d:
        await water.add(date: date, amountMl: d.amountMl, userId: userId);
      case LogWeightDraft d:
        await weight.add(date: date, weightKg: d.weightKg, userId: userId);
    }
    return 'Logged — ${draft.summary}.';
  }
}
