import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/coach/domain/history_summary.dart';

/// Vita could only ever see TODAY, so "what did I average this week?" — one of
/// the two questions people most naturally ask a coach — was unanswerable.
FoodLog _log(String date, double kcal, {double protein = 0, String? id}) =>
    FoodLog(
      id: id ?? '$date-$kcal',
      userId: null,
      date: date,
      meal: 'lunch',
      name: 'dal',
      grams: null,
      energyKcal: kcal,
      proteinG: protein,
      carbG: 0,
      fatG: 0,
      loggedVia: 'manual',
      createdAt: 1,
      updatedAt: 1,
    );

WeightLog _w(String date, double kg) => WeightLog(
      id: date, userId: null, date: date, weightKg: kg,
      note: null, createdAt: 1, updatedAt: 1,
    );

void main() {
  test('averages over DAYS LOGGED, not over the window', () {
    // The trap: dividing by the window reports someone who logged two good
    // days out of seven as eating 500 kcal a day — wrong, and alarming.
    final s = HistorySummary.from(
      logs: [_log('2026-08-01', 2000), _log('2026-08-02', 1800)],
      windowDays: 7,
      calorieTarget: 2000,
    );
    expect(s.avgCalories, 1900);
    expect(s.daysLogged, 2,
        reason: 'reported separately so the average can be read with the '
            'right amount of trust');
  });

  test('multiple entries on one day are ONE day, summed', () {
    final s = HistorySummary.from(
      logs: [
        _log('2026-08-01', 500, id: 'a'),
        _log('2026-08-01', 700, id: 'b'),
      ],
      windowDays: 7,
      calorieTarget: 2000,
    );
    expect(s.daysLogged, 1);
    expect(s.avgCalories, 1200);
  });

  group('"on target" means WITHIN the band, not under it', () {
    test('a heavy under-eat does not count as success', () {
      // Scoring under-eating as on-target teaches the wrong thing — the same
      // rule the Diary summary follows.
      final s = HistorySummary.from(
        logs: [_log('2026-08-01', 900)],
        windowDays: 7,
        calorieTarget: 2000,
      );
      expect(s.daysOnTarget, 0);
    });

    test('inside the band counts', () {
      final s = HistorySummary.from(
        logs: [_log('2026-08-01', 1950)],
        windowDays: 7,
        calorieTarget: 2000,
      );
      expect(s.daysOnTarget, 1);
    });

    test('with no target set, nothing is scored', () {
      final s = HistorySummary.from(
        logs: [_log('2026-08-01', 1950)],
        windowDays: 7,
        calorieTarget: 0,
      );
      expect(s.daysOnTarget, 0);
    });
  });

  group('weight is a trend or it is nothing', () {
    test('one weigh-in yields NO trend', () {
      // One measurement stated as a trend invites a conclusion the data
      // cannot support.
      final s = HistorySummary.from(
        logs: [_log('2026-08-01', 2000)],
        windowDays: 28,
        calorieTarget: 2000,
        weights: [_w('2026-08-01', 84)],
      );
      expect(s.weightChangeKg, isNull);
      expect(s.promptLine, isNot(contains('Weight')));
    });

    test('two weigh-ins give a signed change and a span', () {
      final s = HistorySummary.from(
        logs: [_log('2026-08-01', 2000)],
        windowDays: 28,
        calorieTarget: 2000,
        weights: [_w('2026-08-20', 82.5), _w('2026-08-01', 84.0)],
      );
      expect(s.weightChangeKg, closeTo(-1.5, 0.001));
      expect(s.weightDays, 19);
      expect(s.promptLine, contains('down 1.5kg'));
    });

    test('order of the input does not matter', () {
      final asc = HistorySummary.from(
          logs: [_log('2026-08-01', 2000)],
          windowDays: 28,
          calorieTarget: 2000,
          weights: [_w('2026-08-01', 84), _w('2026-08-20', 82.5)]);
      expect(asc.weightChangeKg, closeTo(-1.5, 0.001));
    });
  });

  test('an empty window says so rather than reporting zeros', () {
    final s = HistorySummary.from(
        logs: const [], windowDays: 28, calorieTarget: 2000);
    expect(s.isEmpty, isTrue);
    expect(s.promptLine, contains('No history logged'));
    expect(s.promptLine, isNot(contains('0 kcal')),
        reason: '"averaging 0 kcal" reads as a finding about the user rather '
            'than an absence of data');
  });

  test('the prompt line states the sample size alongside the average', () {
    final s = HistorySummary.from(
      logs: [_log('2026-08-01', 2000), _log('2026-08-02', 2100, protein: 90)],
      windowDays: 28,
      calorieTarget: 2000,
    );
    expect(s.promptLine, contains('logged on 2 of them'));
    expect(s.promptLine, contains('2050 kcal'));
  });
}
