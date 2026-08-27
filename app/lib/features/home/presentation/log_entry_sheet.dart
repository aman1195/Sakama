import 'package:flutter/material.dart';

import '../../../app/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../domain/day_totals.dart';

/// What you logged, in full — and the only place to correct or remove it.
///
/// Until this existed a logged row was write-only: the dashboard showed a name
/// and a calorie count, and there was no way to see its macros, fix a wrong
/// estimate, or delete a mistake. `FoodLogRepository.delete` had no caller at
/// all.
class LogEntrySheet extends ConsumerStatefulWidget {
  const LogEntrySheet({required this.entry, super.key});
  final FoodLog entry;

  static Future<void> show(BuildContext context, FoodLog entry) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => LogEntrySheet(entry: entry),
      );

  @override
  ConsumerState<LogEntrySheet> createState() => _LogEntrySheetState();
}

class _LogEntrySheetState extends ConsumerState<LogEntrySheet> {
  late final _name = TextEditingController(text: widget.entry.name);
  late final _kcal =
      TextEditingController(text: widget.entry.energyKcal.round().toString());
  late final _protein =
      TextEditingController(text: widget.entry.proteinG.round().toString());
  late final _carb =
      TextEditingController(text: widget.entry.carbG.round().toString());
  late final _fat =
      TextEditingController(text: widget.entry.fatG.round().toString());
  late final _grams = TextEditingController(
      text: widget.entry.grams == null
          ? ''
          : widget.entry.grams!.round().toString());
  late Meal _meal = Meal.values.firstWhere((m) => m.key == widget.entry.meal,
      orElse: () => Meal.snack);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carb, _fat, _grams]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return; // symmetry with _delete (review #100)
    final kcal = double.tryParse(_kcal.text.trim());
    if (_name.text.trim().isEmpty || kcal == null || kcal <= 0) return;
    setState(() => _busy = true);
    final repo = await ref.read(foodLogRepositoryProvider.future);
    await repo.update(
      id: widget.entry.id,
      meal: _meal.key,
      name: _name.text.trim(),
      energyKcal: kcal,
      proteinG: double.tryParse(_protein.text.trim()) ?? 0,
      carbG: double.tryParse(_carb.text.trim()) ?? 0,
      fatG: double.tryParse(_fat.text.trim()) ?? 0,
      grams: double.tryParse(_grams.text.trim()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// A barcode row's macros came from Open Food Facts, so saving it here would
  /// write ODbL-derived nutrition into `user_foods` — the exact merge the
  /// pointer scheme exists to prevent (docs/architecture/08 §3).
  ///
  /// It cannot be saved as a POINTER either: `food_logs` keeps no `off_foods`
  /// id (see the table — name and macros only), so by the time a scan reaches
  /// this sheet the link to its source is already gone. Save at scan time
  /// instead, where the id still exists and a real pointer can be written.
  bool get _keepable => widget.entry.loggedVia != 'barcode';

  /// Keep this as a saved food. A logged row is already a portion, so it is
  /// stored as a CUSTOM food converted to the canonical per-100 g basis.
  ///
  /// Safe for every origin [_keepable] admits: manual and Vita rows are the
  /// user's own numbers, search rows are USDA (CC0) or our proprietary corpus,
  /// and PhotoSnap rows are our own AI estimate. Only OFF is excluded.
  Future<void> _keep() async {
    if (_busy || !_keepable) return;
    final kcal = double.tryParse(_kcal.text.trim());
    final grams = double.tryParse(_grams.text.trim());
    if (_name.text.trim().isEmpty || kcal == null || kcal <= 0) return;
    setState(() => _busy = true);
    final per100 = (grams != null && grams > 0) ? 100 / grams : 1.0;
    final repo = await ref.read(userFoodRepositoryProvider.future);
    await repo.addCustom(
      name: _name.text.trim(),
      energyKcal: kcal * per100,
      proteinG: (double.tryParse(_protein.text.trim()) ?? 0) * per100,
      carbG: (double.tryParse(_carb.text.trim()) ?? 0) * per100,
      fatG: (double.tryParse(_fat.text.trim()) ?? 0) * per100,
      servingGrams: grams,
      userId: ref.read(currentUserIdProvider),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "${_name.text.trim()}" to your foods.')));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.entry.name}?'),
        content: const Text('This takes it out of today\'s totals.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final repo = await ref.read(foodLogRepositoryProvider.future);
    await repo.delete(widget.entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'log-entry-sheet',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit entry',
                  style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 4),
              Text(_provenance(widget.entry.loggedVia),
                  style: text.bodySmall),
              const SizedBox(height: 16),
              Wrap(
                spacing: Sk.sm,
                runSpacing: Sk.sm,
                children: [
                  for (final m in Meal.values)
                    SkPill(
                      label: m.label,
                      selected: _meal == m,
                      onTap: () => setState(() => _meal = m),
                    ),
                ],
              ),
              const SizedBox(height: Sk.lg),
              _field('log-edit-name', _name, 'Food name'),
              _field('log-edit-grams', _grams, 'Grams (optional)',
                  number: true),
              _field('log-edit-kcal', _kcal, 'Calories (kcal)', number: true),
              Row(children: [
                Expanded(
                    child: _field('log-edit-protein', _protein, 'Protein (g)',
                        number: true)),
                const SizedBox(width: Sk.md),
                Expanded(
                    child: _field('log-edit-carb', _carb, 'Carbs (g)',
                        number: true)),
                const SizedBox(width: Sk.md),
                Expanded(
                    child:
                        _field('log-edit-fat', _fat, 'Fat (g)', number: true)),
              ]),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_keepable)
                    Semantics(
                      identifier: 'log-edit-keep',
                      button: true,
                      child: TextButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save food'),
                        onPressed: _busy ? null : _keep,
                      ),
                    ),
                  Semantics(
                    identifier: 'log-edit-delete',
                    button: true,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                      onPressed: _busy ? null : _delete,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    identifier: 'log-edit-save',
                    button: true,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String id, TextEditingController c, String label,
          {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          identifier: id,
          child: TextField(
            controller: c,
            keyboardType:
                number ? const TextInputType.numberWithOptions(decimal: true) : null,
            inputFormatters: number
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                : null,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
          ),
        ),
      );

  /// Where the row came from — the point of tagging provenance (rule 7) is that
  /// a user can see whether a number was measured, matched, or estimated.
  static String _provenance(String via) => switch (via) {
        'vita' => 'Logged by Vita from your chat',
        'photo' => 'From a photo estimate',
        'search' => 'Matched from the food database',
        'recent' => 'Repeated from a previous entry',
        'barcode' => 'Scanned barcode',
        'ai_estimate' => 'AI estimate',
        _ => 'Entered by hand',
      };
}
