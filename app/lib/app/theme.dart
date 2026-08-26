import 'package:flutter/material.dart';

/// The visual system (SAK-124 refresh).
///
/// DIRECTION, and what we deliberately did NOT take. The refresh draws its
/// grammar from a set of modern fintech references: near-black surfaces, a
/// single saturated accent, large confident display numerals, generous corner
/// radii, pill-shaped controls, and a floating bottom bar. That grammar
/// transfers to a health app almost entirely.
///
/// One thing does not, and it is the important one. Those references colour an
/// ENTIRE card by a single metric — a lime balance card when the number is
/// good, a red portfolio card when it is bad. In fintech that is neutral
/// information about money. In a health app it is the guilt loop PRODUCT.md
/// names as anti-reference #1, and it contradicts principle 5 outright:
/// "Earn every colour... never colour the whole screen by a calorie deficit."
///
/// So: the accent marks IDENTITY (brand surfaces, the primary action, the
/// selected tab), never JUDGEMENT. Amber and red stay reserved for attention
/// and genuine problems, exactly as before.
ThemeData sakamaTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: SakamaPalette.accent,
    brightness: brightness,
  ).copyWith(
    primary: light ? SakamaPalette.accentInk : SakamaPalette.accent,
  );

  final base = light ? ThemeData.light() : ThemeData.dark();
  final text = base.textTheme.apply(fontFamily: _font).copyWith(
        // Display sizes carry the reference's confidence: a day's calorie
        // total should read like a headline, not a table cell.
        displaySmall: const TextStyle(
            fontFamily: _font, fontWeight: FontWeight.w800, letterSpacing: -1.2),
        headlineMedium: const TextStyle(
            fontFamily: _font, fontWeight: FontWeight.w700, letterSpacing: -0.8),
        titleLarge: const TextStyle(
            fontFamily: _font, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
        labelLarge: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      );

  return ThemeData(
    colorScheme: scheme,
    fontFamily: _font,
    textTheme: text,
    scaffoldBackgroundColor: light ? SakamaPalette.paper : SakamaPalette.inkDark,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      // 20, up from 16: the references round harder, and it reads softer
      // without tipping into novelty.
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: light ? Colors.white : SakamaPalette.surfaceDark,
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Pill controls, and a height that clears the 48dp touch target with
        // room to spare — this is a phone used mid-meal, often one-handed.
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(
            fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: const StadiumBorder()),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : SakamaPalette.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : SakamaPalette.surfaceDark,
      indicatorColor: SakamaPalette.accent,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    extensions: [SakamaColors.of(brightness)],
  );
}

const _font = 'PlusJakartaSans';

/// The palette, named by ROLE rather than by hue, so a later re-skin cannot
/// accidentally turn "on track" into "problem".
abstract final class SakamaPalette {
  /// Identity. Used for brand surfaces, the primary action and the selected
  /// tab — NEVER to signal that a number is good or bad.
  static const accent = Color(0xFF98EF5A);

  /// The same hue darkened enough to carry white text and to pass contrast on
  /// a light background, where the raw accent cannot.
  static const accentInk = Color(0xFF2E7D32);

  static const inkDark = Color(0xFF101010);
  static const surfaceDark = Color(0xFF1A1C19);

  /// Warm paper, kept from the previous system: PRODUCT.md asks for warm, not
  /// clinical, and a pure-white light mode reads colder than the brand wants.
  static const paper = Color(0xFFFAF7F2);
}

/// Semantic accents beyond the Material scheme. Each macro keeps ONE identity
/// color across the whole app (bars, chips, detail views) — recognition over
/// decoration.
class SakamaColors extends ThemeExtension<SakamaColors> {
  const SakamaColors({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
    required this.softTint,
  });

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
      // Lifted for the darker surface: the old values were tuned against
      // #141613 and go muddy on near-black.
      : const SakamaColors(
          protein: Color(0xFF5FD4C6),
          carbs: Color(0xFFE8B65E),
          fat: Color(0xFFC0A9E8),
          water: Color(0xFF5CCBFA),
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
  SakamaColors lerp(ThemeExtension<SakamaColors>? other, double t) {
    if (other is! SakamaColors) return this;
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
