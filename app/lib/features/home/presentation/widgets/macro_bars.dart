import 'package:flutter/material.dart';

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
    return Semantics(
      identifier: 'macro-bars',
      child: Column(
        children: [
          _bar(context, 'Protein', proteinEaten, proteinTarget),
          _bar(context, 'Carbs', carbEaten, carbTarget),
          _bar(context, 'Fat', fatEaten, fatTarget),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, String label, double eaten, int target) {
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${eaten.round()} / ${target}g',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
        ],
      ),
    );
  }
}
