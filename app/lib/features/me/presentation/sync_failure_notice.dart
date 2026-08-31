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
            onTap: () => _show(context),
          ),
        ),
      ),
    );
  }

  /// Clearing is DESTRUCTIVE, and not obviously so.
  ///
  /// The row itself was reconciled off the device when the op was dropped, so
  /// the payload on the receipt is the last copy of that entry. A button that
  /// reads like dismissing a notification would quietly end the recovery story
  /// this table exists for, and on a build that cannot be hotfixed. So it
  /// confirms, and names what goes.
  Future<void> _confirmClear(
      BuildContext context, WidgetRef ref, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the list?'),
        content: Text(count == 1
            ? 'This is the only remaining copy of that entry. Clearing it '
                'deletes it for good.'
            : 'These are the only remaining copies of those $count entries. '
                'Clearing them deletes them for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = await ref.read(syncFailureRepositoryProvider.future);
    await repo.clear();
    if (context.mounted) Navigator.of(context).pop();
  }

  void _show(BuildContext context) {
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
                for (final (i, r) in rows.indexed)
                  Semantics(
                    // Positional and stable: the row id is PowerSync's op id,
                    // which no driver or test can know in advance.
                    identifier: 'sync-failure-$i',
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
                Semantics(
                  identifier: 'sync-failures-clear',
                  child: FilledButton(
                    onPressed: () => _confirmClear(context, ref, rows.length),
                    child: const Text('Clear this list'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
