import 'package:freezed_annotation/freezed_annotation.dart';

part 'nutrition_targets.freezed.dart';

/// A day's computed targets. All grams are whole numbers (nobody logs against
/// 0.3 g of protein); calories rounded to the nearest 10 for a calm UI.
@freezed
abstract class NutritionTargets with _$NutritionTargets {
  const factory NutritionTargets({
    required int calories,
    required int proteinG,
    required int carbG,
    required int fatG,
    required int fiberG,
    required int waterMl,
  }) = _NutritionTargets;
}
