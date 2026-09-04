import 'package:flutter/foundation.dart';

import '../../home/domain/day_totals.dart';
import '../domain/reminder_plan.dart';
import 'reminder_scheduler.dart';
import 'reminder_store.dart';

/// Keeps the platform's schedule equal to what the user asked for.
///
/// The one place the three halves of A8 meet: the settings say what was asked
/// for, the plan decides what is worth firing, and the scheduler puts it on the
/// device's clock.
///
/// WHOLESALE, EVERY TIME. Rescheduling replaces the lot rather than diffing —
/// the set is a handful of rows, and a diff that gets one case wrong leaves a
/// reminder firing that the user believes they switched off. That is the
/// failure people never forgive.
class ReminderSync {
  ReminderSync({
    required this.store,
    required this.scheduler,
    this.plan = const ReminderPlan(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ReminderStore store;
  final ReminderScheduler scheduler;
  final ReminderPlan plan;
  final DateTime Function() _now;

  /// Rebuild the schedule from what is currently saved.
  ///
  /// Deliberately does NOT consider what has been logged today. Suppression is
  /// a decision made when a reminder FIRES, not when it is scheduled: a
  /// notification set at 09:00 tomorrow cannot know whether breakfast will be
  /// logged by then, and scheduling on today's diary would silence tomorrow.
  Future<void> reschedule() async {
    try {
      final settings = await store.load();
      final due = plan.due(
        date: _now(),
        settings: settings,
        // Nothing is suppressed here — see above.
        loggedMeals: const <Meal>{},
        weighedToday: false,
      );
      if (due.isEmpty) {
        await scheduler.cancelAll();
        return;
      }
      await scheduler.replaceAll(toScheduled(due));
    } catch (e) {
      // Reminders are a convenience. Failing to schedule one must never break
      // the screen the user was on.
      debugPrint('reminders: reschedule failed: $e');
    }
  }

  /// Everything off, everything cancelled.
  ///
  /// For an identity change: the next person on this device must not inherit
  /// someone else's day, and a reminder is a statement about a diary that is
  /// no longer theirs.
  Future<void> clear() async {
    try {
      await store.save(const []);
      await scheduler.cancelAll();
    } catch (e) {
      debugPrint('reminders: clear failed: $e');
    }
  }
}
