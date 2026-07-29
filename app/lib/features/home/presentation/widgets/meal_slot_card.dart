import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';
import '../../domain/day_totals.dart';

/// One meal slot (Breakfast/Lunch/Dinner/Snack) with its entries + a "+".
///
/// Visual pass: the HealthifyMe scannable-row pattern — a leading tinted icon
/// circle giving each meal a stable identity, one hero fact (kcal), one action.
class MealSlotCard extends StatelessWidget {
  const MealSlotCard({
    super.key,
    required this.meal,
    required this.entries,
    this.onAdd,
  });

  final Meal meal;
  final List<FoodLog> entries;
  final VoidCallback? onAdd;

  static const _icons = {
    Meal.breakfast: Icons.wb_twilight_outlined,
    Meal.lunch: Icons.wb_sunny_outlined,
    Meal.dinner: Icons.nightlight_outlined,
    Meal.snack: Icons.cookie_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final kcal = entries.fold<double>(0, (a, e) => a + e.energyKcal);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'meal-${meal.key}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.25),
                        width: 1.5),
                  ),
                  child: Icon(_icons[meal], size: 21, color: scheme.primary),
                ),
                title: Text(meal.label,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  entries.isEmpty
                      ? 'Nothing yet'
                      : '${kcal.round()} kcal · ${entries.length} '
                          '${entries.length == 1 ? 'item' : 'items'}',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                trailing: Semantics(
                  identifier: 'meal-${meal.key}-add',
                  child: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: scheme.primary,
                    onPressed: onAdd,
                  ),
                ),
              ),
              for (final e in entries)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.only(left: 74, right: 20),
                  title: Text(e.name, overflow: TextOverflow.ellipsis),
                  trailing: Text('${e.energyKcal.round()} kcal',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
