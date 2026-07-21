/// Per-100g → per-portion nutrition. Nutrition is stored canonically per 100 g
/// (CLAUDE.md); the logged portion is DERIVED here at read time, never stored.
/// Drift-free so it is trivially unit-tested.
class Macros {
  const Macros({
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fiberG,
  });

  final double energyKcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final double? fiberG;

  /// These values are per 100 g; scale them to [grams].
  Macros scaleTo(double grams) {
    final f = grams / 100.0;
    return Macros(
      energyKcal: energyKcal * f,
      proteinG: proteinG * f,
      carbG: carbG * f,
      fatG: fatG * f,
      fiberG: fiberG == null ? null : fiberG! * f,
    );
  }
}
