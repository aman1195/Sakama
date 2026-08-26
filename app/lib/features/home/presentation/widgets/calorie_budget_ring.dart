import 'package:flutter/material.dart';

/// The hero of Home (DESIGN.md): target · eaten · remaining.
///
/// The ring now sits ON a status-coloured surface (StatusSurface), so it no
/// longer carries the state itself — the card does. Its job is contrast
/// against whatever fill it lands on, which is why the track and sweep are
/// drawn from the inherited on-colour rather than from the scheme: a
/// scheme-primary ring on a lime card would vanish.
///
/// Visual pass: the remaining number is the single hero (one big number per
/// card — the HealthifyMe pattern), the ring sweeps in with an ease-out curve
/// (state reveal, 250ms — product register), and honors reduced motion.
class CalorieBudgetRing extends StatelessWidget {
  const CalorieBudgetRing({
    super.key,
    required this.target,
    required this.eaten,
  });

  final int target;
  final double eaten;

  @override
  Widget build(BuildContext context) {
    final remaining = target - eaten;
    final over = remaining < 0;
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Inherited from StatusSurface's DefaultTextStyle so the ring reads on
    // any status fill. Falls back to scheme.primary off a status surface.
    final onSurface = DefaultTextStyle.of(context).style.color ?? scheme.primary;
    final ringColor = onSurface;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      identifier: 'calorie-budget-ring',
      child: SizedBox(
        width: 208,
        height: 208,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 208,
              height: 208,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOutQuart,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 14,
                  strokeCap: StrokeCap.round,
                  // A translucent version of the same ink, so the unfilled
                  // track never fights the card colour.
                  backgroundColor: onSurface.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ONE hero number. Everything else is subordinate.
                Text(
                  '${remaining.abs().round()}',
                  style: text.displayMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
                Text(over ? 'kcal over' : 'kcal left',
                    style: text.bodyMedium?.copyWith(
                        color: over ? Colors.amber.shade700 : null)),
                const SizedBox(height: 6),
                Text('${eaten.round()} of $target eaten',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
