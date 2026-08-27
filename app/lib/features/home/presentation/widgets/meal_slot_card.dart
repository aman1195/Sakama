import 'package:flutter/material.dart';

import '../../../../app/kit/kit.dart';
import '../../../../core/db/database.dart';
import '../../domain/day_totals.dart';
import '../log_entry_sheet.dart';

/// One meal slot (Breakfast/Lunch/Dinner/Snack) with its entries + a "+".
///
/// Visual pass: the HealthifyMe scannable-row pattern — a leading tinted icon
/// circle giving each meal a stable identity, one hero fact (kcal), one action.
///
/// SAK-126: the icon circle is now a FILLED accent chip rather than an
/// outlined ring, matching the reference apps' merchant-avatar rows, and an
/// empty slot is visibly quieter than a filled one. A day with three meals
/// logged and one empty should look different at arm's length — that is the
/// entire job of a list like this.
/// One meal slot inside the Meals card: a chip-anchored row per meal, with
/// its entries nested under it.
///
/// No longer its own Card — five stacked cards read as five unrelated things.
/// It is a row in a single grouped surface now, which is how the reference
/// apps present a transaction list.
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
    final filled = entries.isNotEmpty;

    return Semantics(
      identifier: 'meal-${meal.key}',
      child: Column(
        children: [
          SkRow(
            icon: _icons[meal]!,
            title: meal.label,
            subtitle: filled
                ? '${kcal.round()} kcal · ${entries.length} '
                    '${entries.length == 1 ? "item" : "items"}'
                : 'Nothing yet',
            // An empty slot recedes: untinted chip, so a filled day is legible
            // at arm's length.
            tint: filled ? null : scheme.onSurface.withValues(alpha: 0.06),
            trailing: Semantics(
              identifier: 'meal-${meal.key}-add',
              button: true,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: onAdd,
              ),
            ),
          ),
          for (final e in entries)
            Semantics(
              identifier: 'log-entry-${e.id}',
              button: true,
              child: InkWell(
                onTap: () => LogEntrySheet.show(context, e),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(70, 4, Sk.lg, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.name,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium),
                      ),
                      Text('${e.energyKcal.round()} kcal',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
