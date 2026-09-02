import 'package:flutter/material.dart';

import '../application/voice_session.dart';

/// Voice mode (S-101): the screen that makes voice a MODE.
///
/// Full-bleed and dark on purpose. This is the one place in the app where the
/// user is not reading — they are talking, and the screen's job is to prove it
/// is listening, show what it heard, and get out of the way.
///
/// CAPTIONS ARE ALWAYS ON. The reply is on screen whether or not it is spoken,
/// so a muted session, a noisy room, or a phone with no private voice still
/// answers the question. Nothing here is audio-only.
class VoiceModeSheet extends StatefulWidget {
  const VoiceModeSheet({required this.session, super.key});
  final VoiceSession session;

  @override
  State<VoiceModeSheet> createState() => _VoiceModeSheetState();
}

class _VoiceModeSheetState extends State<VoiceModeSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  VoiceSessionState _state = const VoiceSessionState();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onState);
    _state = widget.session.state;
  }

  void _onState(VoiceSessionState s) {
    if (mounted) setState(() => _state = s);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onState);
    _pulse.dispose();
    super.dispose();
  }

  String get _title => switch (_state.phase) {
        VoicePhase.listening => 'Listening…',
        VoicePhase.thinking => 'Thinking…',
        VoicePhase.speaking => 'Vita is speaking',
        VoicePhase.failed => 'Voice stopped',
        VoicePhase.idle => 'Voice',
      };

  @override
  Widget build(BuildContext context) {
    // A pulsing circle is decoration to some people and a problem for others.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const ink = Color(0xFFF2F2F0);
    const ground = Color(0xFF0B0B0C);
    const accent = Color(0xFFB6F35C);

    return Semantics(
      identifier: 'voice-mode-sheet',
      child: Material(
        color: ground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_title,
                          style: const TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w600)),
                    ),
                    Semantics(
                      identifier: 'voice-mode-close',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: ink),
                        tooltip: 'Close voice mode',
                        onPressed: () async {
                          await widget.session.stop();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),

                // What is being heard, live. Silence here reads as broken, so
                // it shows a prompt rather than nothing.
                SizedBox(
                  height: 72,
                  child: Center(
                    child: Text(
                      _state.transcript.isEmpty
                          ? (_state.phase == VoicePhase.listening
                              ? 'Say something…'
                              : '')
                          : _state.transcript,
                      key: const Key('voice-transcript'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ink.withValues(alpha: 0.75), fontSize: 16),
                    ),
                  ),
                ),

                const Spacer(),

                // Tap to interrupt. Not automatic barge-in: holding the mic
                // open while the speaker plays needs echo cancellation we do
                // not have, and without it Vita hears itself.
                Semantics(
                  identifier: 'voice-mode-orb',
                  button: true,
                  label: _state.phase == VoicePhase.speaking
                      ? 'Tap to interrupt'
                      : _title,
                  child: GestureDetector(
                    onTap: widget.session.interrupt,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final t = reduceMotion ? 0.0 : _pulse.value;
                        final active = _state.phase == VoicePhase.listening ||
                            _state.phase == VoicePhase.speaking;
                        return SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: Container(
                              width: 160 + (active ? t * 24 : 0),
                              height: 160 + (active ? t * 24 : 0),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(
                                    alpha: active ? 0.18 + t * 0.10 : 0.10),
                                border: Border.all(color: accent, width: 2),
                              ),
                              child: Icon(
                                switch (_state.phase) {
                                  VoicePhase.speaking => Icons.graphic_eq,
                                  VoicePhase.thinking => Icons.more_horiz,
                                  VoicePhase.failed => Icons.mic_off,
                                  _ => Icons.mic,
                                },
                                color: accent,
                                size: 44,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const Spacer(),

                if (_state.reply.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        _state.reply,
                        key: const Key('voice-captions'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ink, fontSize: 17),
                      ),
                    ),
                  ),

                if (_state.notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _state.notice!,
                      key: const Key('voice-notice'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: ink.withValues(alpha: 0.7), fontSize: 13),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(
                    identifier: 'voice-mode-mute',
                    button: true,
                    child: TextButton.icon(
                      onPressed: () => widget.session.toggleMute(),
                      icon: Icon(
                          _state.muted ? Icons.volume_off : Icons.volume_up,
                          color: ink),
                      label: Text(_state.muted ? 'Voice off' : 'Voice on',
                          style: const TextStyle(color: ink)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
