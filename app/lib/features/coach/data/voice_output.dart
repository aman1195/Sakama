
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

  /// Select the voice to speak with. False when the platform did not take it.
  ///
  /// RETURNS A RESULT because the platform can refuse. Android's `setVoice`
  /// answers 0 with only a debug log when no voice matches on name+locale, and
  /// a `void` here discarded that — leaving us believing a vetted voice was in
  /// force while the engine kept its own.
  Future<bool> useVoice(Map<String, String> voice);

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

    // BEST VOICE FIRST, within each tier. iOS ships a compact default voice
    // and lets the user download "enhanced" and "premium" ones, and the gap
    // between them is most of why synthesized speech sounds cheap. They are
    // all local, so preferring them costs nothing this class is protecting.
    // Android does not report the field; those simply sort equal.
    int rank(Map<String, String> v) => switch (v['quality']) {
          'premium' => 0,
          'enhanced' => 1,
          _ => 2,
        };
    List<Map<String, String>> best(Iterable<Map<String, String>> vs) =>
        vs.toList()..sort((a, b) => rank(a).compareTo(rank(b)));

    final exact =
        best(embedded.where((v) => norm(v['locale']) == norm(preferred)));
    if (exact.isNotEmpty) return exact.first;

    final sameLanguage =
        best(embedded.where((v) => lang(v['locale']) == lang(preferred)));
    if (sameLanguage.isNotEmpty) return sameLanguage.first;
    return best(embedded).first;
  }
}

/// [SpeechSynthesizer] over `flutter_tts` (MIT, rule 4).
///
/// Licence read from the package's own LICENSE rather than the pub.dev badge,
/// and specifically checked for the right to SELL. A permissive-looking grant
/// with that one right removed is the known trap this project has a named
/// entry for in CLAUDE.md rule 4; flutter_tts keeps it.
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
  Future<bool> useVoice(Map<String, String> voice) async =>
      await _tts.setVoice(voice) == 1;

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

  /// The vetted voice, once we have found one.
  ///
  /// The LIST is cached, not the permission. Enumerating voices is a platform
  /// round trip, but "we are allowed to speak" is re-established before every
  /// utterance — see [speak].
  Map<String, String>? _voice;

  Future<SpeakOutcome> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SpeakOutcome.empty;
    try {
      // RE-PINNED EVERY TIME, and the result checked.
      //
      // Resolving this once and caching "yes" was a hole big enough to undo
      // the whole file. Two ways the pin disappears underneath us, both in the
      // plugin's own source:
      //
      //  - the Android plugin RECREATES its TextToSpeech object when the
      //    service connection dies (memory pressure, an engine update, the
      //    user changing engines in Settings). Its re-init restores only the
      //    LANGUAGE, so the vetted voice is gone — and the next utterance
      //    would go out on the engine's default, which for many locales is a
      //    network voice. That is precisely the voice this class exists to
      //    refuse.
      //  - `setVoice` can simply answer 0 when nothing matches, with no
      //    exception. Ignoring that meant believing a pin we never got.
      //
      // A round trip per utterance is nothing next to a health line being
      // synthesized by someone else's server.
      if (!await _pinEmbeddedVoice()) return SpeakOutcome.noOnDeviceVoice;
      await _tts.speak(trimmed);
      return SpeakOutcome.ok;
    } catch (e) {
      debugPrint('voice output: $e');
      return SpeakOutcome.failed;
    }
  }

  /// Stop immediately. This is barge-in: the user talking over Vita, or
  /// leaving the screen, must silence it at once.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('voice output stop: $e');
    }
  }

  /// Ensure an on-device voice is selected RIGHT NOW. False means stay silent.
  Future<bool> _pinEmbeddedVoice() async {
    // A failed enumeration is NOT remembered. Caching the failure turned one
    // transient null from the platform into permanent silence for the rest of
    // the process, under a message telling the user their phone cannot do it.
    _voice ??= EmbeddedVoicePolicy(isAndroid: _isAndroid)
        .choose(await _tts.voices());
    final choice = _voice;
    if (choice == null) return false;

    if (await _tts.useVoice(choice)) return true;
    // The platform did not take it. The voice we vetted may have been
    // uninstalled; drop it so the next attempt looks again rather than
    // retrying a name that no longer exists.
    _voice = null;
    return false;
  }
}
