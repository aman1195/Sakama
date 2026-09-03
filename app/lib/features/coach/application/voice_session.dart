import 'package:flutter/foundation.dart';

import '../data/voice_input.dart';
import '../data/voice_output.dart';
import '../domain/spoken_intent.dart';

/// Voice mode (S-101): a conversation, not a dictation box.
///
/// WHAT MAKES IT A MODE. Today's mic transcribes into the composer and stops;
/// every turn costs two taps and the reply arrives as text. Here the loop runs
/// itself — listen, answer, listen again — until the user closes it or stops
/// talking. That difference is the whole feature, and it is why this is a state
/// machine rather than a handful of callbacks in a widget.
///
/// AUDIO NEVER LEAVES THE PHONE. Recognition is on-device ([VoiceInput], which
/// refuses rather than falling back on iOS) and synthesis is on-device
/// ([VoiceOutput], which stays silent rather than using a network voice). Only
/// the TEXT of a turn goes upstream, exactly as the typed chat already does —
/// so this adds a mode, not a new class of egress. A realtime speech-to-speech
/// engine would change that, and needs its own ADR before it is written.
enum VoicePhase {
  /// Not started, or finished.
  idle,

  /// Microphone open, waiting for the user.
  listening,

  /// Their turn is in, waiting on Vita.
  thinking,

  /// Reading the reply aloud.
  speaking,

  /// Stopped with something the user needs to be told.
  failed,
}

@immutable
class VoiceSessionState {
  const VoiceSessionState({
    this.phase = VoicePhase.idle,
    this.transcript = '',
    this.reply = '',
    this.muted = false,
    this.notice,
  });

  final VoicePhase phase;

  /// What is being heard right now. Shown live, because a mode that displays
  /// nothing for six seconds reads as broken.
  final String transcript;

  /// The latest reply, always shown as captions even when muted or when no
  /// on-device voice exists.
  final String reply;

  /// Replies are not spoken. The session keeps running.
  final bool muted;

  /// Why it stopped, when the user needs to know.
  final String? notice;

  bool get isRunning =>
      phase == VoicePhase.listening ||
      phase == VoicePhase.thinking ||
      phase == VoicePhase.speaking;

