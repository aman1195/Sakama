import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app/kit/kit.dart';
import '../../../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../capture/presentation/snap_controller.dart' show captureJpegBase64;
import '../../settings/presentation/ai_disclosure.dart';
import '../domain/coach_message.dart';
import '../domain/tool_draft.dart';
import '../data/voice_input.dart';
import '../data/voice_output.dart';
import '../application/voice_session.dart';
import '../domain/spoken_intent.dart';
import 'voice_mode_sheet.dart';
import 'coach_controller.dart';

/// Vita — the coach tab. A persistent chat grounded in today's real data.
class CoachPage extends ConsumerStatefulWidget {
  const CoachPage({super.key});
  @override
  ConsumerState<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends ConsumerState<CoachPage> {
  final _input = TextEditingController();
  final _voice = VoiceInput();
  final _speech = VoiceOutput();
  bool _listening = false;

  /// The exact transcript last dictated into the composer, if any.
  ///
  /// THE TEXT, NOT A FLAG. A boolean had to be cleared on every path that
  /// sends, and review found two that do not go through [_send] at all — the
  /// photo button and the suggestion chip, the latter in a child widget that
  /// cannot reach this state. A stale `true` there meant a turn the user TYPED
  /// got read aloud, which is the one thing the rule exists to prevent.
  ///
  /// Comparing the text needs no clearing anywhere: a photo turn, a chip turn
  /// and a typed turn simply do not match, so they cannot speak. Editing a
  /// dictated line no longer speaks either, which is the honest reading — once
  /// you are typing, you are in a typing conversation.
  String? _dictated;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // SWITCHING TABS MUST SILENCE VITA, and `dispose` cannot do it: this page
    // is a branch of a StatefulShellRoute.indexedStack, so it stays MOUNTED
    // when the user leaves. go_router wraps each branch in
    // `TickerMode(enabled: isActive)` (go_router route.dart:1696), so losing
    // the ticker is the signal that this tab went away — and depending on it
    // brings us back here the moment it flips.
    if (!TickerMode.valuesOf(context).enabled) unawaited(_speech.stop());
  }

