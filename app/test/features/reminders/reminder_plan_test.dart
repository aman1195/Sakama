import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:sakama/features/reminders/domain/reminder_plan.dart';

/// A notification is an interruption. The tests that matter here are the ones
/// about NOT sending one — a health app that nags is one people silence for the
/// whole category, and there is no coming back from that.
void main() {
  const plan = ReminderPlan();
  final monday = DateTime(2026, 9, 7); // weekday 1
  final sunday = DateTime(2026, 9, 6); // weekday 7

  ReminderSetting mealAt(Meal m, int minute, {bool enabled = true}) =>
      ReminderSetting(
          kind: ReminderKind.meal, enabled: enabled, minuteOfDay: minute, meal: m);

  List<DueReminder> due({
    DateTime? date,
    List<ReminderSetting> settings = const [],
    Set<Meal> logged = const {},
    bool weighed = false,
  }) =>
      plan.due(
        date: date ?? monday,
        settings: settings,
        loggedMeals: logged,
        weighedToday: weighed,
      );

  group('nothing fires unless it was asked for', () {
    test('no settings, no reminders', () {
      expect(due(), isEmpty);
    });

    test('a disabled reminder stays silent', () {
      expect(due(settings: [mealAt(Meal.lunch, 780, enabled: false)]), isEmpty);
    });

    test('a reminder with no time cannot fire', () {
      expect(
          due(settings: const [
            ReminderSetting(
                kind: ReminderKind.meal, enabled: true, meal: Meal.lunch)
          ]),
          isEmpty);
    });
  });

  /// THE RULE THE FEATURE EXISTS FOR.
  group('an already-logged slot is silent', () {
    test('lunch logged means no lunch reminder', () {
      expect(due(settings: [mealAt(Meal.lunch, 780)], logged: {Meal.lunch}),
          isEmpty,
          reason: 'reminding someone to do what they already did is a lie '
              'about their own diary');
    });

    test('but an unlogged slot still fires', () {
      final out = due(settings: [mealAt(Meal.lunch, 780)], logged: {Meal.breakfast});
      expect(out.single.kind, ReminderKind.meal);
      expect(out.single.meal, Meal.lunch);
    });

    test('logging one meal does not silence another', () {
      final out = due(
        settings: [mealAt(Meal.breakfast, 480), mealAt(Meal.dinner, 1200)],
        logged: {Meal.breakfast},
      );
      expect(out.map((r) => r.meal), [Meal.dinner]);
    });

    test('a weigh-in already done today is silent', () {
      expect(
          due(
              settings: const [
                ReminderSetting(
                    kind: ReminderKind.weighIn, enabled: true, minuteOfDay: 420)
              ],
              weighed: true),
          isEmpty);
    });
  });

  group('weekly reminders respect the day', () {
    test('a Sunday digest does not fire on Monday', () {
      expect(
          due(date: monday, settings: const [
            ReminderSetting(
                kind: ReminderKind.weeklyDigest,
                enabled: true,
                minuteOfDay: 1140,
                weekday: 7)
          ]),
          isEmpty);
    });

    test('and does fire on Sunday', () {
      expect(
          due(date: sunday, settings: const [
            ReminderSetting(
                kind: ReminderKind.weeklyDigest,
                enabled: true,
                minuteOfDay: 1140,
                weekday: 7)
          ]).length,
          1);
    });

    test('a weekly weigh-in only fires on its day', () {
      const s = ReminderSetting(
          kind: ReminderKind.weighIn,
          enabled: true,
          minuteOfDay: 420,
          weekday: 1);
      expect(due(date: monday, settings: const [s]).length, 1);
      expect(due(date: sunday, settings: const [s]), isEmpty);
    });
  });

  test('reminders come back in the order the day happens', () {
    final out = due(settings: [
      mealAt(Meal.dinner, 1200),
      mealAt(Meal.breakfast, 480),
      mealAt(Meal.lunch, 780),
    ]);
    expect(out.map((r) => r.minuteOfDay), [480, 780, 1200]);
  });

  group('fasting edges', () {
    test('a user with no fasting plan is never told about a window', () {
      expect(plan.fastingEdges(eatStartMin: null, eatEndMin: null, enabled: true),
          isEmpty);
      expect(
          plan.fastingEdges(eatStartMin: 720, eatEndMin: 1200, enabled: false),
          isEmpty);
    });

    test('the close warning comes BEFORE the window shuts', () {
      final out =
          plan.fastingEdges(eatStartMin: 720, eatEndMin: 1200, enabled: true);
      expect(out.map((r) => r.minuteOfDay), [720, 1170],
          reason: '"you can no longer eat" arrives too late to be a reminder '
              'and lands as a reprimand');
    });

    test('a window too short to warn inside only announces its opening', () {
      final out =
          plan.fastingEdges(eatStartMin: 720, eatEndMin: 735, enabled: true);
      expect(out.map((r) => r.minuteOfDay), [720],
          reason: 'a warning before the window opened would be nonsense');
    });
  });
}
