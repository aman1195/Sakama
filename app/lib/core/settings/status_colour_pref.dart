import 'package:shared_preferences/shared_preferences.dart';

/// Whether the day's hero card is filled by status colour.
///
/// WHY THIS EXISTS. PRODUCT.md principle 5 was revised on 2026-08-26 so the
/// surface carries the state — lime within target, warm red past it. That is
/// the default and it is deliberate.
///
/// But colour is judgement even when the words are neutral: a red card on an
/// "over" day says "bad" before anything is read, and in a nutrition app that
/// lands on somebody's body rather than their bank balance. The guardrails
/// (empty is neutral, over begins past target, warm not alarm, copy stays
/// factual) reduce that; they cannot remove it.
///
/// So this is the valve for the users PRODUCT.md's guilt-driven-fitness
/// anti-reference was written to protect. ON by default — the fintech
/// treatment is the intended experience — and one switch away for anyone who
/// does not want their day graded in colour.
class StatusColourPref {
  StatusColourPref({SharedPreferences? prefs}) : _injected = prefs;
  final SharedPreferences? _injected;

  static const _key = 'status_colour_enabled';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// Defaults to TRUE: absence of a preference means the default experience,
  /// not the muted one.
  Future<bool> enabled() async => (await _prefs).getBool(_key) ?? true;

  /// The same read, without an await.
  ///
  /// Required so the hero card is painted correctly on the FIRST frame.
  /// Resolving it asynchronously showed an opted-out user their day graded in
  /// colour for a frame before snapping to neutral — a flash of precisely the
  /// thing they turned off.
  ///
  /// With no injected instance (widget tests) this returns the default rather
  /// than throwing: the caller wants a display preference, not a crash, and
  /// the default is what an unset preference means anyway.
  bool enabledSync() => _injected?.getBool(_key) ?? true;

  Future<void> set(bool value) async => (await _prefs).setBool(_key, value);
}
