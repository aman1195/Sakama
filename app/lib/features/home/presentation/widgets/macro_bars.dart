import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class MacroBars extends StatelessWidget {
  const MacroBars({
    super.key,
    required this.proteinEaten,
    required this.proteinTarget,
    required this.carbEaten,
    required this.carbTarget,
    required this.fatEaten,
    required this.fatTarget,
  });

  final double proteinEaten, carbEaten, fatEaten;
  final int proteinTarget, carbTarget, fatTarget;

  @override
  Widget build(BuildContext context) {
    final c = context.sakamaColors;
    return Semantics(
      identifier: 'macro-bars',
      child: Column(
        children: [
          _bar(context, 'Protein', proteinEaten, proteinTarget, c.protein),
          _bar(context, 'Carbs', carbEaten, carbTarget, c.carbs),
          _bar(context, 'Fat', fatEaten, fatTarget, c.fat),
        ],
      ),
    );
  }

  /// Each macro keeps ONE identity color app-wide (recognition, not
  /// decoration) — and a macro colour is NEVER a status colour, so a glance
  /// can always tell "this is fat" from "this is going badly".
  ///
  /// These bars sit ON the status-coloured hero card, so everything that is
  /// not a macro identity — labels, numbers, the unfilled track — is drawn
  /// from the INHERITED on-colour. Drawing them from the scheme (as this did
  /// before SAK-126) left grey-on-lime text and an invisible track.
  Widget _bar(
      BuildContext context, String label, double eaten, int target, Color color) {
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    final over = target > 0 && eaten > target;
    final scheme = Theme.of(context).colorScheme;
    final ink = DefaultTextStyle.of(context).style.color ?? scheme.onSurface;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              // Over is carried by WEIGHT, not by a second status colour: the
              // card behind it already says how the day is going, and a second
              // amber here would be the same message shouted twice.
              Text('${eaten.round()} / ${target}g',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ink.withValues(alpha: over ? 1.0 : 0.7),
                        fontWeight: over ? FontWeight.w700 : FontWeight.w500,
                      )),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOutQuart,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: color,
                backgroundColor: ink.withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
