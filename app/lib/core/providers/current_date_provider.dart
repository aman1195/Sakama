import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local date-only (midnight) of [t].
DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// The next local midnight strictly after [t].
DateTime nextMidnightAfter(DateTime t) => DateTime(t.year, t.month, t.day + 1);

/// Today's local date, kept fresh across the midnight rollover. Date-sensitive
/// providers (the active plan's day type, today's logs) watch this so the app
/// rolls into the new day without a restart (review #70 low note).
///
/// Intentionally a plain [Notifier] — it only holds the value and exposes
/// [CurrentDateNotifier.refresh]. The *when* to roll over (a midnight timer plus
/// app-resume) is driven by `DateRolloverObserver`, so no timer or widget
/// binding lives here and the provider is safe to build in any unit test.
final currentDateProvider =
    NotifierProvider<CurrentDateNotifier, DateTime>(CurrentDateNotifier.new);

class CurrentDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  /// Recompute today's date; a no-op (no rebuild of watchers) when unchanged.
  void refresh() {
    final today = dateOnly(DateTime.now());
    if (today != state) state = today;
  }
}
