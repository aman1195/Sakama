import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Warm first-run/empty state for a day with no logs — teaches the interface
/// with ONE clear action instead of a blank list ("empty states that teach",
/// product register). Assetless: a tilted trio of tinted icon tiles.
class EmptyDayCard extends StatelessWidget {
  const EmptyDayCard({super.key, required this.onLog});

  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.sakamaColors;
    final text = Theme.of(context).textTheme;
    Widget tile(IconData icon, Color color, double angle) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 72,
            height: 88,
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.softTint, scheme.surface),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
        );
    return Semantics(
      identifier: 'empty-day',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              SizedBox(
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                        offset: const Offset(-52, 6),
                        child: tile(Icons.local_drink_outlined, c.water, -0.16)),
                    Transform.translate(
                        offset: const Offset(52, 6),
                        child: tile(Icons.monitor_weight_outlined, c.fat, 0.16)),
                    tile(Icons.restaurant_outlined, scheme.primary, 0),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Nothing logged yet', style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Log your first meal and Sakama starts adding up your day.',
                textAlign: TextAlign.center,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'empty-day-log',
                child: FilledButton.icon(
                  onPressed: onLog,
                  icon: const Icon(Icons.add),
                  label: const Text('Log a meal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
