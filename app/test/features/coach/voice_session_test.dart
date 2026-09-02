import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/application/voice_session.dart';
import 'package:sakama/features/coach/data/voice_input.dart';
import 'package:sakama/features/coach/data/voice_output.dart';

/// The loop is what makes this a MODE rather than a dictation box, so the loop
/// is what gets tested: that it keeps going, that it stops when it should, and
/// that a misheard word still cannot write to a health diary.

class _ScriptedEngine implements SpeechEngine {
  _ScriptedEngine(this._script);
  final List<VoiceResult> _script;
  int calls = 0;

  /// REAL state, not a hardcoded false. Review found every microphone guard in
  /// the state machine could be deleted with all 16 tests green, because
  /// nothing in the fixture ever observed the input engine — the test named
  /// "close stops listening and speaking" asserted the SPEAKER.
  bool _listening = false;
  int stops = 0;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    required Duration limit,
  }) async {
    final r = _script[calls.clamp(0, _script.length - 1)];
    calls++;
    if (r.outcome == VoiceOutcome.denied) return false;
    // How the real plugin reports it: iOS throws rather than falling back to
    // Apple's servers, and VoiceInput translates that to noOnDevice.
    if (r.outcome == VoiceOutcome.noOnDevice) {
      throw Exception('onDevice recognition is not supported');
    }
    if (r.outcome == VoiceOutcome.failed) throw Exception('mic died');
    _listening = true;
    if (r.text.isNotEmpty) onResult(r.text, true);
    _listening = false; // the platform settles before listenOnce returns
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _listening = false;
  }
}

class _FakeSynth implements SpeechSynthesizer {
  _FakeSynth({this.embedded = true});
  final bool embedded;
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<List<Map<String, String>>> voices() async => [
        {'name': 'v', 'locale': 'en-IN', 'network_required': embedded ? '0' : '1'}
      ];
  @override
  Future<bool> useVoice(Map<String, String> voice) async => true;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async => stops++;
}

