import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/theme.dart';

/// Contrast per WCAG 2.x. Written out rather than pulled in, because a
/// dependency for one formula is not worth a licence review.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final (hi, lo) = lum(a) > lum(b) ? (lum(a), lum(b)) : (lum(b), lum(a));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('the accent marks identity, never judgement', () {
    // The whole point of the refresh's one deviation from its references.
    // PRODUCT.md principle 5 and anti-reference #1 both live or die here.
    test('the accent is not reused as a macro colour', () {
      for (final b in Brightness.values) {
        final c = SakamaColors.of(b);
        for (final macro in [c.protein, c.carbs, c.fat, c.water]) {
          expect(macro, isNot(SakamaPalette.accent),
              reason: 'a macro tinted with the brand accent would read as '
                  '"this number is good", which is exactly the judgement '
                  'colouring we refused to copy');
        }
      }
    });

    test('no macro colour is alarm-red', () {
      // Red is reserved for genuine problems. A macro that happens to be red
      // makes every glance at the diary feel like a warning.
      for (final b in Brightness.values) {
        final c = SakamaColors.of(b);
        for (final macro in [c.protein, c.carbs, c.fat, c.water]) {
          final isRedish = macro.r > 0.7 && macro.g < 0.35 && macro.b < 0.35;
          expect(isRedish, isFalse, reason: 'reserved for real problems');
        }
      }
    });

    test('each macro keeps a distinct identity', () {
      for (final b in Brightness.values) {
        final c = SakamaColors.of(b);
        final all = {c.protein, c.carbs, c.fat, c.water};
        expect(all, hasLength(4),
            reason: 'recognition over decoration — two macros sharing a '
                'colour defeats the point of having them');
      }
    });
  });

  group('the accent is legible where it is actually used', () {
    test('light mode uses the darkened accent for primary', () {
      // The raw lime cannot carry white text. Shipping it as `primary` in
      // light mode would put unreadable buttons on the most common surface.
      final t = sakamaTheme(Brightness.light);
      expect(t.colorScheme.primary, SakamaPalette.accentInk);
      expect(_contrast(t.colorScheme.primary, Colors.white),
          greaterThanOrEqualTo(4.5),
          reason: 'WCAG AA for button text');
    });

    test('dark mode uses the raw accent, on near-black', () {
      final t = sakamaTheme(Brightness.dark);
      expect(t.colorScheme.primary, SakamaPalette.accent);
      expect(_contrast(SakamaPalette.accent, SakamaPalette.inkDark),
          greaterThanOrEqualTo(4.5));
    });

    test('body text clears AA on both scaffolds', () {
      for (final b in Brightness.values) {
        final t = sakamaTheme(b);
        expect(
            _contrast(t.colorScheme.onSurface, t.scaffoldBackgroundColor),
            greaterThanOrEqualTo(4.5),
            reason: '$b body text must be readable');
      }
    });
  });

  test('the bundled font is applied, not fetched at runtime', () {
    // Offline-first (rule 1): typography must not depend on a network call.
    for (final b in Brightness.values) {
      expect(sakamaTheme(b).textTheme.titleLarge!.fontFamily, 'PlusJakartaSans');
    }
  });

  test('primary actions clear the touch-target floor', () {
    final style = sakamaTheme(Brightness.light).filledButtonTheme.style!;
    final size = style.minimumSize!.resolve({})!;
    expect(size.height, greaterThanOrEqualTo(48),
        reason: 'used one-handed, mid-meal');
  });
}
