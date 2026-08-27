import 'package:flutter/material.dart';

import '../../../app/kit/kit.dart';
import '../../../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../coach/presentation/coach_controller.dart';

import '../../settings/presentation/ai_disclosure.dart';
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
    // #60: consent before the camera opens — PhotoSnap sends the photo off
    // device. Declining leaves the page without taking a picture.
    if (!await ensureAiConsent(context, ref)) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (!mounted) return;
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
          SnapProviderDown() => _Retry(
              id: 'snap-provider-down',
              icon: Icons.cloud_off_outlined,
              text: 'Our food AI is unavailable right now. This is on our side, '
                  'not your connection — please try again later, or add your '
                  'food manually.',
              onRetry: null),
          SnapSignInFailed() => _Retry(
              id: 'snap-signin-failed',
              icon: Icons.person_off_outlined,
              text: "Couldn't sign in, so we can't read your photo. Check your "
                  'connection and try again, or add it manually.',
              onRetry: _snap),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Sk.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SkTitle('PhotoSnap'),
            SkHero(
              identifier: 'snap-analyzing',
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: SakamaPalette.onAccent),
                  ),
                  const SizedBox(height: Sk.lg),
                  Text('Reading your plate',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: SakamaPalette.onAccent,
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          )),
                  const SizedBox(height: 6),
                  Text('Finding each dish and estimating the portions.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SakamaPalette.onAccent
                              .withValues(alpha: 0.75))),
                ],
              ),
            ),
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
    final keptCount = widget.drafts.where((d) => d.keep).length;
    return Column(
      children: [
        // The result gets a hero too: the total is the number the user is
        // deciding on, so it should be the largest thing on the screen rather
        // than buried in the button label.
        Padding(
          padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SkTitle('On your plate'),
              SkHero(
                identifier: 'snap-total',
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI ESTIMATE · TAP ANY ITEM TO ADJUST',
                              style: text.labelSmall?.copyWith(
                                color: SakamaPalette.onAccent
                                    .withValues(alpha: 0.65),
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 4),
                          Text('${_totalKcal.round()}',
                              style: text.displaySmall?.copyWith(
                                color: SakamaPalette.onAccent,
                                fontSize: 46,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -2,
                              )),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          'kcal · $keptCount of ${widget.drafts.length}',
                          style: text.labelLarge?.copyWith(
                              color: SakamaPalette.onAccent
                                  .withValues(alpha: 0.75))),
                    ),
                  ],
                ),
              ),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  identifier: 'snap-log',
                  child: FilledButton(
                    onPressed: (_saving || keptCount == 0) ? null : _log,
                    child: Text(keptCount == 0
                        ? 'Nothing selected'
                        : 'Log $keptCount ${keptCount == 1 ? 'item' : 'items'} · '
                            '${_totalKcal.round()} kcal'),
                  ),
                ),
                // Second entry point into photo-chat (design §4). This path has
                // ALREADY paid for vision, so it hands the extracted items over
                // as text — no second vision call, no second photo charge (§5).
                Semantics(
                  identifier: 'snap-ask-vita',
                  button: true,
                  child: TextButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Ask Vita about this'),
                    onPressed: _saving ? null : () => _askVita(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension _AskVita on _ConfirmListState {
  /// Hand the ALREADY-extracted items to the coach as text (design §5): this
  /// path has paid for vision once, so it runs an ordinary Vita turn — one
  /// exchange, no second vision call, no second photo charge.
  Future<void> _askVita(BuildContext context) async {
    // Hand over the REAL items (macros + grams), not a name-and-kcal summary:
    // if the user then says they ate it, the whole meal must be loggable
    // accurately rather than re-derived from prose.
    final items = widget.drafts.map((d) => d.item).toList();
    context.go('/coach'); // switch first so the reply lands in view
    await ref
        .read(coachControllerProvider.notifier)
        .handoffFromPhotoSnap(items);
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Sk.lg),
        child: Column(
          children: [
            const SkTitle('PhotoSnap'),
            SkCard(
              padding: EdgeInsets.zero,
              child: SkEmpty(
                identifier: id,
                icon: icon,
                title: _headline,
                body: text,
                actionLabel: onRetry != null ? 'Take another' : null,
                onAction: onRetry,
              ),
            ),
            const SizedBox(height: Sk.md),
            TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back')),
          ],
        ),
      );

  /// A short headline above the explanation. The old states were one grey
  /// paragraph under a grey icon, which read as an error even when the answer
  /// was mundane ("that is not food").
  String get _headline => switch (id) {
        'snap-no-food' => 'That does not look like food',
        'snap-budget' => "Today's photo estimates are used up",
        'snap-provider-down' => 'The AI service is unavailable',
        'snap-signin' => 'Could not sign in',
        'snap-permission' => 'Camera access is off',
        _ => 'Something went wrong',
      };
}
