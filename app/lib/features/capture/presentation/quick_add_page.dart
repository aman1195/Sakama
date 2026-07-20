import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../home/domain/day_totals.dart';

/// Quick-add manual food logging (M1). Photo / voice / barcode / DB-search
/// capture come with M2–M3; this is the type-it-in path, which every tracker
/// needs as the fallback. Reachable from the Log tab and the meal-slot "+".
class QuickAddPage extends ConsumerStatefulWidget {
  const QuickAddPage({super.key, this.initialMeal});

  /// Preselected slot when opened from a meal card's "+".
  final Meal? initialMeal;

  @override
  ConsumerState<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends ConsumerState<QuickAddPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();
  late Meal _meal = widget.initialMeal ?? _defaultMeal();
  bool _saving = false;

  static Meal _defaultMeal() {
    final h = DateTime.now().hour;
    if (h < 11) return Meal.breakfast;
    if (h < 16) return Meal.lunch;
    if (h < 21) return Meal.dinner;
    return Meal.snack;
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carb, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = await ref.read(foodLogRepositoryProvider.future);
    await repo.add(
      date: _today(),
      meal: _meal.key,
      name: _name.text.trim(),
      energyKcal: double.parse(_kcal.text),
      proteinG: double.tryParse(_protein.text) ?? 0,
      carbG: double.tryParse(_carb.text) ?? 0,
      fatG: double.tryParse(_fat.text) ?? 0,
      userId: ref.read(currentUserIdProvider),
    );
    if (mounted) {
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logged ${_name.text.trim()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'quick-add-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Add food')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Meal slot.
              SegmentedButton<Meal>(
                segments: [
                  for (final m in Meal.values)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_meal},
                onSelectionChanged: (s) => setState(() => _meal = s.first),
              ),
              const SizedBox(height: 16),
              _field(_name, 'Food name', id: 'qa-name', required: true),
              _field(_kcal, 'Calories (kcal)', id: 'qa-kcal',
                  number: true, required: true, positive: true),
              _field(_protein, 'Protein (g)', id: 'qa-protein', number: true),
              _field(_carb, 'Carbs (g)', id: 'qa-carb', number: true),
              _field(_fat, 'Fat (g)', id: 'qa-fat', number: true),
              const SizedBox(height: 24),
              Semantics(
                identifier: 'qa-save',
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Log it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    required String id,
    bool number = false,
    bool required = false,
    bool positive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        identifier: id,
        child: TextFormField(
          controller: c,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration:
              InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: (v) {
            final t = (v ?? '').trim();
            if (required && t.isEmpty) return 'Required';
            if (t.isEmpty) return null;
            if (number) {
              final n = double.tryParse(t);
              if (n == null) return 'Enter a number';
              if (positive && n <= 0) return 'Must be greater than 0';
              if (n > 100000) return 'Too large';
            }
            return null;
          },
        ),
      ),
    );
  }
}