  @override
  void dispose() {
    // The other half of the rule above. This catches teardown — sign-out, a
    // shell rebuild — which the ticker signal does not. It does NOT catch a
    // tab switch, because the branch stays mounted; believing it did was the
    // bug, and the fix is in didChangeDependencies rather than here.
    unawaited(_speech.stop());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Read the newest reply aloud.
  ///
  /// Only ever called after a turn the user SPOKE. Typing gets text back;
  /// speaking gets speech back. That keeps the feature off for anyone who
  /// never touches the microphone, without a setting to discover.
  Future<void> _speakLatestReply() async {
    final messages = ref.read(coachControllerProvider).messages;
    final latest = messages.lastWhere((m) => m.role == CoachRole.vita,
        orElse: () => const CoachMessage(CoachRole.vita, ''));
    final outcome = await _speech.speak(latest.content);
    if (!mounted) return;
    if (outcome == SpeakOutcome.noOnDeviceVoice) {
      // A protection, not a malfunction — the same wording as dictation uses
      // when the platform refuses rather than uploading.
      _toast('This phone has no private voice available, so Vita stayed '
          'silent. The reply is on screen.');
    }
  }

  /// Open VOICE MODE (S-101).
  ///
  /// THE MIC OPENS THE MODE, and that is the answer to "where is voice mode?".
  /// Before this it opened dictation, which transcribed into the composer and
  /// stopped — the feature existed and nobody could find it, because there was
  /// nothing to find. Dictation is still here on a long-press for anyone who
  /// wants words in the box rather than a conversation.
  Future<void> _openVoiceMode() async {
    if (!await ensureAiConsent(context, ref)) return;
    if (!mounted) return;
    if (await _voice.needsNetworkDisclosure()) {
      if (!await _confirmAndroidVoice()) return;
      await _voice.rememberNetworkDisclosure();
    }
    if (!mounted) return;

    final notifier = ref.read(coachControllerProvider.notifier);
    final session = VoiceSession(
      input: _voice,
      output: _speech,
      turn: (text) async {
        await notifier.send(text);
        final messages = ref.read(coachControllerProvider).messages;
        return messages
            .lastWhere((m) => m.role == CoachRole.vita,
                orElse: () => const CoachMessage(CoachRole.vita, ''))
            .content;
      },
      hasPendingDraft: () =>
          ref.read(coachControllerProvider).pendingDrafts.isNotEmpty,
      confirmDraft: () async {
        await notifier.confirmDraft();
        final messages = ref.read(coachControllerProvider).messages;
        return messages
            .lastWhere((m) => m.role == CoachRole.vita,
                orElse: () => const CoachMessage(CoachRole.vita, 'Logged.'))
            .content;
      },
      dismissDraft: notifier.dismissDraft,
    );

    // Fire the loop and show the sheet over it. The sheet listens; it does not
    // drive — closing it stops the session, and the session ending pops it.
    final running = session.run();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 1,
        child: VoiceModeSheet(session: session),
      ),
    );
    // Whatever closed it — the button, a swipe, silence — the microphone must
    // not still be open.
    await session.stop();
    await running;
  }

  /// Dictate into the composer (ADR 0016 decision 12).
  ///
  /// Speech is recognised ON DEVICE — the audio never leaves the phone on
  /// iOS, which refuses outright rather than falling back to Apple's servers.
  /// Android cannot make that promise (its recogniser silently falls back to
  /// Google below API 31 / without a downloaded model), so Android users are
  /// told before the first use, rather than discovering it never.
  ///
  /// The transcript lands in the text field UNSENT. Dictation is often
  /// misheard, and a health app that fires off "I ate two rotis" when you said
  /// "I ate two rusks" has made a mistake the user cannot see coming. Same
  /// propose-confirm instinct as every other write path here.
  Future<void> _dictate() async {
    // BARGE-IN. Reaching for the microphone means "I want to talk now", so
    // Vita stops mid-sentence. Waiting for it to finish is the thing that
    // makes voice assistants feel like arguing with an answering machine.
    await _speech.stop();
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (await _voice.needsNetworkDisclosure()) {
      if (!await _confirmAndroidVoice()) return;
      await _voice.rememberNetworkDisclosure();
    }
    if (!mounted) return;

    setState(() => _listening = true);
    final result = await _voice.listenOnce(
      onPartial: (t) {
        if (!mounted) return;
        _input.text = t;
        _input.selection = TextSelection.collapsed(offset: t.length);
      },
    );
    if (!mounted) return;
    setState(() => _listening = false);

    switch (result.outcome) {
      case VoiceOutcome.ok:
        // Answering a pending proposal out loud IS the confirmation — the user
        // said it deliberately, in response to a card asking the question, so
        // it is still an explicit act and ADR 0016 decision 2 holds.
        //
        // Only an UNMISTAKABLE answer acts. Anything else falls through to the
        // composer unsent, exactly as before, so a misheard word costs a tap
        // rather than a wrong entry in a health diary.
        final notifier = ref.read(coachControllerProvider.notifier);
        final action = actionForDictation(
          text: result.text,
          hasPendingDraft:
              ref.read(coachControllerProvider).pendingDrafts.isNotEmpty,
        );
        switch (action) {
          case DictationAction.confirmDraft:
            // The partial-transcript callback above put "yes" in the composer.
            // Leaving it there sends the word to Vita on the next tap, costing
            // a real exchange against the daily budget to say nothing.
            _input.clear();
            _dictated = null;
            await notifier.confirmDraft();
            await _speakLatestReply(); // "Logged 2 items."
            return;
          case DictationAction.dismissDraft:
            _input.clear();
            _dictated = null;
            notifier.dismissDraft();
            return;
          case DictationAction.fillComposer:
            break;
        }
        _input.text = result.text;
        _input.selection =
            TextSelection.collapsed(offset: result.text.length);
        _dictated = result.text;
      case VoiceOutcome.denied:
        _toast('Sakama needs microphone and speech access. Enable it in '
            'Settings to talk to Vita.');
      case VoiceOutcome.noOnDevice:
        // The platform refused rather than uploading the audio. Say that
        // plainly — it is a protection, not a malfunction.
        _toast('This phone cannot transcribe speech privately, so nothing was '
            'recorded. Type instead.');
      case VoiceOutcome.empty:
        _toast("Didn't catch that.");
      case VoiceOutcome.failed:
        _toast('Could not start the microphone.');
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Honesty on Android, where on-device recognition cannot be guaranteed and
  /// the platform will not tell us when it falls back. Shown before the first
  /// use and then remembered — nagging is not consent.
  Future<bool> _confirmAndroidVoice() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('About voice on Android'),
          // Re-worded when voice gained the ability to LOG. The old copy was
          // honest about a transcript that landed in a composer the user read
          // before sending; it is not honest about one that can commit a row.
          content: const Text(
              'Sakama asks Android to transcribe on your phone. On some '
              'devices Android uses its online service instead, which means '
              'what you say is sent to Google. We cannot tell which your '
              'phone does.\n\nWhen Vita has asked you to confirm something, '
              'saying "yes" logs it straight away.\n\nTyping always stays on '
              'your phone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Use voice')),
          ],
        ),
      ) ??
      false;

  /// Attach a photo and send it with whatever is typed as the question.
  Future<void> _sendPhoto() async {
    if (!await ensureAiConsent(context, ref)) return;
    final image = await captureJpegBase64();
    if (image == null || !mounted) return; // cancelled
    final caption = _input.text;
    _input.clear();
    await ref
        .read(coachControllerProvider.notifier)
        .sendPhoto(imageBase64: image, caption: caption);
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // #60: consent before sending the log + profile (incl. health conditions).
    if (!await ensureAiConsent(context, ref)) return;
    if (!mounted) return;
    // Speak only if this is EXACTLY what was dictated. See [_dictated].
    final spoken = _dictated != null && text.trim() == _dictated!.trim();
    _dictated = null;
    _input.clear();
    await ref.read(coachControllerProvider.notifier).send(text);
    if (spoken && mounted) await _speakLatestReply();
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Saved conversations. A sheet keeps the chat full-bleed and needs no route.
  Future<void> _showThreads() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _ThreadSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachControllerProvider);
    return Semantics(
      identifier: 'coach-page',
      // Tabs in the shell have no AppBar of their own, so nothing insets them
      // from the status bar — without this the thread icons sit under the
      // clock/battery. bottom:false: the shell's nav bar already insets the
      // bottom, and the input row has its own SafeArea(top: false).
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ThreadBar(
              onNew: () =>
                  ref.read(coachControllerProvider.notifier).newThread(),
              onHistory: _showThreads,
            ),
            Expanded(
              child: state.messages.isEmpty
                  ? const _Intro()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          state.messages.length + (state.sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == state.messages.length) return const _Typing();
                        return _Bubble(message: state.messages[i]);
                      },
                    ),
            ),
            if (state.pendingDrafts.isNotEmpty)
              _ConfirmCard(
                drafts: state.pendingDrafts,
                onConfirm: () =>
                    ref.read(coachControllerProvider.notifier).confirmDraft(),
                onDismiss: () =>
                    ref.read(coachControllerProvider.notifier).dismissDraft(),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Semantics(
                      identifier: 'coach-attach',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.add_a_photo_outlined),
                        tooltip: 'Send a photo',
                        onPressed: state.sending ? null : _sendPhoto,
                      ),
                    ),
                    Semantics(
                      identifier: 'coach-mic',
                      button: true,
                      child: GestureDetector(
                        // Long-press keeps plain dictation for anyone who wants
                        // words in the box rather than a conversation.
                        onLongPress: state.sending ? null : _dictate,
                        child: IconButton(
                        icon: Icon(_listening ? Icons.stop_circle_outlined
                                              : Icons.mic_none),
                        // Colour, not just a swapped glyph: a mic that is
                        // recording must be unmistakable at a glance.
                        color: _listening
                            ? Theme.of(context).colorScheme.error
                            : null,
                        tooltip: _listening ? 'Stop' : 'Talk to Vita',
                        onPressed: state.sending ? null : _openVoiceMode,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        identifier: 'coach-input',
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: const InputDecoration(
                            hintText: 'Ask Vita about your day…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      identifier: 'coach-send',
                      child: IconButton.filled(
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: state.sending ? null : _send,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty Coach screen.
///
/// A centred icon and two paragraphs left the screen almost blank and gave a
/// first-time user nothing to tap. It now leads with a bright hero — the
/// reference grammar — and offers the three questions people actually ask, as
/// pills that start the conversation.
class _Intro extends ConsumerWidget {
  const _Intro();

  static const _starters = [
    'What should I eat tonight?',
    "How's my protein today?",
    'Is dal chawal enough for dinner?',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.lg),
      children: [
        SkHero(
          identifier: 'coach-intro',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome, size: 28, color: SakamaPalette.onAccent),
              const SizedBox(height: Sk.md),
              Text('Ask Vita',
                  style: text.displaySmall?.copyWith(
                      color: SakamaPalette.onAccent,
                      fontSize: 40,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.6)),
              const SizedBox(height: Sk.sm),
              Text(
                'Your coach can see today\'s logs, your targets and your plan '
                '— so the answer is about your day, not a generic tip.',
                style: text.bodyMedium
                    ?.copyWith(color: SakamaPalette.onAccent.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
        const SkSection('Try asking'),
        for (final q in _starters)
          Padding(
            padding: const EdgeInsets.only(bottom: Sk.sm),
            child: SkCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sk.lg, vertical: Sk.md),
              // MUST gate on consent like every other send path. The
              // redesign added this tile calling send() directly, which would
              // have shipped the grounding snapshot — profile and health
              // CONDITIONS — without the consent #60/#62 exist to require.
              // A new entry point to an existing action inherits its gates.
              onTap: () async {
                if (!await ensureAiConsent(context, ref)) return;
                await ref.read(coachControllerProvider.notifier).send(q);
              },
              child: Row(
                children: [
                  Expanded(child: Text(q, style: text.bodyLarge)),
                  Icon(Icons.north_east,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CoachMessage message;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == CoachRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
          // 20 to match the card radius the refresh set; the 6dp tail corner
          // is what makes a bubble read as speech rather than as a card.
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isUser ? const Radius.circular(6) : null,
            bottomLeft: isUser ? null : const Radius.circular(6),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20).copyWith(
          bottomLeft: const Radius.circular(6),
        ),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// Slim header: start a new conversation, or open the saved ones.
class _ThreadBar extends StatelessWidget {
  const _ThreadBar({required this.onNew, required this.onHistory});
  final VoidCallback onNew;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Semantics(
            identifier: 'coach-history',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Saved chats',
              onPressed: onHistory,
            ),
          ),
          Semantics(
            identifier: 'coach-new-thread',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: 'New chat',
              onPressed: onNew,
            ),
          ),
        ],
      ),
    );
  }
}

/// The saved-conversation list. Tap to open, trash to delete.
class _ThreadSheet extends ConsumerWidget {
  const _ThreadSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(chatThreadsProvider);
    return Semantics(
      identifier: 'coach-thread-sheet',
      child: SafeArea(
        child: threads.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your chats: $e'),
          ),
          data: (rows) => rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No saved chats yet.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [for (final t in rows) _ThreadTile(thread: t)],
                ),
        ),
      ),
    );
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread});
  final ChatThreadRow thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: 'coach-thread-${thread.id}',
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Semantics(
          identifier: 'coach-thread-delete-${thread.id}',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref
                  .read(coachControllerProvider.notifier)
                  .deleteThread(thread.id);
            },
          ),
        ),
        onTap: () async {
          await ref
              .read(coachControllerProvider.notifier)
              .openThread(thread.id);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}

/// Vita PROPOSES; the user commits. Nothing is written until "Log it" is
/// tapped (ADR 0016 decision 2) — this card is the whole safety contract made
/// visible, so it states exactly what will be saved.
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.drafts,
    required this.onConfirm,
    required this.onDismiss,
  });

  /// A photo of a thali proposes several foods at once; a text tool call
  /// proposes one. Both render here.
  final List<ToolDraft> drafts;
  final VoidCallback onConfirm, onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'vita-confirm-card',
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final d in drafts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    d.summary,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    identifier: 'vita-confirm-dismiss',
                    button: true,
                    child: TextButton(
                      onPressed: onDismiss,
                      child: const Text('No thanks'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'vita-confirm-log',
                    button: true,
                    child: FilledButton(
                      onPressed: onConfirm,
                      child: const Text('Log it'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
