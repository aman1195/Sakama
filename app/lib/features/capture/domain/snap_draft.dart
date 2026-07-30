import 'snapped_item.dart';

/// One editable row in the PhotoSnap confirm sheet: the model's [item] plus the
/// user's live edits (portion grams, keep/drop). Macros are scaled from the
/// model's per-portion values by (userGrams / modelGrams) so adjusting the
/// portion adjusts the numbers — the "show the confidence, one-tap correct"
/// principle (PRODUCT.md).
class SnapDraft {
  SnapDraft(this.item)
      : grams = item.grams ?? _defaultGrams(item),
        keep = true;

  final SnappedItem item;
  double grams;
  bool keep;

  /// When the model gives no grams, seed from its kcal at a rough 1.3 kcal/g
  /// (a plausible mixed-Indian-food density) so the row isn't 0 g.
  static double _defaultGrams(SnappedItem i) =>
      (i.energyKcal / 1.3).clamp(10, 1000).roundToDouble();

  double get _factor {
    final base = item.grams ?? _defaultGrams(item);
    return base <= 0 ? 1 : grams / base;
  }

  double get energyKcal => item.energyKcal * _factor;
  double get proteinG => item.proteinG * _factor;
  double get carbG => item.carbG * _factor;
  double get fatG => item.fatG * _factor;
}
