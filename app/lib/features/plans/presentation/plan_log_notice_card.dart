import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/home_page.dart' show planTargetsOverriddenProvider;
import '../application/plan_providers.dart';
import '../domain/plan_log_notice.dart';

/// A gentle, non-blocking reminder shown on the food-logging screen when an
/// active plan has something to flag right now: the clock is outside the eating
/// window, and/or the day asks the user to avoid certain foods. Never prevents
/// logging — it informs (offline-first, user autonomy). Renders nothing when
/// there is no active plan or nothing to say.
class PlanLogNoticeCard extends ConsumerWidget {
  const PlanLogNoticeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice =
        PlanLogNotice.forDay(ref.watch(activePlanDayProvider), DateTime.now());
    // The plan's rules still apply on a day whose NUMBERS were refused, so this
    // card has something to say even when the notice itself is empty.
    final overridden = ref.watch(planTargetsOverriddenProvider);
    if (notice == null && !overridden) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[
      // First: without it the rest of the card describes a plan whose target is
      // not the one being counted against, and nothing says so.
      if (overridden)
        "Today's plan target was below a safe minimum, so your usual target is "
            'in force. The rest of the plan still applies.',
      if (notice != null && notice.outsideWindow)
        'Outside your eating window (${notice.windowStart}–${notice.windowEnd}). '
            'You can still log — just a heads-up.',
      if (notice != null && notice.avoidFoods.isNotEmpty)
        'Your plan asks you to avoid today: ${notice.avoidFoods.join(', ')}.',
    ];

    return Semantics(
      identifier: 'plan-log-notice',
      child: Card(
        color: scheme.tertiaryContainer,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: line == lines.last ? 0 : 6),
                        child: Text(line,
                            style: TextStyle(color: scheme.onTertiaryContainer)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
