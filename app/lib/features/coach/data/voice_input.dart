import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The narrow slice of dictation this app needs.
///
/// Ours, not the plugin's, for the same reason [MemoryExtractor] is an
/// interface: it keeps the swap-in cost low (Apple's Foundation Models, a
/// different plugin) and it lets the tests assert what we ASKED the platform
/// for — which is the only thing standing between a health disclosure and
/// someone else's server.
abstract class SpeechEngine {
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    required Duration limit,
  });
  Future<void> stop();
  bool get isListening;
}

/// [SpeechEngine] over the `speech_to_text` plugin (BSD-3, rule 4).
class PluginSpeechEngine implements SpeechEngine {
  PluginSpeechEngine({SpeechToText? speech}) : _speech = speech ?? SpeechToText();
  final SpeechToText _speech;
  bool _initialised = false;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    required Duration limit,
  }) async {
    if (!_initialised) {
      _initialised = await _speech.initialize(
        onError: (e) => debugPrint('voice error: ${e.errorMsg}'),
      );
      if (!_initialised) return false;
    }
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        // THE point of this class. Never default this to false: the plugin
        // does, and that ships the audio to Apple or Google.
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: limit,
        // People pause mid-sentence when dictating a meal, so this is not as
        // tight as it looks.
        pauseFor: const Duration(seconds: 3),
      ),
    );
    return true;
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }
}

/// How voice input finished, so the UI can say something true.
enum VoiceOutcome {
  /// Text was captured.
  ok,

  /// The user denied microphone or speech-recognition permission.
  denied,

  /// This device cannot recognise speech WITHOUT sending audio away, so we
  /// refused rather than quietly uploading it (see [VoiceInput]).
  noOnDevice,

  /// Nothing was said, or nothing was recognised.
  empty,

  /// Anything else — plugin or platform failure.
  failed,
}

class VoiceResult {
  const VoiceResult(this.outcome, [this.text = '']);
  final VoiceOutcome outcome;
  final String text;
}

/// Dictation for the chat composer (ADR 0016 decision 12).
///
/// ON-DEVICE OR NOT AT ALL. Decision 12 promises "free, offline, no audio
/// egress", and the plugin does NOT give that by default — `onDevice`
/// defaults to false on both platforms, i.e. audio goes to Apple's or
/// Google's servers. Someone dictating "I've been dizzy since starting the
/// diabetes tablets" would be uploading a health disclosure. So this class
/// always asks for on-device.
///
/// THE TWO PLATFORMS DIFFER, and it matters (verified against
/// speech_to_text 7.3.0 source, 2026-08-25):
///
///  - **iOS** fails LOUD. If `supportsOnDeviceRecognition` is false the plugin
///    returns a FlutterError (`onDeviceError`) and no audio is captured. The
///    promise holds by itself.
///  - **Android** fails OPEN. If `isOnDeviceRecognitionAvailable()` is false
///    the plugin silently constructs an ordinary network recogniser
///    (`SpeechToTextPlugin.kt`: the `null == speechRecognizer` fallback) and
///    streams the audio to Google with no error and no signal back to Dart.
///
/// That silent fallback is the same shape as the ModelBeat model swap, with a
/// worse payload. We cannot detect it from Dart, so we do not pretend to:
/// [available] refuses Android below API 31 (where on-device recognition does
/// not exist at all), and the consent copy tells Android users plainly that
/// the platform may use network recognition. Refusing what we cannot verify is
/// the same rule the AI gateway follows.
class VoiceInput {
  VoiceInput({SpeechEngine? engine, bool? isAndroidOverride})
      : _engine = engine ?? PluginSpeechEngine(),
        _isAndroid = isAndroidOverride ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final SpeechEngine _engine;
  final bool _isAndroid;

  /// Android's on-device recogniser is API 31+ (Android 12). Below that the
  /// plugin's `onDevice: true` is silently ignored, so voice is a promise we
  /// cannot keep — the same minimum-spec reality that ruled out bundling a
  /// local model.
  static const androidMinSdkForOnDevice = 31;

  /// Listen once and return what was said.
  ///
  /// [onPartial] streams interim text so the composer fills in as the user
  /// speaks — dictation that shows nothing for six seconds feels broken.
  Future<VoiceResult> listenOnce({
    Duration limit = const Duration(seconds: 30),
    void Function(String partial)? onPartial,
  }) async {
    var text = '';
    try {
      final started = await _engine.start(
        limit: limit,
        onResult: (t, isFinal) {
          text = t;
          if (!isFinal) onPartial?.call(t);
        },
      );
      if (!started) return const VoiceResult(VoiceOutcome.denied);
    } catch (e) {
      // iOS raises here when on-device recognition is unsupported. That is the
      // platform REFUSING to leak audio — a success of the design — so it gets
      // its own outcome. Retrying without the flag would defeat the point.
      if (e.toString().toLowerCase().contains('ondevice')) {
        return const VoiceResult(VoiceOutcome.noOnDevice);
      }
      debugPrint('voice listen failed: $e');
      return const VoiceResult(VoiceOutcome.failed);
    }

    // Wait for the platform to settle rather than returning the first partial.
    while (_engine.isListening) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final trimmed = text.trim();
    return trimmed.isEmpty
        ? const VoiceResult(VoiceOutcome.empty)
        : VoiceResult(VoiceOutcome.ok, trimmed);
  }

  Future<void> stop() => _engine.stop();

  /// Android cannot promise on-device recognition, so the UI must say so once
  /// before the first use. iOS needs no such warning: it refuses instead.
  bool get needsNetworkDisclosure => _isAndroid;
}
