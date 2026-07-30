import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/coach_message.dart';
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
    _input.clear();
    await ref.read(coachControllerProvider.notifier).send(text);
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachControllerProvider);
    return Semantics(
      identifier: 'coach-page',
      child: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const _Intro()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == state.messages.length) return const _Typing();
                      return _Bubble(message: state.messages[i]);
                    },
                  ),
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
            Text('Hi, I'"'"'m Vita', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Your coach. I can see today'"'"'s logs and targets — ask me '
              '"what should I eat tonight?" or "how'"'"'s my protein?"',
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
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: isUser ? null : const Radius.circular(4),
          ),
        ),
        child: Text(message.content,
            style: TextStyle(
                color: isUser ? scheme.onPrimary : scheme.onSurface)),
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
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}
