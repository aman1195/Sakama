import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/kit/kit.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/sync/sync_failure_repository.dart';

/// "Some entries didn't save" — shown only when the upload path has discarded
/// a write.
///
/// The alternative shipped for three weeks: the row vanished and nothing
/// anywhere said why. A count the user can see is the difference between a bug
/// they can report and one they conclude is their own fault.
class SyncFailureNotice extends ConsumerWidget {
  const SyncFailureNotice({super.key});

  /// The headline for [count] discarded writes, or null when there is nothing
  /// to report.
  ///
  /// Pulled out of build() so the rule is testable: a widget test of this
  /// deadlocks, because work scheduled under a widget test's fake clock never
  /// resumes on real database I/O. The rule is worth pinning anyway — "1
  /// entries didn't save" is the kind of detail that tells a user nobody
  /// looked at the screen.
  static String? title(int count) => switch (count) {
        <= 0 => null,
        1 => "1 entry didn't save",
        _ => "$count entries didn't save",
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(syncFailureCountProvider).value ?? 0;
    final headline = title(count);
    if (headline == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sk.md),
      child: Card(
        color: scheme.tertiaryContainer,
        child: Semantics(
          identifier: 'sync-failures-notice',
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined,
                color: scheme.onTertiaryContainer),
            title: Text(
              headline,
              style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600),
            ),
            // Plain about the consequence, without blame or alarm.
            subtitle: Text(
              'They were rejected by the server and are not in your history.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
            trailing: Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
            onTap: () => _show(context, ref),
          ),
        ),
      ),
    );
  }

  void _show(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final rows = ref.watch(syncFailuresProvider).value ?? const [];
          return Semantics(
            identifier: 'sync-failures-sheet',
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.xxl),
              children: [
                const SkTitle("Entries that didn't save"),
                const SizedBox(height: Sk.sm),
                Text(
                  'The server refused these writes, so they are not in your '
                  'history and re-opening the app will not bring them back. '
                  'This list is only on this phone.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Sk.lg),
                for (final r in rows)
                  Semantics(
                    identifier: 'sync-failure-${r.id}',
                    child: SkRow(
                      icon: Icons.error_outline,
                      title: SyncFailureRepository.describe(r),
                      // The code is what makes it diagnosable; the message is
                      // what makes it explicable.
                      subtitle: [r.code, r.message]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(' · '),
                    ),
                  ),
                const SizedBox(height: Sk.lg),
                FilledButton(
                  key: const Key('sync-failures-clear'),
                  onPressed: () async {
                    final repo =
                        await ref.read(syncFailureRepositoryProvider.future);
                    await repo.clear();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Clear this list'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