  VoiceSessionState copyWith({
    VoicePhase? phase,
    String? transcript,
    String? reply,
    bool? muted,
    String? notice,
    bool clearNotice = false,
  }) =>
      VoiceSessionState(
        phase: phase ?? this.phase,
        transcript: transcript ?? this.transcript,
        reply: reply ?? this.reply,
        muted: muted ?? this.muted,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Runs the listen → answer → listen loop.
///
/// Everything it touches is injected, so the loop is testable without a
/// microphone, a speaker, or a network.
class VoiceSession {
  VoiceSession({
    required this.input,
    required this.output,
    required this.turn,
    required this.hasPendingDraft,
    required this.confirmDraft,
    required this.dismissDraft,
    this.maxQuietTurns = 2,
  });

  final VoiceInput input;
  final VoiceOutput output;

  /// Send a turn and return Vita's reply text.
  final Future<String> Function(String userText) turn;
  final bool Function() hasPendingDraft;

  /// Write the pending proposal and return what to say about it.
  final Future<String> Function() confirmDraft;
  final void Function() dismissDraft;

  /// How many silent turns end the session.
  ///
  /// A mode that listens forever is a microphone the user forgot about, which
  /// in a health app is the single worst thing to leave running.
  final int maxQuietTurns;

  /// Pause between Vita finishing and the microphone reopening.
  ///
  /// Short, but not zero: `speak` waits for the utterance, and this covers what
  /// is still decaying in the room afterwards.
  static const settleAfterSpeaking = Duration(milliseconds: 250);

  VoiceSessionState _state = const VoiceSessionState();
  VoiceSessionState get state => _state;

  /// The last thing Vita said, so the loop can recognise its own voice.
  String _lastSpoken = '';

  final _listeners = <void Function(VoiceSessionState)>[];
  void addListener(void Function(VoiceSessionState) l) => _listeners.add(l);
  void removeListener(void Function(VoiceSessionState) l) =>
      _listeners.remove(l);

  void _set(VoiceSessionState s) {
    _state = s;
    for (final l in List.of(_listeners)) {
      l(s);
    }
  }

  bool _stopping = false;

  /// Run until the user closes it or goes quiet.
  Future<void> run() async {
    if (_state.isRunning) return;
    _stopping = false;
    var quiet = 0;

    while (!_stopping) {
      _set(_state.copyWith(
          phase: VoicePhase.listening, transcript: '', clearNotice: true));

      final heard = await input.listenOnce(
        // A short pause for an ordinary turn, the long one when a proposal is
        // on screen — because on THAT turn a clipped "yes but not the rice"
        // becomes "yes" and writes a food row. Truncation inverts the
        // classifier rather than defeating it safely.
        pauseFor: VoiceInput.pauseForTurn(answeringProposal: hasPendingDraft()),
        onPartial: (t) {
          if (_stopping) return;
          _set(_state.copyWith(transcript: t));
        },
      );
      if (_stopping) break;

      switch (heard.outcome) {
        case VoiceOutcome.empty:
          quiet++;
          if (quiet >= maxQuietTurns) {
            await _finish();
            return;
          }
          continue;

        case VoiceOutcome.denied:
          await _fail('Sakama needs microphone and speech access. Enable it '
              'in Settings to talk to Vita.');
          return;

        case VoiceOutcome.noOnDevice:
          // The platform refused rather than uploading the audio. That is the
          // promise holding, so it is worded as a protection, not a fault.
          await _fail('This phone cannot transcribe speech privately, so '
              'nothing was recorded. You can type instead.');
          return;

        case VoiceOutcome.failed:
          await _fail('The microphone stopped working. Try again.');
          return;

        case VoiceOutcome.ok:
          // SECOND LINE OF DEFENCE AGAINST HEARING OURSELVES. The first is
          // that `speak` now waits for the utterance to finish, so the mic is
          // shut while the speaker plays. This catches the tail: a reverberant
          // room, a Bluetooth speaker running behind, a word still decaying
          // when the mic opens.
          //
          // It matters more than an ordinary guard because of WHAT Vita says.
          // Its confirmation prompt is "shall I log that?", and "log that" is
          // an affirmative — so an echo could confirm the app's own proposal
          // and write a food row with no user involved. Treating our own words
          // as silence also lets the session time out normally instead of
          // talking to itself forever.
          if (_isEcho(heard.text)) {
            quiet++;
            if (quiet >= maxQuietTurns) {
              await _finish();
              return;
            }
            continue;
          }
          quiet = 0;
          await _handle(heard.text);
          if (_stopping) return;
      }
    }
    await _finish();
  }

  Future<void> _handle(String said) async {
    _set(_state.copyWith(transcript: said));

    // A proposal on screen turns this turn into an answer. Only an
    // unmistakable one acts; anything else is treated as a new message, so a
    // misheard word costs a turn rather than a wrong entry in a health diary.
    if (hasPendingDraft()) {
      switch (actionForDictation(text: said, hasPendingDraft: true)) {
        case DictationAction.confirmDraft:
          _set(_state.copyWith(phase: VoicePhase.thinking));
          await _say(await confirmDraft());
          return;
        case DictationAction.dismissDraft:
          dismissDraft();
          await _say('Okay, I left it out.');
          return;
        case DictationAction.fillComposer:
          break; // not an answer — send it as a message
      }
    }

    _set(_state.copyWith(phase: VoicePhase.thinking));
    try {
      await _say(await turn(said));
    } catch (e) {
      debugPrint('voice turn failed: $e');
      await _say("Something went wrong reaching me. Try again in a moment.");
    }
  }

  /// Did we just hear the reply we ourselves spoke?
  ///
  /// Substring both ways, on normalised words: a recogniser catches a FRAGMENT
  /// of the tail, not the whole sentence, so equality would never fire.
  bool _isEcho(String heard) {
    if (_lastSpoken.isEmpty) return false;
    String flat(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final said = flat(_lastSpoken);
    final got = flat(heard);
    if (got.isEmpty) return false;
    return said.contains(got) || got.contains(said);
  }

  Future<void> _say(String text) async {
    if (_stopping) return;
    _lastSpoken = text;
    _set(_state.copyWith(phase: VoicePhase.speaking, reply: text));
    if (_state.muted) return;
    final outcome = await output.speak(text);
    // Let the room go quiet before the microphone opens again.
    if (outcome == SpeakOutcome.ok && !_stopping) {
      await Future<void>.delayed(settleAfterSpeaking);
    }
    if (outcome == SpeakOutcome.noOnDeviceVoice) {
      // Captions are always on, so the answer is never lost — say once why it
      // is silent, and keep the conversation going.
      _set(_state.copyWith(
          muted: true,
          notice: 'No private voice on this phone, so replies stay on screen.'));
    }
  }

  /// The user talking over Vita, or tapping to interrupt.
  ///
  /// NOT automatic voice-activity barge-in: keeping the microphone open while
  /// the speaker is playing needs echo cancellation we do not have, and
  /// without it Vita hears itself and answers its own reply. Tap-to-interrupt
  /// is the honest version until that is solved.
  Future<void> interrupt() async => output.stop();

  void toggleMute() {
    _set(_state.copyWith(muted: !_state.muted, clearNotice: true));
    if (_state.muted) unawaitedStop();
  }

  void unawaitedStop() {
    // Silence immediately on mute; awaiting would hold the UI for a sentence.
    output.stop();
  }

  /// Close the session. Safe to call at any point, including mid-utterance.
  Future<void> stop() async {
    _stopping = true;
    await input.stop();
    await output.stop();
    _set(_state.copyWith(phase: VoicePhase.idle, transcript: ''));
  }

  Future<void> _finish() async {
    _stopping = true;
    await output.stop();
    _set(_state.copyWith(phase: VoicePhase.idle, transcript: ''));
  }

  Future<void> _fail(String message) async {
    _stopping = true;
    await output.stop();
    _set(_state.copyWith(phase: VoicePhase.failed, notice: message));
  }
}
