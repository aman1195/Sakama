import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user has consented to Sakama's AI features sending their logged
/// data off-device to the AI provider (#60). A device-local preference, not a
/// synced setting — consent is given on this phone, in this install.
///
/// Tri-state, deliberately:
///   * `null`  — never asked. The first AI action shows the disclosure sheet.
///   * `true`  — consented. AI features run.
///   * `false` — explicitly off (declined in settings). AI features are gated
///               with a pointer back to the toggle.
///
/// One flag covers both the first-use consent gate AND the "turn AI off"
/// switch: the settings toggle just writes true/false, and the gate fires only
/// while the value is still null.
class AiConsentStore {
  AiConsentStore({SharedPreferences? prefs}) : _injected = prefs;
  final SharedPreferences? _injected;

  static const _key = 'ai_data_enabled';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<bool?> read() async {
    final p = await _prefs;
    return p.containsKey(_key) ? p.getBool(_key) : null;
  }

  Future<void> write(bool enabled) async {
    final p = await _prefs;
    await p.setBool(_key, enabled);
  }
}
