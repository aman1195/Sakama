import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/status_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/core/settings/status_colour_pref.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The valve for colour-as-judgement (PRODUCT.md principle 5).
///
/// Colour says "bad" before a word is read. The guardrails soften that; they
/// cannot remove it. These tests fix the two properties that make the opt-out
/// trustworthy: it defaults to the intended experience, and turning it off
/// removes the judgement WITHOUT removing any data.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the preference itself', () {
    test('defaults ON — absence means the default experience', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await StatusColourPref(prefs: prefs).enabled(), isTrue,
          reason: 'the fintech treatment is the intended default; a missing '
              'key must not silently mute the app');
    });

    test('the choice persists', () async {
      final prefs = await SharedPreferences.getInstance();
      await StatusColourPref(prefs: prefs).set(false);
      // A fresh instance, as after a restart.
      expect(await StatusColourPref(prefs: prefs).enabled(), isFalse);
    });
  });

  group('opting out removes the judgement, not the data', () {
    testWidgets('a neutral surface still renders its children', (t) async {
      // The property that matters: the switch changes the FILL. Every number
      // on the card must survive, or the opt-out becomes a data toggle.
      const marker = '1,240 kcal left';
      for (final status in [TrackStatus.over, TrackStatus.neutral]) {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: StatusSurface(
              status: status,
              identifier: 'card',
              child: const Text(marker),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text(marker), findsOneWidget,
            reason: '$status must not hide the numbers');
      }
    });

    test('muted is not one of the judgement fills', () {
      // Opting out must WITHHOLD a verdict, not pick a quieter one.
      //
      // This used to assert the same of `neutral`. That changed on device:
      // making an empty day grey meant the very first screen anyone opens had
      // no colour at all and the treatment was invisible. `neutral` now shares
      // the BRAND colour with onTrack — a card reading "1,750 kcal left"
      // praises nothing — and `muted` carries the opt-out instead.
      for (final b in Brightness.values) {
        final muted = TrackStatus.muted.surface(b);
        for (final judged in [
          TrackStatus.nearing,
          TrackStatus.over,
          TrackStatus.onTrack,
        ]) {
          expect(muted, isNot(judged.surface(b)));
        }
      }
    });

    test('an empty day is the brand colour, not a verdict', () {
      // The fix for the grey first screen, pinned so it cannot regress.
      for (final b in Brightness.values) {
        expect(TrackStatus.neutral.surface(b), TrackStatus.onTrack.surface(b),
            reason: 'a normal day should look like the app');
        expect(TrackStatus.neutral.surface(b),
            isNot(TrackStatus.over.surface(b)));
      }
    });
  });


  group('the opt-out must not flash on cold start', () {
    // The #127 review nit, and the reason the provider is synchronous. As a
    // FutureProvider the card rendered COLOURED for the first frame(s), then
    // snapped to neutral — showing an opted-out user exactly the judgement
    // they had switched off, every single launch.
    test('an opted-out preference reads false on the FIRST synchronous read',
        () async {
      SharedPreferences.setMockInitialValues({'status_colour_enabled': false});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      // No pump, no await: this is what the first frame sees.
      expect(container.read(statusColourEnabledProvider), isFalse,
          reason: 'a frame of colour is the whole thing being opted out of');
    });

    test('without prefs wired it yields the DEFAULT, never a wrong verdict',
        () {
      // Widget tests mount screens without prefs. Degrading to the default
      // experience is correct; crashing the screen over a display setting is
      // not, and Riverpod turns a throw here into an error state for every
      // dependent provider.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(statusColourEnabledProvider), isTrue);
    });
  });
}
