// One food the model identified in a meal photo (M3.2 PhotoSnap). Per PORTION,
// not per-100g — the photo is of a specific serving.
class SnappedItem {
  const SnappedItem({
    required this.name,
    required this.portionLabel,
    required this.grams,
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.confidence,
  });

  final String name;
  final String portionLabel; // "1 katori", "2 roti"
  final double grams;
  final double energyKcal, proteinG, carbG, fatG;

  /// Model self-assessed, clamped to [0.2, 0.6] by the parser — a photo item is
  /// never "verified" (source='ai_estimate' territory), so it stays below the
  /// verified floor for ranking, but photo evidence beats a blind text guess.
  final double confidence;
}
