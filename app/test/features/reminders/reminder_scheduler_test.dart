import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:sakama/features/reminders/data/reminder_scheduler.dart';
import 'package:sakama/features/reminders/domain/reminder_plan.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The decision layer says WHETHER to interrupt someone. This layer decides
/// what they read and when it lands — both are ways to get it wrong after the
/// hard part was right.
void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  });

  DueReminder meal(Meal m, int minute) =>
      DueReminder(kind: ReminderKind.meal, minuteOfDay: minute, meal: m);

  group('ids are stable, or every launch adds another breakfast', () {
    test('the same reminder produces the same id twice', () {
      expect(reminderId(meal(Meal.breakfast, 480)),
          reminderId(meal(Meal.breakfast, 480)));
    });

    test('different reminders do not collide', () {
      final ids = {
        reminderId(meal(Meal.breakfast, 480)),
        reminderId(meal(Meal.lunch, 480)),
        reminderId(meal(Meal.breakfast, 540)),
        reminderId(const DueReminder(
            kind: ReminderKind.weighIn, minuteOfDay: 480)),
      };
      expect(ids.length, 4);
    });

    test('an id is a valid notification id', () {
      // Android ids are 32-bit signed; a negative or oversized one is silently
      // dropped by the platform.
      expect(reminderId(meal(Meal.dinner, 1200)), greaterThanOrEqualTo(0));
      expect(reminderId(meal(Meal.dinner, 1200)), lessThan(0x80000000));
    });
  });

  group('the words on the lock screen', () {
    test('a meal reminder names the meal', () {
      expect(reminderTitle(meal(Meal.lunch, 780)), 'Log your lunch');
    });

    test('nothing scolds', () {
      // A reminder that reads as disappointment is one people switch off
      // rather than obey. The diary belongs to the user.
      const forbidden = [
        'missed', 'failed', 'forgot', 'behind', 'should have', "haven't"
      ];
      for (final k in ReminderKind.values) {
        final r = DueReminder(
            kind: k, minuteOfDay: 600, meal: k == ReminderKind.meal ? Meal.lunch : null);
        final text = '${reminderTitle(r)} ${reminderBody(r)}'.toLowerCase();
        for (final word in forbidden) {
          expect(text.contains(word), isFalse,
              reason: '"$word" in ${k.name}: "$text"');
        }
      }
    });

    test('every kind has copy — none falls through to a blank', () {
      for (final k in ReminderKind.values) {
        final r = DueReminder(kind: k, minuteOfDay: 600, meal: Meal.lunch);
        expect(reminderTitle(r).trim(), isNotEmpty);
        expect(reminderBody(r).trim(), isNotEmpty);
      }
    });
  });

  test('a decided reminder becomes a schedulable one', () {
    final out = toScheduled([meal(Meal.lunch, 780)]);
    expect(out.single.minuteOfDay, 780);
    expect(out.single.title, 'Log your lunch');
    expect(out.single.id, reminderId(meal(Meal.lunch, 780)));
  });

  /// Scheduling into the past either fires immediately — a notification at a
  /// moment the user did not choose — or is silently dropped.
  group('when it lands', () {
    tz.TZDateTime at(int h, int m) =>
        tz.TZDateTime(tz.local, 2026, 9, 4, h, m);

    test('a time later today is today', () {
      final when = LocalNotificationScheduler.nextOccurrenceFor(780, at(9, 0));
      expect(when.day, 4);
      expect(when.hour, 13);
    });

    test('a time already past is tomorrow, never now', () {
      final now = at(14, 0);
      final when = LocalNotificationScheduler.nextOccurrenceFor(780, now);
      expect(when.day, 5);
      expect(when.isAfter(now), isTrue);
    });

    test('the exact current minute counts as past', () {
      // Firing "now" for a time the user set for 13:00 tomorrow is worse than
      // waiting a day.
      final now = at(13, 0);
      final when = LocalNotificationScheduler.nextOccurrenceFor(780, now);
      expect(when.day, 5);
    });

    test('it is the DEVICE timezone, not UTC', () {
      final when = LocalNotificationScheduler.nextOccurrenceFor(480, at(6, 0));
      expect(when.location.name, 'Asia/Kolkata',
          reason: 'computing this anywhere else fires 08:00 IST at the wrong '
              'hour — the reason the engine lives on the device');
    });
  });
}
