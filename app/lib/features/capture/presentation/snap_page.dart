import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/snap_draft.dart';
import '../domain/snap_flow.dart';
import 'snap_controller.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// PhotoSnap: point at a meal → AI lists the foods → confirm portions → log.
/// The camera itself is image_picker (a modal capture UI); this page owns the
/// analyzing / confirm / error states.
class SnapPage extends ConsumerStatefulWidget {
  const SnapPage({super.key});
  @override
  ConsumerState<SnapPage> createState() => _SnapPageState();
}

class _SnapPageState extends ConsumerState<SnapPage> {
  @override
  void initState() {
    super.initState();
    // Fire the camera immediately — the whole point is "snap", not a menu.
    WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
  }

  Future<void> _snap() async {
    final ctl = ref.read(snapControllerProvider.notifier);
    await ctl.snap();
    // If the user backed out of the camera before taking a photo, leave.
    if (mounted && ref.read(snapControllerProvider) is SnapIdle) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(snapControllerProvider);
    return Semantics(
      identifier: 'snap-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('PhotoSnap')),
        body: switch (state) {
          SnapIdle() || SnapAnalyzing() => const _Analyzing(),
          SnapReady(:final drafts) => _ConfirmList(drafts: drafts),
          SnapNoFood() => _Retry(
              id: 'snap-no-food',
              icon: Icons.no_food_outlined,
              text: "That doesn't look like food. Try another photo, or add "
                  'it manually.',
              onRetry: _snap),
          SnapBudgetExhausted() => _Retry(
              id: 'snap-budget',
              icon: Icons.timer_outlined,
              text: "You've used today's photo estimates. They reset tomorrow "
                  '— or add your own AI key (Me → Your own AI key) to go '
                  'unlimited.',
              onRetry: null),
          SnapError() => _Retry(
              id: 'snap-error',
              icon: Icons.wifi_off,
              text: "Couldn't read that photo. Check your connection and try "
                  'again, or add it manually.',
              onRetry: _snap),
          SnapPermissionDenied() => _Retry(
              id: 'snap-permission',
              icon: Icons.no_photography_outlined,
              text: 'Sakama needs camera access to read your meal. Enable it '
                  'in Settings, or add your food manually.',
              onRetry: _snap),
        },
      ),
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading your plate…'),
          ],
        ),
      );
}

class _ConfirmList extends ConsumerStatefulWidget {
  const _ConfirmList({required this.drafts});
  final List<SnapDraft> drafts;
  @override
  ConsumerState<_ConfirmList> createState() => _ConfirmListState();
}

class _ConfirmListState extends ConsumerState<_ConfirmList> {
  bool _saving = false;

  double get _totalKcal => widget.drafts
      .where((d) => d.keep)
      .fold(0, (a, d) => a + d.energyKcal);

  Future<void> _log() async {
    setState(() => _saving = true);
    try {
      final n =
          await ref.read(snapControllerProvider.notifier).logKept(_today());
      if (!mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 1 ? 'Logged 1 item' : 'Logged $n items')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final keptCount = widget.drafts.where((d) => d.keep).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('We found these', style: text.titleMedium),
              Text('AI estimate — tap to adjust',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: widget.drafts.length,
            itemBuilder: (context, i) => _DraftTile(
              index: i,
              draft: widget.drafts[i],
              onChanged: () => setState(() {}),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              identifier: 'snap-log',
              child: FilledButton(
                onPressed: (_saving || keptCount == 0) ? null : _log,
                child: Text(keptCount == 0
                    ? 'Nothing selected'
                    : 'Log $keptCount ${keptCount == 1 ? 'item' : 'items'} · '
                        '${_totalKcal.round()} kcal'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile(
      {required this.index, required this.draft, required this.onChanged});
  final int index; // for a stable, collision-free semantics id (review #57)
  final SnapDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'snap-item-$index',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Opacity(
          opacity: draft.keep ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(draft.item.name,
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600))),
                    Semantics(
                      identifier: 'snap-item-$index-keep',
                      child: Checkbox(
                        value: draft.keep,
                        onChanged: (v) {
                          draft.keep = v ?? true;
                          onChanged();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('${draft.item.portionLabel} · ',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    Text('${draft.grams.round()} g',
                        style: text.bodySmall),
                    const Spacer(),
                    Text(
                      '${draft.energyKcal.round()} kcal · '
                      'P ${draft.proteinG.round()} · '
                      'C ${draft.carbG.round()} · F ${draft.fatG.round()}',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (draft.keep)
                  Semantics(
                    identifier: 'snap-item-$index-grams',
                    child: Builder(builder: (context) {
                      // Max adapts so a large portion isn't silently pinned
                      // (review #57): headroom above the current grams.
                      final max = (((draft.grams / 100).ceil() + 1) * 100)
                          .clamp(600, 2000)
                          .toDouble();
                      return Slider(
                        value: draft.grams.clamp(10, max),
                        min: 10,
                        max: max,
                        onChanged: (v) {
                          draft.grams = v.roundToDouble();
                          onChanged();
                        },
                      );
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry(
      {required this.id,
      required this.icon,
      required this.text,
      required this.onRetry});
  final String id, text;
  final IconData icon;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          identifier: id,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44),
                const SizedBox(height: 12),
                Text(text, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (onRetry != null)
                  FilledButton(
                      onPressed: onRetry, child: const Text('Take another')),
                TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back')),
              ],
            ),
          ),
        ),
      );
}
