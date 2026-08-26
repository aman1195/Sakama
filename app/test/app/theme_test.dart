import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/status_surface.dart';
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
  group('status colours: the whole-surface treatment, with guardrails', () {
    // REVERSAL, recorded. These tests previously asserted the opposite — that
    // the accent could never signal state. PRODUCT.md principle 5 was amended
    // on 2026-08-26 to colour the surface by state; what survives is the set
    // of guardrails that keep a loud signal from becoming a guilt loop.

    test('over starts PAST the target, not near it', () {
      // The one that matters most. A person eating their planned dinner
      // crosses 90% every day; treating that as "over" would make the app
      // shout at normal eating.
      expect(trackStatus(value: 1799, target: 2000), TrackStatus.onTrack);
      expect(trackStatus(value: 1800, target: 2000), TrackStatus.nearing,
          reason: 'exactly 90% is where noticing starts');
      expect(trackStatus(value: 2000, target: 2000), TrackStatus.nearing,
          reason: 'hitting the target exactly is not overshooting it');
      expect(trackStatus(value: 2001, target: 2000), TrackStatus.over);
    });

    test('an empty or target-less day is neutral, not "good"', () {
      // Logging nothing is not being on track. Colouring it lime would
      // congratulate a user for not eating.
      expect(trackStatus(value: 0, target: 2000), TrackStatus.neutral);
      expect(trackStatus(value: 500, target: 0), TrackStatus.neutral);
    });

    test('every status clears WCAG AA on its own fill', () {
      // A saturated card that cannot carry its own text is worse than no
      // colour at all.
      for (final b in Brightness.values) {
        for (final st in TrackStatus.values) {
          expect(_contrast(st.on(b), st.surface(b)), greaterThanOrEqualTo(4.5),
              reason: '$st on $b must be readable');
        }
      }
    });

    test('over is warm, not alarm red', () {
      // Guardrail from principle 5: past target is information, not an
      // emergency. Pure red belongs to genuine problems.
      final over = TrackStatus.over.surface(Brightness.dark);
      expect(over.g, greaterThan(0.35),
          reason: 'a warm red keeps some green; alarm red does not');
    });

    test('macro colours are identity, never status', () {
      // Protein is teal because it is protein. If a macro drifted onto a
      // status colour, a glance could not tell "this is fat" from
      // "this is going badly".
      final statuses = {
        for (final b in Brightness.values)
          for (final st in TrackStatus.values) st.surface(b)
      };
      for (final b in Brightness.values) {
        final c = SakamaColors.of(b);
        for (final macro in [c.protein, c.carbs, c.fat, c.water]) {
          expect(statuses.contains(macro), isFalse);
        }
      }
    });

    test('each macro keeps a distinct identity', () {
      for (final b in Brightness.values) {
        final c = SakamaColors.of(b);
        expect({c.protein, c.carbs, c.fat, c.water}, hasLength(4),
            reason: 'recognition over decoration');
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
