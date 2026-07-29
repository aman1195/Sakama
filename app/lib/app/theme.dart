import 'package:flutter/material.dart';

/// Warm, not clinical (PRODUCT.md). Green is the single "on-track" accent;
/// red is reserved for genuine problems — never a calorie overshoot.
///
/// Visual pass (SAK-37): a small token layer instead of a rebrand — per-macro
/// identity colors (used ONLY for those macros, everywhere), a warm dark
/// surface to match the warm light one, and a consistent 16dp card language.
ThemeData sakamaTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D32),
    brightness: brightness,
  );
  final light = brightness == Brightness.light;
  return ThemeData(
    colorScheme: scheme,
    // Warm neutral both ways: paper-warm in light, charcoal-warm in dark.
    scaffoldBackgroundColor:
        light ? const Color(0xFFFAF7F2) : const Color(0xFF141613),
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: light ? Colors.white : const Color(0xFF1D201C),
      margin: EdgeInsets.zero,
    ),
    extensions: [SakamaColors.of(brightness)],
  );
}

/// Semantic accents beyond the Material scheme. Each macro keeps ONE identity
/// color across the whole app (bars, chips, detail views) — recognition over
/// decoration. Muted enough to sit on warm surfaces without shouting.
class SakamaColors extends ThemeExtension<SakamaColors> {
  const SakamaColors({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
    required this.softTint,
  });

  /// Deep teal / warm ochre / soft plum: distinct at a glance, none of them
  /// the on-track green, none of them alarm-red.
  final Color protein;
  final Color carbs;
  final Color fat;
  final Color water;

  /// Barely-there tint for icon circles and empty-state shapes.
  final Color softTint;

  static SakamaColors of(Brightness b) => b == Brightness.light
      ? const SakamaColors(
          protein: Color(0xFF00796B),
          carbs: Color(0xFFB07B22),
          fat: Color(0xFF7E57A5),
          water: Color(0xFF0288D1),
          softTint: Color(0x14000000),
        )
      : const SakamaColors(
          protein: Color(0xFF4DB6AC),
          carbs: Color(0xFFD9A554),
          fat: Color(0xFFB39DDB),
          water: Color(0xFF4FC3F7),
          softTint: Color(0x1FFFFFFF),
        );

  @override
  SakamaColors copyWith(
          {Color? protein, Color? carbs, Color? fat, Color? water, Color? softTint}) =>
      SakamaColors(
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        water: water ?? this.water,
        softTint: softTint ?? this.softTint,
      );

  @override
  SakamaColors lerp(SakamaColors? other, double t) {
    if (other == null) return this;
    return SakamaColors(
      protein: Color.lerp(protein, other.protein, t)!,
      carbs: Color.lerp(carbs, other.carbs, t)!,
      fat: Color.lerp(fat, other.fat, t)!,
      water: Color.lerp(water, other.water, t)!,
      softTint: Color.lerp(softTint, other.softTint, t)!,
    );
  }
}

extension SakamaColorsX on BuildContext {
  /// Falls back to brightness defaults when the extension is absent (e.g. a
  /// bare MaterialApp in a widget test) — visual tokens must never be the
  /// reason a build throws.
  SakamaColors get sakamaColors =>
      Theme.of(this).extension<SakamaColors>() ??
      SakamaColors.of(Theme.of(this).brightness);
}
