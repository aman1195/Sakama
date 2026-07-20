import 'package:flutter/material.dart';

/// The hero of Home (DESIGN.md): target · eaten · remaining. Green while within
/// budget; amber once over — red is reserved for genuine problems, never a
/// calorie overshoot (PRODUCT.md "earn every color").
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
    final ringColor = over ? Colors.amber.shade700 : scheme.primary;

    return Semantics(
      identifier: 'calorie-budget-ring',
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 14,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(ringColor),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${remaining.abs().round()}',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(over ? 'kcal over' : 'kcal left'),
                const SizedBox(height: 4),
                Text('${eaten.round()} / $target',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
