import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:sakama/features/reminders/data/reminder_store.dart';
import 'package:sakama/features/reminders/domain/reminder_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The riskiest thing a settings store can do here is invent consent. Every
/// unknown must read as "they did not ask for this".
void main() {
  late SharedPreferences prefs;
  late ReminderStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = ReminderStore(prefs: prefs);
  });

  test('a fresh install notifies nobody', () async {
    expect(await store.load(), isEmpty);
  });

  test('what was saved comes back', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.meal,
          enabled: true,
          minuteOfDay: 780,
          meal: Meal.lunch),
    ]);
    final back = (await store.load()).single;
    expect(back.kind, ReminderKind.meal);
    expect(back.enabled, isTrue);
    expect(back.minuteOfDay, 780);
    expect(back.meal, Meal.lunch);
  });

  test('turning one off persists as off, not as absent', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.weighIn, enabled: false, minuteOfDay: 420)
    ]);
    expect((await store.load()).single.enabled, isFalse);
  });

  group('unknowns read as silence, never as consent', () {
    test('a corrupt value is not guessed at', () async {
      await prefs.setString('reminders_v1', 'not json');
      expect(await store.load(), isEmpty);
    });

    test('a value that is not a list is not guessed at', () async {
      await prefs.setString('reminders_v1', '{"kind":"meal"}');
      expect(await store.load(), isEmpty);
    });

    test('a kind this build does not know is dropped', () async {
      // Written by a newer build. Scheduling something we do not understand is
      // worse than not scheduling it.
      await prefs.setString('reminders_v1',
          '[{"kind":"hydration","enabled":true,"minute":600}]');
      expect(await store.load(), isEmpty);
    });

    test('an impossible time cannot fire', () async {
      await prefs.setString('reminders_v1',
          '[{"kind":"weighIn","enabled":true,"minute":9999}]');
      expect((await store.load()).single.minuteOfDay, isNull,
          reason: 'a null time is skipped by the plan, which is the point');
    });

    test('a missing enabled flag is off', () async {
      await prefs.setString(
          'reminders_v1', '[{"kind":"weighIn","minute":420}]');
      expect((await store.load()).single.enabled, isFalse);
    });
  });

  group('the suggestions the settings screen starts from', () {
    test('every one is OFF', () async {
      // These are suggestions of WHEN, not a decision to notify.
      expect(ReminderStore.suggested.every((s) => !s.enabled), isTrue);
    });

    test('and they still produce nothing until someone opts in', () {
      const plan = ReminderPlan();
      expect(
          plan.due(
            date: DateTime(2026, 9, 7),
            settings: ReminderStore.suggested,
            loggedMeals: const {},
            weighedToday: false,
          ),
          isEmpty);
    });

    test('the times are plausible for someone in India', () {
      // Dinner at 21:00, not 18:00 — the default that is wrong for the whole
      // market is the one nobody edits, they just turn the feature off.
      final dinner =
          ReminderStore.suggested.firstWhere((s) => s.meal == Meal.dinner);
      expect(dinner.minuteOfDay, 21 * 60);
    });
  });
}
