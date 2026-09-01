import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/data/voice_output.dart';

/// Vita's replies are health data. Speaking one through a network voice would
/// send it to the platform vendor, which is exactly what ADR 0016 decision 1
/// says never happens. The plugin does not prevent that; this does.

class _FakeSynth implements SpeechSynthesizer {
  _FakeSynth(this._voices, {this.throwOnSpeak = false, this.acceptVoice = true});
  List<Map<String, String>> _voices;
  final bool throwOnSpeak;

  /// The platform can refuse a voice — Android answers 0 with no exception.
  bool acceptVoice;
  bool throwOnVoices = false;

  Map<String, String>? selected;
  final spoken = <String>[];
  int stops = 0;
  int voiceQueries = 0;
  int voicePins = 0;

  @override
  Future<List<Map<String, String>>> voices() async {
    voiceQueries++;
    if (throwOnVoices) throw Exception('platform returned null');
    return _voices;
  }

  @override
  Future<bool> useVoice(Map<String, String> voice) async {
    voicePins++;
    if (!acceptVoice) return false;
    selected = voice;
    return true;
  }

  @override
  Future<void> speak(String text) async {
    if (throwOnSpeak) throw Exception('engine died');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;
}

Map<String, String> _voice(String name, String locale, {String? network}) => {
      'name': name,
      'locale': locale,
      'network_required': ?network,
    };

void main() {
  group('EmbeddedVoicePolicy on Android — where the risk is', () {
    const policy = EmbeddedVoicePolicy(isAndroid: true);

    test('a network voice is never chosen', () {
      final chosen = policy.choose([
        _voice('en-in-x-network', 'en-IN', network: '1'),
        _voice('en-us-x-local', 'en-US', network: '0'),
      ]);
      expect(chosen!['name'], 'en-us-x-local',
          reason: 'the wrong accent is fine; sending health data is not');
    });

    test('when every voice needs the network, there is no voice', () {
      final chosen = policy.choose([
        _voice('a', 'en-IN', network: '1'),
        _voice('b', 'en-US', network: '1'),
      ]);
      expect(chosen, isNull);
    });

    test('a MISSING flag is refused, not assumed safe', () {
      // Android always reports the field today. If a future version stops, the
      // failure must be silence, not an upload. Every fail-open bug in this
      // codebase has looked exactly like treating absence as permission.
      expect(policy.choose([_voice('mystery', 'en-IN')]), isNull);
      expect(policy.isEmbedded(_voice('mystery', 'en-IN')), isFalse);
    });

    test('an unexpected flag value is refused', () {
      for (final v in ['1', 'true', 'yes', '', 'unknown']) {
        expect(policy.isEmbedded(_voice('x', 'en-IN', network: v)), isFalse,
            reason: 'network_required="$v"');
      }
    });

    test('no voices at all is not a crash', () {
      expect(policy.choose(const []), isNull);
    });
  });

  group('EmbeddedVoicePolicy on iOS — safe by construction', () {
    const policy = EmbeddedVoicePolicy(isAndroid: false);

    test('a voice with no flag is accepted, because iOS reports none', () {
      // AVSpeechSynthesisVoice is always local, so the absent key is "nothing
      // to report" rather than "we could not tell".
      final chosen = policy.choose([_voice('Rishi', 'en-IN')]);
      expect(chosen!['name'], 'Rishi');
    });
  });

  group('which voice, once the unsafe ones are gone', () {
    const policy = EmbeddedVoicePolicy(isAndroid: true);

    test('prefers the exact locale', () {
      final chosen = policy.choose([
        _voice('us', 'en-US', network: '0'),
        _voice('in', 'en-IN', network: '0'),
      ]);
      expect(chosen!['name'], 'in');
    });

    test('falls back to the same language in another region', () {
      final chosen = policy.choose([
        _voice('hi', 'hi-IN', network: '0'),
        _voice('gb', 'en-GB', network: '0'),
      ]);
      expect(chosen!['name'], 'gb');
    });

    test('takes any embedded voice rather than staying silent', () {
      final chosen = policy.choose([_voice('hi', 'hi-IN', network: '0')]);
      expect(chosen!['name'], 'hi');
    });

    test('underscored and differently-cased locales still match', () {
      // Android returns en_IN in places; matching must not hinge on the shape.
      final chosen = policy.choose([
        _voice('us', 'en_US', network: '0'),
        _voice('in', 'EN_in', network: '0'),
      ]);
      expect(chosen!['name'], 'in');
    });
  });

  group('VoiceOutput', () {
    test('speaks through a vetted voice, and sets it explicitly', () async {
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);

      expect(await out.speak('You have 690 kcal left.'), SpeakOutcome.ok);
      expect(synth.spoken, ['You have 690 kcal left.']);
      expect(synth.selected!['name'], 'local',
          reason: "the engine's current voice is not necessarily the vetted one");
    });

    test('stays SILENT when only network voices exist', () async {
      // The whole point. Nothing is spoken, and the caller is told why.
      final synth = _FakeSynth([_voice('cloud', 'en-IN', network: '1')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);

      expect(await out.speak('Your fasting window closed.'),
          SpeakOutcome.noOnDeviceVoice);
      expect(synth.spoken, isEmpty);
      expect(synth.selected, isNull);
    });

    test('empty text is not spoken', () async {
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      expect(await out.speak('   '), SpeakOutcome.empty);
      expect(synth.spoken, isEmpty);
    });

    test('an engine failure is reported, not thrown at the UI', () async {
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')],
          throwOnSpeak: true);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      expect(await out.speak('hello'), SpeakOutcome.failed);
    });

    test('the voice LIST is enumerated once, but the pin is re-issued every '
        'time', () async {
      // THE BLOCKING BUG. Pinning once and caching "allowed" meant that when
      // the Android engine is recreated — service connection dropped, engine
      // updated, engine changed in Settings — it restores only the LANGUAGE,
      // and the next reply goes out on the engine's default voice, which for
      // many locales is a network one. Enumerating is a cheap round trip;
      // being wrong about this reads health data to a server.
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      await out.speak('one');
      await out.speak('two');
      expect(synth.voiceQueries, 1, reason: 'the list does not change');
      expect(synth.voicePins, 2, reason: 'the pin can be lost between them');
      expect(synth.spoken, ['one', 'two']);
    });

    test('a REFUSED pin is not spoken through', () async {
      // setVoice answers 0 when nothing matches, with no exception. Ignoring
      // that meant believing a pin we never got and speaking anyway.
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')],
          acceptVoice: false);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      expect(await out.speak('hello'), SpeakOutcome.noOnDeviceVoice);
      expect(synth.spoken, isEmpty);
    });

    test('a refused pin makes the next attempt look for a voice again',
        () async {
      // The vetted voice may have been uninstalled. Retrying the same name
      // forever would be silence that never recovers.
      final synth = _FakeSynth([_voice('gone', 'en-IN', network: '0')],
          acceptVoice: false);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      await out.speak('one');
      synth.acceptVoice = true;
      synth._voices = [_voice('installed', 'en-IN', network: '0')];
      expect(await out.speak('two'), SpeakOutcome.ok);
      expect(synth.selected!['name'], 'installed');
    });

    test('a transient enumeration failure is not remembered forever', () async {
      // Caching the failure turned one null from the platform into permanent
      // silence, under a message telling the user their PHONE cannot do it.
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')])
        ..throwOnVoices = true;
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      expect(await out.speak('one'), SpeakOutcome.failed);

      synth.throwOnVoices = false;
      expect(await out.speak('two'), SpeakOutcome.ok,
          reason: 'the device was always capable; the query failed once');
    });

    test('a network-only device stays silent on every utterance, not just the '
        'first', () async {
      final synth = _FakeSynth([_voice('cloud', 'en-IN', network: '1')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      await out.speak('first');
      expect(await out.speak('second'), SpeakOutcome.noOnDeviceVoice);
      expect(synth.spoken, isEmpty);
    });

    test('barge-in stops immediately', () async {
      final synth = _FakeSynth([_voice('local', 'en-IN', network: '0')]);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      await out.speak('a long reply');
      await out.stop();
      expect(synth.stops, 1);
    });

    test('stopping when nothing is speaking is harmless', () async {
      final synth = _FakeSynth(const []);
      final out = VoiceOutput(synthesizer: synth, isAndroidOverride: true);
      await out.stop();
      expect(synth.stops, 1, reason: 'a stop with nothing to stop must not throw');
    });
  });
}
