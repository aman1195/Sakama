import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/home/domain/day_totals.dart';
import 'package:sakama/features/reminders/data/reminder_scheduler.dart';
import 'package:sakama/features/reminders/data/reminder_store.dart';
import 'package:sakama/features/reminders/data/reminder_sync.dart';
import 'package:sakama/features/reminders/domain/reminder_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements ReminderScheduler {
  bool granted = true;
  int cancels = 0;
  List<ScheduledReminder>? last;
  Object? failWith;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    if (failWith != null) throw failWith!;
    last = reminders;
  }

  @override
  Future<void> cancelAll() async => cancels++;
}

void main() {
  late ReminderStore store;
  late _FakeScheduler scheduler;
  late ReminderSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ReminderStore(prefs: await SharedPreferences.getInstance());
    scheduler = _FakeScheduler();
    sync = ReminderSync(
        store: store,
        scheduler: scheduler,
        now: () => DateTime(2026, 9, 7)); // a Monday
  });

  test('nothing asked for means nothing scheduled', () async {
    await sync.reschedule();
    expect(scheduler.last, isNull);
    expect(scheduler.cancels, 1, reason: 'and anything stale is cleared');
  });

  test('an enabled reminder reaches the platform', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.meal,
          enabled: true,
          minuteOfDay: 780,
          meal: Meal.lunch)
    ]);
    await sync.reschedule();

    expect(scheduler.last!.single.minuteOfDay, 780);
    expect(scheduler.last!.single.title, 'Log your lunch');
  });

  test('turning the last one off cancels rather than scheduling nothing',
      () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.meal,
          enabled: false,
          minuteOfDay: 780,
          meal: Meal.lunch)
    ]);
    await sync.reschedule();
    expect(scheduler.last, isNull);
    expect(scheduler.cancels, greaterThan(0));
  });

  /// The subtle one. Suppression happens when a reminder FIRES, not when it is
  /// scheduled — a notification set for 09:00 tomorrow cannot know whether
  /// breakfast will be logged by then.
  test('scheduling does not silence tomorrow using today\'s diary', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.meal,
          enabled: true,
          minuteOfDay: 540,
          meal: Meal.breakfast)
    ]);
    await sync.reschedule();

    expect(scheduler.last!.length, 1,
        reason: 'today being logged must not cancel tomorrow');
  });

  test('a scheduler that throws does not break the caller', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.weighIn, enabled: true, minuteOfDay: 420)
    ]);
    scheduler.failWith = Exception('platform said no');

    await sync.reschedule(); // must not throw
  });

  test('clear turns everything off AND cancels it', () async {
    await store.save(const [
      ReminderSetting(
          kind: ReminderKind.meal,
          enabled: true,
          minuteOfDay: 780,
          meal: Meal.lunch)
    ]);
    await sync.clear();

    expect(await store.load(), isEmpty);
    expect(scheduler.cancels, greaterThan(0));
  });
}
