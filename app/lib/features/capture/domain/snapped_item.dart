// One food the model identified in a meal photo (M3.2 PhotoSnap). Per PORTION,
// not per-100g — the photo is of a specific serving.
class SnappedItem {
  const SnappedItem({
    required this.name,
    required this.portionLabel,
    this.grams,
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.confidence,
  });

  final String name;
  final String portionLabel; // "1 katori", "2 roti"
  /// Model's portion estimate in grams; null when it didn't give one
  /// (3.2b's confirm sheet asks the user).
  final double? grams;
  final double energyKcal, proteinG, carbG, fatG;

  /// Model self-assessed, clamped to [0.2, 0.49] by the parser — STRICTLY
  /// below verifiedConfidenceFloor (0.5), because a photo item is source=
  /// 'ai_estimate' and must be ranking-demoted below verified data (rule 7).
  /// The near-ceiling reflects "photo evidence beats a blind text guess".
  final double confidence;
}
