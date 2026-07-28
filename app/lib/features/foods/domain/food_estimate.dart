// AI-estimated nutrition for a named dish (M2.4). The long-tail route for
// Indian dishes after INDB was ruled out (CLAUDE.md rule 6): a model estimate,
// grounded where possible, ALWAYS marked as such.

/// A structured estimate returned by the AI gateway. Per 100 g, like every
/// reference row (CLAUDE.md canonical basis).
class FoodEstimate {
  const FoodEstimate({
    required this.name,
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fiberG,
    this.servingLabel,
    this.servingGrams,
    required this.confidence,
    this.assumptions,
  });

  final String name;
  final double energyKcal, proteinG, carbG, fatG;
  final double? fiberG;
  final String? servingLabel;
  final double? servingGrams;

  /// Model self-assessed confidence, clamped by the parser to [0.2, 0.4] —
  /// deliberately BELOW verifiedConfidenceFloor (0.5) so ranking demotes
  /// estimates one tier (issue #27's rule exists precisely for this data).
  final double confidence;

  /// What the model assumed (oil quantity, preparation), shown to the user so
  /// an estimate is never mistaken for measured data.
  final String? assumptions;
}
