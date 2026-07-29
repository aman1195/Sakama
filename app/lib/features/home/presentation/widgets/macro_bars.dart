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
  /// decoration). Amber only when genuinely over target.
  Widget _bar(
      BuildContext context, String label, double eaten, int target, Color color) {
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    final over = target > 0 && eaten > target;
    final scheme = Theme.of(context).colorScheme;
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
              Text('${eaten.round()} / ${target}g',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: over
                          ? Colors.amber.shade700
                          : scheme.onSurfaceVariant)),
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
                color: over ? Colors.amber.shade700 : color,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
