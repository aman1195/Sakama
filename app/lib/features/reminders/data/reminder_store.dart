import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/day_totals.dart';
import '../domain/reminder_plan.dart';

/// What the user has asked to be reminded about.
///
/// SharedPreferences, not the synced database, and deliberately: a reminder
/// time is a property of THIS phone. A tablet in another timezone should not
/// inherit 08:00 from a handset, and a notification schedule is not health
/// data worth carrying across devices.
///
/// DEFAULTS TO NOTHING. `load()` on a fresh install returns an empty list, so
/// the app never notifies anyone who has not asked. Every read path treats a
/// missing or unreadable value as "no reminders" rather than guessing.
class ReminderStore {
  ReminderStore({SharedPreferences? prefs})
      : _prefs = prefs; // ignore: prefer_initializing_formals
  final SharedPreferences? _prefs;

  static const _key = 'reminders_v1';

  Future<SharedPreferences> get _p async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<List<ReminderSetting>> load() async {
    try {
      final raw = (await _p).getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(_fromJson).whereType<ReminderSetting>().toList();
    } catch (e) {
      // A corrupt preference must not stop the app, and must not be guessed
      // at: silence is the safe reading of "we do not know what you wanted".
      debugPrint('reminders: could not read settings: $e');
      return const [];
    }
  }

  Future<void> save(List<ReminderSetting> settings) async {
    try {
      await (await _p).setString(
          _key, jsonEncode(settings.map(_toJson).toList()));
    } catch (e) {
      debugPrint('reminders: could not save settings: $e');
    }
  }

  static Map<String, dynamic> _toJson(ReminderSetting s) => {
        'kind': s.kind.name,
        'enabled': s.enabled,
        'minute': s.minuteOfDay,
        'meal': s.meal?.key,
        'weekday': s.weekday,
      };

  /// Tolerant on the way in. An unknown kind or meal is a setting written by a
  /// newer build; dropping it silently is right, because the alternative is
  /// scheduling something this build does not understand.
  static ReminderSetting? _fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = ReminderKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    if (kind == null) return null;
    final minute = j['minute'];
    return ReminderSetting(
      kind: kind,
      enabled: j['enabled'] == true,
      minuteOfDay: minute is int && minute >= 0 && minute < 1440 ? minute : null,
      meal: Meal.values.where((m) => m.key == j['meal']).firstOrNull,
      weekday: j['weekday'] is int ? j['weekday'] as int : null,
    );
  }

  /// What the settings screen offers before anyone has chosen anything.
  ///
  /// ALL DISABLED. These are suggestions of WHEN, not a decision to notify —
  /// the screen shows sensible times already filled in so turning one on is a
  /// single tap, and nothing fires until someone does.
  static List<ReminderSetting> get suggested => const [
        ReminderSetting(
            kind: ReminderKind.meal,
            enabled: false,
            minuteOfDay: 9 * 60,
            meal: Meal.breakfast),
        ReminderSetting(
            kind: ReminderKind.meal,
            enabled: false,
            minuteOfDay: 14 * 60,
            meal: Meal.lunch),
        ReminderSetting(
            kind: ReminderKind.meal,
            enabled: false,
            minuteOfDay: 21 * 60,
            meal: Meal.dinner),
        ReminderSetting(
            kind: ReminderKind.weighIn,
            enabled: false,
            minuteOfDay: 7 * 60,
            weekday: DateTime.monday),
        ReminderSetting(
            kind: ReminderKind.weeklyDigest,
            enabled: false,
            minuteOfDay: 19 * 60,
            weekday: DateTime.sunday),
      ];
}
