import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/workouts/domain/energy_burn.dart';

void main() {
  group('metFor', () {
    test('matches an activity embedded in a natural phrase', () {
      expect(EnergyBurn.metFor('evening run in the park'), 9.8);
      expect(EnergyBurn.metFor('30 min cycle'), 7.5);
    });

    test('prefers the longer key so a qualifier is not lost', () {
      // 'brisk walking' contains 'walk'; the generic entry must not win, or a
      // brisk walk would be scored as a stroll.
      expect(EnergyBurn.metFor('brisk walking'), 4.3);
      expect(EnergyBurn.metFor('walking'), 3.5);
      expect(EnergyBurn.metFor('evening power walk'), 4.3);
    });

    test('returns null for an activity we do not know', () {
      expect(EnergyBurn.metFor('kabaddi'), isNull);
      expect(EnergyBurn.metFor(''), isNull);
      expect(EnergyBurn.metFor('   '), isNull);
    });
  });

  group('estimate', () {
    test('scales with body weight, which is the whole point', () {
      final light = EnergyBurn.estimate(
          activity: 'running', durationMin: 40, weightKg: 55)!;
      final heavy = EnergyBurn.estimate(
          activity: 'running', durationMin: 40, weightKg: 95)!;
      expect(light, closeTo(377, 2)); // 9.8*3.5*55/200*40
      expect(heavy, closeTo(651, 2));
      // A weight-blind formula would return the same number for both. It does
      // not, and the gap is a third of a day's deficit.
      expect(heavy - light, greaterThan(250));
    });

    test('is null — never 0 — whenever an input is missing', () {
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: null, weightKg: 70),
          isNull);
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: 40, weightKg: null),
          isNull);
      expect(
          EnergyBurn.estimate(
              activity: 'kabaddi', durationMin: 40, weightKg: 70),
          isNull);
    });

    test('rejects nonsense inputs rather than propagating them', () {
      for (final w in [0.0, -70.0, double.nan, double.infinity]) {
        expect(
            EnergyBurn.estimate(
                activity: 'running', durationMin: 40, weightKg: w),
            isNull,
            reason: 'weight $w must not produce a burn');
      }
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: 0, weightKg: 70),
          isNull);
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: -30, weightKg: 70),
          isNull);
    });
  });

  group('output bounds', () {
    test('refuses an absurd duration rather than computing off it', () {
      // WorkoutRepository.add is callable directly, so a manual-entry screen
      // could hand this a month-long session.
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: 1441, weightKg: 70),
          isNull);
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: 43200, weightKg: 70),
          isNull);
    });

    test('refuses an absurd body weight', () {
      expect(
          EnergyBurn.estimate(
              activity: 'running', durationMin: 30, weightKg: 1001),
          isNull);
    });

    test('a genuinely hard endurance day still computes', () {
      // Four hours of running at 80 kg — an Ironman-shaped day. The cap must
      // not discard real training.
      final k = EnergyBurn.estimate(
          activity: 'running', durationMin: 240, weightKg: 80);
      expect(k, closeTo(3292, 2));
    });

    test('a physiologically impossible total is refused', () {
      // 24 hours of continuous skipping computes to about 31,000 kcal. The
      // highest expenditure ever recorded for a human day is roughly a third
      // of that, so this is a bad input wearing the shape of a workout, and
      // the number would be subtracted from a calorie target.
      expect(
          EnergyBurn.estimate(
              activity: 'skipping', durationMin: 1440, weightKg: 100),
          isNull);
    });
  });
}
