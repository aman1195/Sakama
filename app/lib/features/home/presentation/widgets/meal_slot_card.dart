import 'package:flutter/material.dart';

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
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Filled once the meal has something in it; a faint tint
                    // while empty. Presence is legible before any text is read.
                    color: filled
                        ? scheme.primaryContainer
                        : scheme.onSurface.withValues(alpha: 0.06),
                  ),
                  child: Icon(_icons[meal],
                      size: 21,
                      color: filled
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface.withValues(alpha: 0.45)),
                ),
                title: Text(meal.label,
                    style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        // An empty slot recedes rather than shouting for
                        // attention — it is an invitation, not a failure.
                        color: filled
                            ? null
                            : scheme.onSurface.withValues(alpha: 0.65))),
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
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.only(left: 74, right: 20),
                    title: Text(e.name, overflow: TextOverflow.ellipsis),
                    trailing: Text('${e.energyKcal.round()} kcal',
                        // Tabular figures so a column of calories aligns on
                        // the decimal rather than shimmying per row.
                        style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    // A logged row was write-only until now: no macros, no fix,
                    // no delete. Tap opens the entry.
                    onTap: () => LogEntrySheet.show(context, e),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
