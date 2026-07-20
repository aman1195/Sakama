import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';
import '../../domain/day_totals.dart';

/// One meal slot (Breakfast/Lunch/Dinner/Snack) with its entries + a "+".
/// The "+" routes to capture in slice 5; here it invokes [onAdd].
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

  @override
  Widget build(BuildContext context) {
    final kcal = entries.fold<double>(0, (a, e) => a + e.energyKcal);
    return Semantics(
      identifier: 'meal-${meal.key}',
      child: Card(
        child: Column(
          children: [
            ListTile(
              title: Text(meal.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${kcal.round()} kcal'),
              trailing: Semantics(
                identifier: 'meal-${meal.key}-add',
                child: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: onAdd,
                ),
              ),
            ),
            for (final e in entries)
              ListTile(
                dense: true,
                title: Text(e.name),
                trailing: Text('${e.energyKcal.round()} kcal'),
              ),
          ],
        ),
      ),
    );
  }
}
