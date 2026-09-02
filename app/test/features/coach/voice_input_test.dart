import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/data/voice_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what was asked of the platform. The point of these tests is not
/// that dictation returns words — it is that we never ask for recognition
/// that would ship a user's health disclosure to someone else's server.
class _FakeEngine implements SpeechEngine {
  _FakeEngine({this.starts = true, this.words = 'two rotis and dal', this.throwOn});

  final bool starts;
  final String words;
  final Object? throwOn;
  bool started = false;
  Duration? capturedLimit;

  @override
  bool get isListening => false;

  Duration? seenPause;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    required Duration limit,
    Duration pauseFor = VoiceInput.dictationPause,
  }) async {
    seenPause = pauseFor;
    if (throwOn != null) throw throwOn!;
    capturedLimit = limit;
    if (!starts) return false;
    started = true;
    onResult(words, false); // a partial, then the final
    onResult(words, true);
    return true;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('the real engine asks for ON-DEVICE recognition — the whole promise',
      () {
    // Decision 12 says "no audio egress". The plugin defaults onDevice to
    // FALSE on both platforms, so this one flag is the difference between
    // local dictation and uploading whatever a user said about their health.
    // Asserted against the SOURCE because the flag is inside a plugin call
    // that a unit test cannot reach.
    final src = File('lib/features/coach/data/voice_input.dart').readAsStringSync();
    expect(src, contains('onDevice: true'));
    expect(src.indexOf('onDevice: true') > 0, isTrue);
    // And it must never be paired with a fallback that drops the flag.
    expect(src.contains('onDevice: false'), isFalse,
        reason: 'a retry without the flag would defeat the entire design');
  });

  test('a transcript reaches the caller, trimmed', () async {
    final r = await VoiceInput(
            engine: _FakeEngine(words: '  paneer bhurji  '),
            isAndroidOverride: false)
        .listenOnce();
    expect(r.outcome, VoiceOutcome.ok);
    expect(r.text, 'paneer bhurji');
  });

  test('partials stream so the composer fills in as you speak', () async {
    final seen = <String>[];
    await VoiceInput(engine: _FakeEngine(), isAndroidOverride: false)
        .listenOnce(onPartial: seen.add);
    expect(seen, isNotEmpty,
        reason: 'dictation showing nothing for six seconds feels broken');
  });

  test('an unsupported on-device platform is reported, not worked around',
      () async {
    // iOS raises onDeviceError when the device cannot recognise locally. That
    // is the platform refusing to leak audio, so it gets its own outcome.
    final r = await VoiceInput(
            engine: _FakeEngine(
                throwOn: Exception('onDeviceError: not supported on this device')),
            isAndroidOverride: false)
        .listenOnce();
    expect(r.outcome, VoiceOutcome.noOnDevice);
    expect(r.text, isEmpty);
  });

  test('a refused permission is distinguishable from a failure', () async {
    final r = await VoiceInput(
            engine: _FakeEngine(starts: false), isAndroidOverride: false)
        .listenOnce();
    expect(r.outcome, VoiceOutcome.denied);
  });

  test('an unrelated failure is not mistaken for a privacy refusal', () async {
    final r = await VoiceInput(
            engine: _FakeEngine(throwOn: Exception('audio session busy')),
            isAndroidOverride: false)
        .listenOnce();
    expect(r.outcome, VoiceOutcome.failed);
  });

  test('silence returns empty, not a bogus transcript', () async {
    final r = await VoiceInput(
            engine: _FakeEngine(words: '   '), isAndroidOverride: false)
        .listenOnce();
    expect(r.outcome, VoiceOutcome.empty);
  });

  group('the Android disclosure is genuinely one-time', () {
    // Review of #120: the first version claimed "one-time" in three comments
    // while re-prompting on every dictation. Nagging is not consent.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('asked before the first use, never again after acknowledging',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final v = VoiceInput(
          engine: _FakeEngine(), isAndroidOverride: true, prefs: prefs);

      expect(await v.needsNetworkDisclosure(), isTrue);
      await v.rememberNetworkDisclosure();
      expect(await v.needsNetworkDisclosure(), isFalse);

      // And it survives a fresh instance — the point of persisting it.
      final again = VoiceInput(
          engine: _FakeEngine(), isAndroidOverride: true, prefs: prefs);
      expect(await again.needsNetworkDisclosure(), isFalse);
    });

    test('iOS is never asked, and acknowledging is a no-op there', () async {
      final prefs = await SharedPreferences.getInstance();
      final v = VoiceInput(
          engine: _FakeEngine(), isAndroidOverride: false, prefs: prefs);
      expect(await v.needsNetworkDisclosure(), isFalse);
      await v.rememberNetworkDisclosure();
      expect(prefs.getBool('voice_android_network_ack'), isNull,
          reason: 'nothing to remember on a platform that refuses instead');
    });
  });

  group('the Android/iOS asymmetry is surfaced, not hidden', () {
    // Verified against speech_to_text 7.3.0 source (2026-08-25): iOS errors
    // when on-device is unavailable; Android SILENTLY builds a network
    // recogniser instead. We cannot detect that from Dart, so we tell people.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Android needs the network disclosure', () async {
      expect(
          await VoiceInput(engine: _FakeEngine(), isAndroidOverride: true)
              .needsNetworkDisclosure(),
          isTrue);
    });

    test('iOS does not — it refuses instead of falling back', () async {
      expect(
          await VoiceInput(engine: _FakeEngine(), isAndroidOverride: false)
              .needsNetworkDisclosure(),
          isFalse);
    });
  });

  /// THE HOP NOTHING TESTED. Review reverted the line that carries `pauseFor`
  /// into the plugin and the entire suite stayed green, because no test ever
  /// constructed PluginSpeechEngine. Two promises cross here.
  group('the options handed to the platform', () {
    test('audio stays on the device', () {
      // The plugin defaults onDevice to FALSE, which ships audio to Apple or
      // Google. This is the single line standing between a health disclosure
      // and someone else's server.
      final o = PluginSpeechEngine.optionsFor(
          limit: const Duration(seconds: 30),
          pauseFor: VoiceInput.conversationPause);
      expect(o.onDevice, isTrue);
    });

    test('the chosen pause is the one that reaches the plugin', () {
      // Not a constant: whatever the caller picked per turn.
      for (final p in [
        VoiceInput.conversationPause,
        VoiceInput.dictationPause,
        const Duration(milliseconds: 900),
      ]) {
        expect(
            PluginSpeechEngine.optionsFor(
                    limit: const Duration(seconds: 30), pauseFor: p)
                .pauseFor,
            p);
      }
    });

    test('partial results are on, or the transcript shows nothing live', () {
      final o = PluginSpeechEngine.optionsFor(
          limit: const Duration(seconds: 30), pauseFor: VoiceInput.dictationPause);
      expect(o.partialResults, isTrue);
      expect(o.listenFor, const Duration(seconds: 30));
    });
  });
}
