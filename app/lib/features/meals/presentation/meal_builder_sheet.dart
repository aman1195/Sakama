import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/kit/kit.dart';
import '../../../core/providers/app_providers.dart';
import '../domain/meal_item.dart';

/// Build a meal from saved foods: pick, set how many of each, name it.
///
/// Only SAVED foods can join a meal, and that is the licence design showing
/// through rather than a UI limitation: a meal stores `user_foods` ids and no
/// nutrition (docs/architecture/08 §3), so its members must be rows that
/// already live in `user_foods`. The sheet says so when there is nothing to
/// pick from, instead of presenting an empty void.
class MealBuilderSheet extends ConsumerStatefulWidget {
  const MealBuilderSheet({super.key});

  static Future<bool?> show(BuildContext context) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const MealBuilderSheet(),
      );

  @override
  ConsumerState<MealBuilderSheet> createState() => _MealBuilderSheetState();
}

class _MealBuilderSheetState extends ConsumerState<MealBuilderSheet> {
  final _name = TextEditingController();
  /// user_food id -> chosen quantity. Absent = not in the meal.
  final _picked = <String, double>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _picked.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(mealRepositoryProvider.future);
      await repo.create(
        name: name,
        items: [
          for (final e in _picked.entries)
            MealItem(userFoodId: e.key, servingQty: e.value),
        ],
        userId: ref.read(currentUserIdProvider),
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _step(String id, double delta) {
    final next = double.parse(((_picked[id] ?? 1) + delta).toStringAsFixed(1));
    if (next <= 0 || next > 100) return;
    setState(() => _picked[id] = next);
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final favs = ref.watch(favouriteFoodsProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.only(
          left: Sk.lg,
          right: Sk.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + Sk.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New meal',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('A group of your saved foods, logged together in one tap.',
              style: text.bodySmall),
          const SizedBox(height: Sk.lg),
          Semantics(
            identifier: 'meal-builder-name',
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Name (my usual breakfast)'),
            ),
          ),
          const SizedBox(height: Sk.md),
          if (favs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sk.lg),
              child: Text(
                'No saved foods yet. Save a food from any logged entry first — '
                'meals are built from your saved foods.',
                style: text.bodyMedium,
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in favs)
                    Semantics(
                      identifier: 'meal-builder-food-${f.row.id}',
                      child: Row(
                        children: [
                          Checkbox(
                            value: _picked.containsKey(f.row.id),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _picked[f.row.id] = 1;
                              } else {
                                _picked.remove(f.row.id);
                              }
                            }),
                          ),
                          Expanded(
                            child: Text(f.row.name,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium),
                          ),
                          if (_picked.containsKey(f.row.id)) ...[
                            IconButton(
                              iconSize: 18,
                              onPressed: () => _step(f.row.id, -0.5),
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Less',
                            ),
                            Text(_n(_picked[f.row.id]!),
                                style: text.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            IconButton(
                              iconSize: 18,
                              onPressed: () => _step(f.row.id, 0.5),
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'More',
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Sk.md),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              identifier: 'meal-builder-save',
              button: true,
              child: FilledButton(
                onPressed:
                    (_saving || _picked.isEmpty) ? null : _save,
                child: Text(_picked.isEmpty
                    ? 'Pick at least one food'
                    : 'Save meal (${_picked.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
