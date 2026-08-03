import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/plans/domain/plan.dart';
import 'package:sakama/features/plans/domain/plan_day.dart';
import 'package:sakama/features/plans/domain/plan_log_notice.dart';

PlanDay _day({FastingWindow? window, List<String> blocked = const []}) => PlanDay(
      dayTypeKey: 'reset',
      label: 'Reset',
      targets: const PlanTargets(),
      fastingWindow: window,
      blockedFoods: blocked,
    );

DateTime _at(int h, int m) => DateTime(2026, 8, 3, h, m);

void main() {
  group('PlanLogNotice.forDay (clock-as-argument, deterministic)', () {
    test('no active plan → null', () {
      expect(PlanLogNotice.forDay(null, _at(21, 0)), isNull);
    });

    test('a plan with no window and no blocked foods → null', () {
      expect(PlanLogNotice.forDay(_day(), _at(21, 0)), isNull);
    });

    test('inside the eating window → null (nothing to flag)', () {
      final n = PlanLogNotice.forDay(
          _day(window: const FastingWindow(eatStart: '08:00', eatEnd: '20:00')),
          _at(12, 0));
      expect(n, isNull);
    });

    test('outside the eating window → outsideWindow with bounds', () {
      final n = PlanLogNotice.forDay(
          _day(window: const FastingWindow(eatStart: '08:00', eatEnd: '20:00')),
          _at(21, 30));
      expect(n, isNotNull);
      expect(n!.outsideWindow, isTrue);
      expect(n.windowStart, '08:00');
      expect(n.windowEnd, '20:00');
    });

    test('overnight window (start>end) is handled: 22:00–06:00 at 02:00 is inside',
        () {
      final n = PlanLogNotice.forDay(
          _day(window: const FastingWindow(eatStart: '22:00', eatEnd: '06:00')),
          _at(2, 0));
      expect(n, isNull, reason: '02:00 is within a 22:00–06:00 window');
    });

    test('blocked foods surface even when inside the window', () {
      final n = PlanLogNotice.forDay(
          _day(
              window: const FastingWindow(eatStart: '00:00', eatEnd: '23:59'),
              blocked: ['sugar', 'fried']),
          _at(12, 0));
      expect(n, isNotNull);
      expect(n!.outsideWindow, isFalse);
      expect(n.avoidFoods, ['sugar', 'fried']);
    });

    test('both conditions combine', () {
      final n = PlanLogNotice.forDay(
          _day(
              window: const FastingWindow(eatStart: '08:00', eatEnd: '20:00'),
              blocked: ['sugar']),
          _at(22, 0));
      expect(n!.outsideWindow, isTrue);
      expect(n.avoidFoods, ['sugar']);
      expect(n.isEmpty, isFalse);
    });
  });
}
