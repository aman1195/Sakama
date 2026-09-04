import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

/// One scheduled reminder, ready for the platform.
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final int minuteOfDay;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.minuteOfDay == minuteOfDay &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, minuteOfDay, title, body);
}

/// The narrow slice of notification scheduling this app needs.
///
/// Ours, not the plugin's, so the decisions above it are testable without a
/// notification permission or a platform channel — the same shape as
/// [SpeechEngine] and [PhotoStorage].
abstract class ReminderScheduler {
  /// Ask for permission. False means the user said no, and nothing should be
  /// scheduled or retried until they ask for it themselves.
  Future<bool> requestPermission();

  /// Replace everything currently scheduled with [reminders].
  Future<void> replaceAll(List<ScheduledReminder> reminders);

  /// Remove everything. Used when the user turns reminders off, and on an
  /// identity change — the next person must not inherit someone else's day.
  Future<void> cancelAll();
}

/// Turns a decided reminder into the words a person reads on a lock screen.
///
/// TEMPLATE TEXT, NEVER AN AI CALL. The system design is explicit that a
/// notification must not spend the user's AI budget: nobody asked for this
/// interruption, and paying a model to phrase it would be charging them for
/// the privilege. A cached phrase can replace these later; a generation on the
/// notification path cannot.
///
/// The copy states a fact and offers an action. It never scolds — the diary
/// belongs to the user, and a reminder that reads as disappointment is one
/// they will switch off rather than obey.
String reminderTitle(DueReminder r) => switch (r.kind) {
      ReminderKind.meal => r.meal == null
          ? 'Time to log'
          : 'Log your ${r.meal!.label.toLowerCase()}',
      ReminderKind.weighIn => 'Weigh-in day',
      ReminderKind.fastingEdge => 'Your eating window',
      ReminderKind.morningNudge => 'Good morning',
      ReminderKind.weeklyDigest => 'Your week',
    };

String reminderBody(DueReminder r) => switch (r.kind) {
      ReminderKind.meal => 'Takes about five seconds.',
      ReminderKind.weighIn => 'One number, whenever suits you.',
      ReminderKind.fastingEdge => 'Check where you are in it.',
      ReminderKind.morningNudge => 'Here is where yesterday landed.',
      ReminderKind.weeklyDigest => 'Seven days, in one screen.',
    };

/// A STABLE id per reminder, so re-scheduling replaces rather than duplicates.
///
/// Derived from what the reminder IS, not from when it was created: two runs
/// of the scheduler must produce the same id for the same reminder, or every
/// app launch adds another copy of breakfast.
int reminderId(DueReminder r) =>
    Object.hash(r.kind, r.meal, r.minuteOfDay) & 0x7fffffff;

/// Build the platform payload for a day's decided reminders.
///
/// Pure, so the mapping from decision to notification is testable on its own.
List<ScheduledReminder> toScheduled(List<DueReminder> due) => [
      for (final r in due)
        ScheduledReminder(
          id: reminderId(r),
          minuteOfDay: r.minuteOfDay,
          title: reminderTitle(r),
          body: reminderBody(r),
        )
    ];

/// [ReminderScheduler] over `flutter_local_notifications` (BSD-3, rule 4 —
/// read from the package's own LICENSE, not the GitHub API, which reports none
/// because the file sits in a subdirectory of the monorepo).
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channelId = 'sakama_reminders';

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
        settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // NOT requested at init. Permission is asked for when the user turns a
      // reminder on, not when the app starts — a permission prompt on first
      // launch, before anyone has asked for anything, is how an app gets
      // denied once and forever.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('reminders: permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    await _init();
    // WHOLESALE, not a diff. The set is small, the schedule is derived from
    // settings that just changed, and a diff that gets one case wrong leaves a
    // reminder firing that the user believes they turned off.
    await cancelAll();
    for (final r in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: _nextOccurrence(r.minuteOfDay),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(_channelId, 'Reminders',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          // Repeat daily at this time. Without it a reminder fires once and
          // the user quietly stops being reminded.
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        // One reminder the platform refuses must not cost the others.
        debugPrint('reminders: could not schedule ${r.id}: $e');
      }
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('reminders: cancelAll failed: $e');
    }
  }

  /// The next time this reminder is due, in the DEVICE's timezone.
  ///
  /// Always in the future: a time already past today means tomorrow. Scheduling
  /// into the past either fires immediately — a notification at a moment the
  /// user did not choose — or is silently dropped.
  static tz.TZDateTime _nextOccurrence(int minuteOfDay, {tz.TZDateTime? now}) {
    final n = now ?? tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
        tz.local, n.year, n.month, n.day, minuteOfDay ~/ 60, minuteOfDay % 60);
    if (!when.isAfter(n)) when = when.add(const Duration(days: 1));
    return when;
  }

  @visibleForTesting
  static tz.TZDateTime nextOccurrenceFor(int minuteOfDay, tz.TZDateTime now) =>
      _nextOccurrence(minuteOfDay, now: now);
}
