import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaking Vita's replies (A5, voice-first).
///
/// ON-DEVICE OR NOT AT ALL — the same rule [VoiceInput] holds for dictation,
/// for the same reason. A reply is health data: "you're 690 kcal short and
/// your fasting window closed an hour ago", or a line about a medication. ADR
/// 0016 decision 1 keeps these conversations on the phone at rest, and there
/// is no version of that promise where the app reads them aloud through
/// someone else's server.
///
/// THE PLUGIN DOES NOT GIVE THAT BY DEFAULT (verified against flutter_tts
/// 4.2.5 source, 2026-09-01). `speak()` hands the text to the platform engine
/// with whatever voice is currently selected, and nothing in that path looks
/// at whether the voice is a network one. The Android check that DOES exist
/// (`isNetworkConnectionRequired`, FlutterTtsPlugin.kt:484) is inside
/// `isLanguageInstalled`, a query helper the speak path never calls.
///
/// The two platforms differ, and unlike dictation this one can be settled from
/// Dart:
///
///  - **iOS**: every `AVSpeechSynthesisVoice` is synthesized on-device, so the
///    promise holds by construction. `getVoices` returns no `network_required`
///    key at all (SwiftFlutterTtsPlugin.swift:337-350) — there is nothing to
///    report, not a missing answer.
///  - **Android**: `getVoices` always reports `network_required` as "1" or "0"
///    (FlutterTtsPlugin.kt:623), and the system engine may well pick a network
///    voice on its own. So we choose an embedded voice explicitly and refuse
///    to speak when there is not one.
///
/// A MISSING KEY ON ANDROID IS A REFUSAL, not a pass. Treating absence as
/// "fine" is how the fail-open bugs in this codebase have all looked, and here
/// it would ship health text to Google on some future platform version that
/// stops reporting the field.

/// The slice of speech synthesis this app needs.
///
/// Ours, not the plugin's, so the tests can assert what we asked the platform
/// for — which is the only thing between a health disclosure and a server.
abstract class SpeechSynthesizer {
  /// Voices the platform offers, as raw maps from the plugin.
  Future<List<Map<String, String>>> voices();

  /// Select the voice to speak with.
  Future<void> useVoice(Map<String, String> voice);

  Future<void> speak(String text);
  Future<void> stop();
}

/// How an attempt to speak finished, so the UI can say something true.
enum SpeakOutcome {
  /// Spoken on-device.
  ok,

  /// This device has no on-device voice for any language we can use, so we
  /// stayed silent rather than reading health data to a server.
  noOnDeviceVoice,

  /// The platform or plugin failed.
  failed,

  /// Nothing to say.
  empty,
}

/// Picks a voice that cannot send text off the device.
///
/// Pure, so the rule that protects the health data is testable without a
/// platform. Everything about the ordering below is a preference; the
/// network filter is not.
class EmbeddedVoicePolicy {
  const EmbeddedVoicePolicy({required this.isAndroid});
  final bool isAndroid;

  /// True when this voice is guaranteed not to leave the device.
  bool isEmbedded(Map<String, String> voice) {
    final flag = voice['network_required'];
    if (!isAndroid) {
      // iOS does not report the field because every voice it offers is local.
      return true;
    }
    // Android always reports it. Absent means we cannot tell, and we do not
    // guess in the direction that uploads.
    return flag == '0';
  }

  /// The best embedded voice for [preferred], or null when there is none.
  ///
  /// Prefers an exact locale (en-IN), then the same language in any region
  /// (en-GB, en-US), then any embedded voice at all — a voice with the wrong
  /// accent still says the number correctly, and silence does not.
  Map<String, String>? choose(
    List<Map<String, String>> voices, {
    String preferred = 'en-IN',
  }) {
    final embedded = voices.where(isEmbedded).toList();
    if (embedded.isEmpty) return null;

    String lang(String? locale) =>
        (locale ?? '').replaceAll('_', '-').split('-').first.toLowerCase();
    String norm(String? locale) =>
        (locale ?? '').replaceAll('_', '-').toLowerCase();

    final exact = embedded
        .where((v) => norm(v['locale']) == norm(preferred))
        .firstOrNull;
    if (exact != null) return exact;

    final sameLanguage = embedded
        .where((v) => lang(v['locale']) == lang(preferred))
        .firstOrNull;
    return sameLanguage ?? embedded.first;
  }
}

/// [SpeechSynthesizer] over `flutter_tts` (MIT, rule 4 — verified from the
/// package's own LICENSE, including that the grant still carries "sell", which
/// is the clause Best-Flutter-UI-Templates deletes).
class PluginSpeechSynthesizer implements SpeechSynthesizer {
  PluginSpeechSynthesizer({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  @override
  Future<List<Map<String, String>>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry('$k', '$v')))
        .toList();
  }

  @override
  Future<void> useVoice(Map<String, String> voice) => _tts.setVoice(voice);

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

/// Speaks Vita's replies, on-device or not at all.
class VoiceOutput {
  VoiceOutput({
    SpeechSynthesizer? synthesizer,
    bool? isAndroidOverride,
  })  : _tts = synthesizer ?? PluginSpeechSynthesizer(),
        _isAndroid = isAndroidOverride ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final SpeechSynthesizer _tts;
  final bool _isAndroid;

  /// Resolved once, then reused: enumerating voices is a platform round trip
  /// and the answer does not change while the app is running.
  bool _resolved = false;
  bool _haveEmbeddedVoice = false;

  /// True once we have spoken and not yet stopped. Barge-in reads this.
  bool get isSpeaking => _speaking;
  bool _speaking = false;

  Future<SpeakOutcome> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SpeakOutcome.empty;
    try {
      if (!await _ensureEmbeddedVoice()) return SpeakOutcome.noOnDeviceVoice;
      _speaking = true;
      await _tts.speak(trimmed);
      return SpeakOutcome.ok;
    } catch (e) {
      _speaking = false;
      debugPrint('voice output: $e');
      return SpeakOutcome.failed;
    }
  }

  /// Stop immediately. This is barge-in: the user talking over Vita, or
  /// leaving the screen, must silence it at once.
  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('voice output stop: $e');
    }
  }

  Future<bool> _ensureEmbeddedVoice() async {
    if (_resolved) return _haveEmbeddedVoice;
    _resolved = true;
    final policy = EmbeddedVoicePolicy(isAndroid: _isAndroid);
    final choice = policy.choose(await _tts.voices());
    if (choice == null) {
      _haveEmbeddedVoice = false;
      return false;
    }
    // Set it explicitly even on iOS: the engine's current voice is not
    // necessarily the one we vetted.
    await _tts.useVoice(choice);
    _haveEmbeddedVoice = true;
    return true;
  }
}

/// Whether this build is running on Android, for callers that need it outside
/// a widget. Kept next to the policy it feeds so the two cannot disagree.
bool get isAndroidPlatform =>
    !kIsWeb && Platform.isAndroid;
