import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';

/// Everything Vita has learned, with a way to delete any of it.
///
/// This screen is a REQUIREMENT, not a feature (ADR 0016 decision 10). Memory
/// silently steers every reply, so a user who cannot see it cannot tell why
/// the coach is behaving as it is, and a user who cannot delete it has no way
/// to correct a wrong inference about their own health.
///
/// Deletion is the only correction offered. Free-text editing would make a
/// user-authored fact indistinguishable from an extracted one, and the
/// provenance we keep would become a lie.
class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    final async = ref.watch(memoryFactsProvider);
    final text = Theme.of(context).textTheme;

    return Semantics(
      identifier: 'memory-page',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('What Vita remembers'),
          actions: [
            if ((async.value ?? const []).isNotEmpty)
              Semantics(
                identifier: 'memory-reset',
                button: true,
                child: TextButton(
                  onPressed: () => _reset(context, ref, uid),
                  child: const Text('Forget all'),
                ),
              ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Could not read memory.')),
          data: (facts) => facts.isEmpty
              ? _empty(context)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Vita learns from your chats to give better advice. This '
                      'stays on your phone and is never uploaded. Delete '
                      'anything that is wrong and Vita will stop using it.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final f in facts) _tile(context, ref, f),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.psychology_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                "Vita hasn't learned anything yet. Chat about your food, "
                'habits or goals and what matters will show up here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );

  Widget _tile(BuildContext context, WidgetRef ref, MemoryFact f) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          identifier: 'memory-fact-${f.id}',
          child: ListTile(
            title: Text(f.content),
            subtitle: Text(_label(f.kind)),
            trailing: Semantics(
              identifier: 'memory-forget-${f.id}',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Forget this',
                // No manual refresh: watchAll is a Drift stream and re-emits
                // on write. Invalidating would tear the stream down and
                // rebuild it for no benefit.
                onPressed: () async {
                  final repo = await ref.read(memoryRepositoryProvider.future);
                  await repo.forget(f.id);
                },
              ),
            ),
          ),
        ),
      );

  Future<void> _reset(BuildContext context, WidgetRef ref, String? uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget everything?'),
        content: const Text(
            'Vita will start over and will not remember your preferences, '
            'goals or restrictions. Your food logs and chats are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Forget all')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = await ref.read(memoryRepositoryProvider.future);
    final n = await repo.forgetAll(uid);
    if (!context.mounted) return;
    // Concrete, not "Done": a silent success is indistinguishable from a
    // failure, and this is the one action the user cannot undo.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'There was nothing to forget.'
            : 'Vita forgot $n thing${n == 1 ? '' : 's'}.')));
  }

  /// Plain words. "constraint" is jargon; "Something you avoid" is not.
  static String _label(String kind) => switch (kind) {
        'constraint' => 'Something you avoid',
        'goal' => 'A goal',
        'routine' => 'A habit',
        'preference' => 'Something you like',
        'observation' => 'Noticed',
        _ => 'Noted',
      };
}
