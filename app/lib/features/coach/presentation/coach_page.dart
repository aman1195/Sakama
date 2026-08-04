import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../settings/presentation/ai_disclosure.dart';
import '../domain/coach_message.dart';
import '../domain/tool_draft.dart';
import 'coach_controller.dart';

/// Vita — the coach tab. A persistent chat grounded in today's real data.
class CoachPage extends ConsumerStatefulWidget {
  const CoachPage({super.key});
  @override
  ConsumerState<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends ConsumerState<CoachPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // #60: consent before sending the log + profile (incl. health conditions).
    if (!await ensureAiConsent(context, ref)) return;
    if (!mounted) return;
    _input.clear();
    await ref.read(coachControllerProvider.notifier).send(text);
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
            if (state.pendingDraft != null)
              _ConfirmCard(
                draft: state.pendingDraft!,
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

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Hi, I'
              "'"
              'm Vita',
              style: text.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Your coach. I can see today'
              "'"
              's logs and targets — ask me '
              '"what should I eat tonight?" or "how'
              "'"
              's my protein?"',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
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
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: isUser ? null : const Radius.circular(4),
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
        borderRadius: BorderRadius.circular(16),
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
    required this.draft,
    required this.onConfirm,
    required this.onDismiss,
  });
  final ToolDraft draft;
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
              Text(
                draft.summary,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
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
