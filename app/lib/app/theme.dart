import 'package:flutter/material.dart';

/// Warm, not clinical (PRODUCT.md). Green is the single "on-track" accent;
/// red is reserved for genuine problems — never a calorie overshoot.
ThemeData sakamaTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D32),
    brightness: brightness,
  );
  final warmSurface =
      brightness == Brightness.light ? const Color(0xFFFAF7F2) : null;
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: warmSurface,
    useMaterial3: true,
  );
}