void main() {
  ({
    VoiceSession session,
    _FakeSynth synth,
    _ScriptedEngine engine,
    List<String> sent,
    List<String> confirmed,
    List<String> dismissed,
  }) build({
    required List<VoiceResult> heard,
    bool pendingDraft = false,
    bool embeddedVoice = true,
    bool android = false,
    String reply = 'Here is your answer.',
  }) {
    final synth = _FakeSynth(embedded: embeddedVoice);
    final sent = <String>[];
    final confirmed = <String>[];
    final dismissed = <String>[];
    var hasDraft = pendingDraft;

    final engine = _ScriptedEngine(heard);
    final session = VoiceSession(
      input: VoiceInput(engine: engine, isAndroidOverride: false),
      output: VoiceOutput(synthesizer: synth, isAndroidOverride: android),
      turn: (t) async {
        sent.add(t);
        return reply;
      },
      hasPendingDraft: () => hasDraft,
      confirmDraft: () async {
        confirmed.add('yes');
        hasDraft = false;
        return 'Logged 2 items.';
      },
      dismissDraft: () {
        dismissed.add('no');
        hasDraft = false;
      },
    );
    return (
      session: session,
      synth: synth,
      engine: engine,
      sent: sent,
      confirmed: confirmed,
      dismissed: dismissed
    );
  }

  const ok = VoiceResult(VoiceOutcome.ok, 'how is my protein');
  const quiet = VoiceResult(VoiceOutcome.empty);

  test('one spoken turn is sent and the reply is spoken back', () async {
    final h = build(heard: [ok, quiet, quiet]);
    await h.session.run();

    expect(h.sent, ['how is my protein']);
    expect(h.synth.spoken, ['Here is your answer.']);
  });

  test('it KEEPS GOING — that is the difference from dictation', () async {
    // Three spoken turns without a single tap. A one-shot mic cannot do this,
    // and it is the whole reason the mode exists.
    final h = build(heard: [ok, ok, ok, quiet, quiet]);
    await h.session.run();

    expect(h.sent.length, 3);
    expect(h.synth.spoken.length, 3);
    expect(h.session.state.phase, VoicePhase.idle);
  });

  test('silence ends it, so a forgotten microphone cannot stay open', () async {
    final h = build(heard: [quiet, quiet]);
    await h.session.run();

    expect(h.sent, isEmpty);
    expect(h.session.state.phase, VoicePhase.idle);
  });

  test('one quiet turn is not the end — people pause', () async {
    final h = build(heard: [quiet, ok, quiet, quiet]);
    await h.session.run();
    expect(h.sent, ['how is my protein']);
  });

  test('it takes EXACTLY two silent turns, not more', () async {
    // Raising maxQuietTurns or loosening >= to > used to change nothing that
    // any test could see, so the stated behaviour was unpinned.
    final h = build(heard: [quiet, quiet, quiet, quiet, quiet]);
    await h.session.run();
    expect(h.engine.calls, 2,
        reason: 'a mode that keeps listening is a mic the user forgot about');
  });

  group('a proposal on screen turns the turn into an answer', () {
    test('a clear yes confirms and says what happened', () async {
      final h = build(
          heard: [const VoiceResult(VoiceOutcome.ok, 'yes'), quiet, quiet],
          pendingDraft: true);
      await h.session.run();

      expect(h.confirmed, ['yes']);
      expect(h.sent, isEmpty, reason: 'an answer is not a new question');
      expect(h.synth.spoken, contains('Logged 2 items.'));
    });

    test('a clear no dismisses and nothing is written', () async {
      final h = build(
          heard: [const VoiceResult(VoiceOutcome.ok, 'nahi'), quiet, quiet],
          pendingDraft: true);
      await h.session.run();

      expect(h.dismissed, ['no']);
      expect(h.confirmed, isEmpty);
    });

    test('a CORRECTION is never a confirmation', () async {
      // The case that matters most: the user is fixing the amount and the
      // sentence opens with "yes". Logging here would write a number they
      // believe they just corrected.
      final h = build(
          heard: [
            const VoiceResult(VoiceOutcome.ok, 'yes but it was two rotis'),
            quiet,
            quiet
          ],
          pendingDraft: true);
      await h.session.run();

      expect(h.confirmed, isEmpty);
      expect(h.dismissed, isEmpty);
      expect(h.sent, ['yes but it was two rotis'],
          reason: 'it becomes a message, and the proposal stays up');
    });

    test('with nothing pending, "yes" is just a message', () async {
      final h = build(heard: [const VoiceResult(VoiceOutcome.ok, 'yes'), quiet, quiet]);
      await h.session.run();
      expect(h.confirmed, isEmpty);
      expect(h.sent, ['yes']);
    });
  });

  group('stopping', () {
    test('close stops the MICROPHONE, not just the speaker', () async {
      // Deleting `input.stop()` from stop() used to pass every test in this
      // file. A live microphone the user believes is closed is the worst
      // failure this feature has.
      final h = build(heard: [ok, ok, ok, quiet, quiet]);
      final running = h.session.run();
      await h.session.stop();
      await running;

      expect(h.engine.stops, greaterThan(0), reason: 'the mic must be closed');
      expect(h.engine.isListening, isFalse);
      expect(h.synth.stops, greaterThan(0));
      expect(h.session.state.phase, VoicePhase.idle);
    });

    test('the microphone is closed when silence ends the session', () async {
      final h = build(heard: [quiet, quiet]);
      await h.session.run();
      expect(h.engine.isListening, isFalse);
    });

    test('interrupt silences Vita without ending the session', () async {
      final h = build(heard: [quiet, quiet]);
      await h.session.interrupt();
      expect(h.synth.stops, 1);
      expect(h.session.state.phase, isNot(VoicePhase.failed));
    });
  });

  group('what the user is told', () {
    test('a denied microphone ends it with an actionable reason', () async {
      final h = build(heard: [const VoiceResult(VoiceOutcome.denied)]);
      await h.session.run();

      expect(h.session.state.phase, VoicePhase.failed);
      expect(h.session.state.notice, contains('Settings'));
    });

    test('a platform that will not transcribe privately is a PROTECTION',
        () async {
      final h = build(heard: [const VoiceResult(VoiceOutcome.noOnDevice)]);
      await h.session.run();

      expect(h.session.state.notice, contains('privately'));
      expect(h.session.state.notice, contains('nothing was recorded'));
    });

    test('no on-device VOICE mutes but keeps the conversation going', () async {
      // Captions are always on, so a silent reply is still an answer.
      // Android, where a network voice is detectable and refused. On iOS every
      // voice is local, so there is nothing to refuse.
      final h = build(heard: [ok, quiet, quiet], embeddedVoice: false, android: true);
      await h.session.run();

      expect(h.synth.spoken, isEmpty, reason: 'never through a network voice');
      expect(h.sent, ['how is my protein'], reason: 'the turn still happened');
      expect(h.session.state.reply, 'Here is your answer.');
      expect(h.session.state.muted, isTrue);
    });

    test('muted means captions only, and the loop still runs', () async {
      final h = build(heard: [ok, quiet, quiet]);
      h.session.toggleMute();
      await h.session.run();

      expect(h.synth.spoken, isEmpty);
      expect(h.sent, ['how is my protein']);
      expect(h.session.state.reply, 'Here is your answer.');
    });
  });

  test('a failed turn is spoken as an apology, not a dead session', () async {
    final synth = _FakeSynth();
    final session = VoiceSession(
      input: VoiceInput(
          engine: _ScriptedEngine([ok, quiet, quiet]), isAndroidOverride: false),
      output: VoiceOutput(synthesizer: synth, isAndroidOverride: false),
      turn: (_) async => throw Exception('offline'),
      hasPendingDraft: () => false,
      confirmDraft: () async => '',
      dismissDraft: () {},
    );
    await session.run();

    expect(synth.spoken.single, contains('Something went wrong'));
    expect(session.state.phase, VoicePhase.idle);
  });

  test('the live transcript is published while the user speaks', () async {
    final h = build(heard: [ok, quiet, quiet]);
    final seen = <String>[];
    h.session.addListener((s) {
      if (s.transcript.isNotEmpty) seen.add(s.transcript);
    });
    await h.session.run();

    expect(seen, contains('how is my protein'));
  });

  /// VITA MUST NOT HEAR ITSELF. `flutter_tts` defaults `awaitSpeakCompletion`
  /// to false, so `speak` used to return before the utterance played and the
  /// loop reopened the microphone over the loudspeaker. `speech_to_text` sets
  /// the audio session to `.mixWithOthers` with no echo cancellation, so the
  /// recogniser heard Vita — and Vita's own prompt says "shall I log that?",
  /// where "log that" is an affirmative that CONFIRMS A FOOD WRITE.
  group('hearing itself', () {
    test('an echo of the reply is treated as silence, not as a turn', () async {
      final h = build(
        heard: [ok, const VoiceResult(VoiceOutcome.ok, 'Here is your'), quiet],
        reply: 'Here is your answer.',
      );
      await h.session.run();

      expect(h.sent, ['how is my protein'],
          reason: 'the fragment of our own reply must not become a turn');
    });

    test('an echo cannot confirm a pending proposal', () async {
      // The catastrophic case: Vita asks "shall I log that?", the mic catches
      // "log that", and the app confirms its own proposal with no user.
      // The real trace: the user asks, Vita answers "…Shall I log that?" and
      // a draft appears, then the microphone opens and catches the tail.
      final h = build(
        heard: [ok, const VoiceResult(VoiceOutcome.ok, 'log that'), quiet, quiet],
        pendingDraft: true,
        reply: 'You are at 48 grams. Shall I log that?',
      );
      await h.session.run();

      expect(h.confirmed, isEmpty,
          reason: 'the app must never write a food row from its own voice');
    });

    test('an echo still lets the session time out', () async {
      // Counting echoes as silence is what stops the app talking to itself
      // forever and burning the daily cap.
      final h = build(
        heard: [
          const VoiceResult(VoiceOutcome.ok, 'Here is your'),
          const VoiceResult(VoiceOutcome.ok, 'Here is your'),
        ],
        reply: 'Here is your answer.',
      );
      await h.session.run();
      expect(h.session.state.phase, VoicePhase.idle);
    });

    test('a genuine reply that merely OVERLAPS wording still counts', () async {
      // The guard must not swallow the user. "protein" appears in neither
      // direction of the containment check against the reply.
      final h = build(heard: [ok, quiet, quiet], reply: 'You are doing well.');
      await h.session.run();
      expect(h.sent, ['how is my protein']);
    });
  });
}
