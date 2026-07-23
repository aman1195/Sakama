import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../foods/domain/food.dart';
import '../../home/domain/day_totals.dart';

/// Quick-add food logging (M1 manual entry + M2.1b corpus search).
///
/// Two paths share one form:
///  - SEARCH: pick a food from the reference corpus → enter grams → macros are
///    derived from the canonical per-100g values (CLAUDE.md) and prefilled.
///  - MANUAL: type a name + macros directly (the always-available fallback;
///    every tracker needs it for foods not yet in the corpus).
/// Photo / voice / barcode capture arrive in M2.3–M3.
class QuickAddPage extends ConsumerStatefulWidget {
  const QuickAddPage({super.key, this.initialMeal});

  /// Preselected slot when opened from a meal card's "+".
  final Meal? initialMeal;

  @override
  ConsumerState<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends ConsumerState<QuickAddPage> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _grams = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();
  late Meal _meal = widget.initialMeal ?? _defaultMeal();
  bool _saving = false;

  /// Set when a corpus food is picked; drives grams→macro derivation and the
  /// `loggedVia='search'` provenance. Cleared the moment the user edits the
  /// name by hand (it is no longer that food).
  Food? _picked;
  List<Food> _results = const [];
  int _searchToken = 0; // drops stale async results
  Timer? _debounce;

  /// Search fires one query per keystroke without this. Fine over the tiny
  /// local corpus, but the corpus is ~8k rows now and grows with OFF (2.3),
  /// so coalesce bursts of typing (issue #32).
  static const _debounceDelay = Duration(milliseconds: 250);

  static Meal _defaultMeal() {
    final h = DateTime.now().hour;
    if (h < 11) return Meal.breakfast;
    if (h < 16) return Meal.lunch;
    if (h < 21) return Meal.dinner;
    return Meal.snack;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_search, _name, _grams, _kcal, _protein, _carb, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      // Clearing the box should feel instant — nothing to coalesce.
      _searchToken++;
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(_debounceDelay, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final repo = await ref.read(foodRepositoryProvider.future);
    final results = await repo.search(q, limit: 8);
    if (!mounted || token != _searchToken) return; // a newer query superseded us
    setState(() => _results = results);
  }

  void _pick(Food food) {
    _picked = food;
    _name.text = food.name;
    _grams.text = (food.defaultServingGrams ?? 100).toStringAsFixed(0);
    _recomputeFromGrams();
    setState(() {
      _results = const [];
      _search.clear();
    });
    FocusScope.of(context).unfocus();
  }

  /// A hand edit to a nutrition field breaks the derived-from-food guarantee,
  /// so the log must record 'manual', not 'search'. Ignored while we are the
  /// ones writing those fields (see [_recomputeFromGrams]).
  void _dropPickedProvenance(String _) {
    if (_picked != null && !_deriving) setState(() => _picked = null);
  }

  bool _deriving = false;

  /// Derive the portion macros from the picked food's per-100g values.
  void _recomputeFromGrams() {
    final food = _picked;
    if (food == null) return;
    final grams = double.tryParse(_grams.text.trim()) ?? 0;
    final m = food.per100g.scaleTo(grams);
    _deriving = true; // our own writes must not look like a hand edit
    _kcal.text = m.energyKcal.toStringAsFixed(0);
    _protein.text = m.proteinG.toStringAsFixed(1);
    _carb.text = m.carbG.toStringAsFixed(1);
    _fat.text = m.fatG.toStringAsFixed(1);
    _deriving = false;
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
      grams: _picked == null ? null : double.tryParse(_grams.text.trim()),
      loggedVia: _picked == null ? 'manual' : 'search',
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
              // Corpus search — the primary path.
              Semantics(
                identifier: 'qa-search',
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    labelText: 'Search foods',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_results.isNotEmpty) _resultsList(),
              const SizedBox(height: 16),
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
              _field(_name, 'Food name', id: 'qa-name', required: true,
                  onChanged: (_) {
                // Hand-editing the name means it is no longer the picked food.
                if (_picked != null) setState(() => _picked = null);
              }),
              // Grams only matters for a picked food (drives derivation).
              if (_picked != null)
                _field(_grams, 'Amount (g)', id: 'qa-grams',
                    number: true, required: true, positive: true,
                    onChanged: (_) => _recomputeFromGrams()),
              // Hand-editing ANY nutrition value means the row no longer
              // equals scaleTo(grams) of the picked food, so it must not keep
              // that food's provenance (issue #32).
              _field(_kcal, 'Calories (kcal)', id: 'qa-kcal',
                  number: true, required: true, positive: true,
                  onChanged: _dropPickedProvenance),
              _field(_protein, 'Protein (g)', id: 'qa-protein', number: true,
                  onChanged: _dropPickedProvenance),
              _field(_carb, 'Carbs (g)', id: 'qa-carb', number: true,
                  onChanged: _dropPickedProvenance),
              _field(_fat, 'Fat (g)', id: 'qa-fat', number: true,
                  onChanged: _dropPickedProvenance),
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

  Widget _resultsList() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final food in _results)
            Semantics(
              identifier: 'qa-result-${food.id}',
              button: true,
              child: ListTile(
                dense: true,
                title: Text(food.name),
                subtitle: Text('${food.per100g.energyKcal.toStringAsFixed(0)} '
                    'kcal / 100 g · ${food.source}'),
                onTap: () => _pick(food),
              ),
            ),
        ],
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
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        identifier: id,
        child: TextFormField(
          controller: c,
          onChanged: onChanged,
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
