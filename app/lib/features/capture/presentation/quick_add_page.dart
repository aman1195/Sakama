import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../meals/data/meal_log_service.dart';
import '../../meals/presentation/meal_builder_sheet.dart';
import '../../foods/data/ai_estimator.dart';
import '../../foods/data/user_food_repository.dart';
import '../../foods/domain/food.dart';
import '../../settings/presentation/ai_disclosure.dart';
import '../../home/domain/day_totals.dart';
import '../../plans/presentation/plan_log_notice_card.dart';

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

  /// Foods you have actually eaten, newest first. Loaded once on open; tapping
  /// one refills the form with the SAME portion you logged before.
  List<FoodLog> _recents = const [];

  /// True when the current form was filled from a recent entry and has not been
  /// hand-edited since — so the new row records where it really came from.
  bool _fromRecent = false;

  /// Same, for a saved food; [_favouriteId] lets the save bump its use count so
  /// most-used ordering reflects reality.
  bool _fromFavourite = false;
  String? _favouriteId;
  List<Food> _results = const [];

  /// The query that produced zero results — shows the AI-estimate offer.
  String? _noResultQuery;
  bool _estimating = false;
  String? _estimateError;
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
  void initState() {
    super.initState();
    unawaited(_loadRecents());
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
      setState(() {
        _results = const [];
        _noResultQuery = null;
        _estimateError = null;
      });
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
    if (!mounted || token != _searchToken) {
      return; // a newer query superseded us
    }
    setState(() {
      _results = results;
      _noResultQuery = results.isEmpty ? q : null;
      _estimateError = null;
    });
  }

  Future<void> _estimate() async {
    final dish = _noResultQuery;
    if (dish == null || _estimating) return;
    // #60: consent before sending the dish name to the AI provider.
    if (!await ensureAiConsent(context, ref)) return;
    if (!mounted) return;
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      // Anonymous-first: if startup was offline, grab the session now.
      await ref.read(authServiceProvider).ensureSession();
      final byok = await ref.read(byokStoreProvider).read();
      final estimator = ref.read(aiEstimatorProvider);
      final estimate = await estimator.estimate(dish, byok: byok);
      // Persist with ai_estimate provenance so it is findable next time, then
      // flow into the normal picked-food path (grams -> derived macros).
      final foodRepo = await ref.read(foodRepositoryProvider.future);
      final food = await foodRepo.saveEstimate(estimate, query: dish);
      if (!mounted) return;
      _pick(food);
      if (estimate.assumptions != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI estimate — assumed: ${estimate.assumptions}'),
          ),
        );
      }
    } on EstimateException catch (e) {
      if (mounted) {
        setState(
          () => _estimateError = e.budgetExhausted
              ? 'Daily AI limit reached. Add your own key in Me → Your own AI key to go unlimited, or enter it manually.'
              : e.notFood
              ? "That doesn't look like a food. Try a different name."
              : 'Could not estimate right now. Enter it manually below.',
        );
      }
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _loadRecents() async {
    final repo = await ref.read(foodLogRepositoryProvider.future);
    final rows = await repo.recentDistinct();
    if (mounted) setState(() => _recents = rows);
  }

  /// Log a saved food at YOUR portion. A pointer's nutrition is per 100 g and
  /// scales by the saved grams; a missing source leaves the numbers blank for
  /// the user to complete rather than logging a silent zero.
  Future<void> _pickFavourite(ResolvedUserFood f) async {
    _picked = null;
    _fromRecent = false;
    _fromFavourite = true;
    _favouriteId = f.row.id;
    _name.text = f.row.name;
    final grams = f.row.servingGrams;
    _grams.text = grams == null ? '' : grams.toStringAsFixed(0);
    if (f.energyKcal != null && grams != null) {
      final k = grams / 100;
      _kcal.text = (f.energyKcal! * k).toStringAsFixed(0);
      _protein.text = ((f.proteinG ?? 0) * k).toStringAsFixed(0);
      _carb.text = ((f.carbG ?? 0) * k).toStringAsFixed(0);
      _fat.text = ((f.fatG ?? 0) * k).toStringAsFixed(0);
    } else {
      // Source gone, or no saved portion: let the user fill it in.
      for (final c in [_kcal, _protein, _carb, _fat]) {
        c.clear();
      }
    }
    setState(() {
      _results = const [];
      _search.clear();
    });
    FocusScope.of(context).unfocus();
  }

  /// Re-log something you have eaten before. Unlike [_pick] (a per-100g corpus
  /// row that must be scaled by grams), a recent entry is ALREADY the portion
  /// you ate, so its totals are copied across verbatim.
  void _pickRecent(FoodLog r) {
    _picked = null; // not a corpus food; provenance is 'recent'
    _fromRecent = true;
    _name.text = r.name;
    _grams.text = r.grams == null ? '' : r.grams!.toStringAsFixed(0);
    _kcal.text = r.energyKcal.toStringAsFixed(0);
    _protein.text = r.proteinG.toStringAsFixed(0);
    _carb.text = r.carbG.toStringAsFixed(0);
    _fat.text = r.fatG.toStringAsFixed(0);
    final meal = Meal.values.where((m) => m.key == r.meal).firstOrNull;
    setState(() {
      if (meal != null) _meal = meal;
      _results = const [];
      _search.clear();
    });
    FocusScope.of(context).unfocus();
  }

  /// Save a corpus food as a POINTER: source + your portion, never a copy of
  /// the nutrition. `addPointer` takes no nutrition arguments, so this path
  /// cannot carry licensed values into the synced table even by mistake.
  Future<void> _keepPicked() async {
    final food = _picked;
    if (food == null) return;
    final repo = await ref.read(userFoodRepositoryProvider.future);
    await repo.addPointer(
      name: food.name,
      sourceTable: UserFoodRepository.sourceFoods,
      sourceId: food.id,
      servingLabel: food.defaultServingLabel,
      servingGrams: double.tryParse(_grams.text.trim()),
      userId: ref.read(currentUserIdProvider),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "${food.name}" to your foods.')));
  }

  /// Saved meals: the whole group in one tap, into the currently selected
  /// slot. The chip row above is the contract — what is selected is where it
  /// lands, no hidden default.
  Widget _mealsStrip() {
    final meals = ref.watch(savedMealsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkSection('Meals'),
        Wrap(
          spacing: Sk.sm,
          runSpacing: Sk.sm,
          children: [
            for (final m in meals)
              SkPill(
                identifier: 'qa-meal-${m.id}',
                icon: Icons.lunch_dining,
                label: m.name,
                onTap: () => _logMeal(m),
              ),
            SkPill(
              identifier: 'qa-meal-new',
              icon: Icons.add,
              label: 'New meal',
              onTap: () => MealBuilderSheet.show(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _logMeal(MealRow m) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final service = MealLogService(
        meals: await ref.read(mealRepositoryProvider.future),
        userFoods: await ref.read(userFoodRepositoryProvider.future),
        foodLogs: await ref.read(foodLogRepositoryProvider.future),
      );
      final r = await service.log(m,
          date: _today(),
          mealSlot: _meal.key,
          userId: ref.read(currentUserIdProvider));
      if (!mounted) return;
      // Say what actually happened. "Logged breakfast" when one of its three
      // foods was skipped leaves the user certain they ate what they did not.
      final msg = r.logged == 0
          ? 'Nothing logged — the foods in "${m.name}" could not be resolved.'
          : 'Logged ${m.name}: ${r.logged} '
              '${r.logged == 1 ? "food" : "foods"}, ~${r.kcal.round()} kcal'
              '${r.skipped > 0 ? " · ${r.skipped} skipped" : ""}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Foods you chose to keep — including ones that fell out of the recency
  /// window, and ones that exist in no corpus at all.
  Widget _favouritesStrip() {
    final favs = ref.watch(favouriteFoodsProvider).value ?? const [];
    if (favs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A HEADING. Unlabelled pills floating under a search box told the
        // user nothing about what they were or why they were there.
        const SkSection('Saved foods'),
        Wrap(
          spacing: Sk.sm,
          runSpacing: Sk.sm,
          children: [
            for (final f in favs)
              SkPill(
                identifier: 'qa-favourite-${f.row.id}',
                icon: Icons.bookmark,
                label: f.row.name,
                onTap: () => _pickFavourite(f),
              ),
          ],
        ),
      ],
    );
  }

  Widget _recentsStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkSection('Logged recently'),
        Wrap(
          spacing: Sk.sm,
          runSpacing: Sk.sm,
          children: [
            for (final r in _recents)
              SkPill(
                identifier: 'qa-recent-${r.id}',
                icon: Icons.history,
                label: '${r.name} · ${r.energyKcal.round()} kcal',
                onTap: () => _pickRecent(r),
              ),
          ],
        ),
      ],
    );
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
    if (_fromRecent && !_deriving) _fromRecent = false;
    if (_fromFavourite && !_deriving) _fromFavourite = false;
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
    try {
      final repo = await ref.read(foodLogRepositoryProvider.future);
      final name = _name.text.trim();
      await repo.add(
        date: _today(),
        meal: _meal.key,
        name: name,
        energyKcal: double.parse(_kcal.text),
        proteinG: double.tryParse(_protein.text) ?? 0,
        carbG: double.tryParse(_carb.text) ?? 0,
        fatG: double.tryParse(_fat.text) ?? 0,
        grams: (_picked == null && !_fromRecent && !_fromFavourite)
            ? null
            : double.tryParse(_grams.text.trim()),
        loggedVia: _picked != null
            ? 'search'
            : (_fromFavourite ? 'saved' : (_fromRecent ? 'recent' : 'manual')),
        userId: ref.read(currentUserIdProvider),
      );
      if (_fromFavourite && _favouriteId != null) {
        final foods = await ref.read(userFoodRepositoryProvider.future);
        await foods.markUsed(_favouriteId!);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      // Pushed as /add -> pop back. As the LOG TAB root there is nothing to
      // pop — maybePop returns false — so reset for the next entry instead.
      // (Device dogfood round 4: the old code assumed the pop always worked,
      // leaving _saving stuck true on the tab — 'Log it' permanently disabled
      // after the first save.)
      final popped = await Navigator.of(context).maybePop();
      if (!popped && mounted) _resetForm();
      messenger.showSnackBar(SnackBar(content: Text('Logged $name')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Clear everything for the next entry (tab context, where the page stays).
  void _resetForm() {
    _formKey.currentState?.reset();
    for (final c in [_search, _name, _grams, _kcal, _protein, _carb, _fat]) {
      c.clear();
    }
    setState(() {
      _picked = null;
      _results = const [];
      _noResultQuery = null;
      _estimateError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.isNotEmpty;
    return Semantics(
      identifier: 'quick-add-page',
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.xxl),
              children: [
                SkTitle('Add food', trailing: [
                  SkCircleAction(
                      identifier: 'qa-snap',
                      icon: Icons.photo_camera_outlined,
                      label: 'PhotoSnap',
                      size: 40,
                      onTap: () => context.push('/snap')),
                  const SizedBox(width: Sk.sm),
                  SkCircleAction(
                      identifier: 'qa-scan',
                      icon: Icons.qr_code_scanner,
                      label: 'Scan barcode',
                      size: 40,
                      onTap: () => context.push('/scan')),
                ]),
                const PlanLogNoticeCard(),
                // Search is the PRIMARY path and now looks like it: a single
                // prominent field, not one input among seven.
                Semantics(
                  identifier: 'qa-search',
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: Theme.of(context).textTheme.titleMedium,
                    decoration: const InputDecoration(
                      hintText: 'Search dal, roti, paneer…',
                      prefixIcon: Icon(Icons.search),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: Sk.lg, vertical: 18),
                    ),
                  ),
                ),
                if (_results.isNotEmpty) _resultsList(),
                // Strips get HEADINGS now. Unlabelled floating pills were the
                // worst thing on this screen — no way to know what they were.
                if (!searching && _results.isEmpty) _mealsStrip(),
                if (!searching && _results.isEmpty) _favouritesStrip(),
                if (!searching && _results.isEmpty && _recents.isNotEmpty)
                  _recentsStrip(),
                if (_noResultQuery != null && _results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Sk.md),
                    child: SkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No match for "$_noResultQuery"',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Vita can estimate it from the name.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                          const SizedBox(height: Sk.md),
                          Semantics(
                            identifier: 'qa-estimate',
                            child: FilledButton.icon(
                              icon: _estimating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.auto_awesome, size: 18),
                              label: Text(
                                  _estimating ? 'Estimating…' : 'Estimate it'),
                              onPressed: _estimating ? null : _estimate,
                            ),
                          ),
                          if (_estimateError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Sk.sm),
                              child: Semantics(
                                identifier: 'qa-estimate-error',
                                child: Text(_estimateError!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SkSection('Which meal?'),
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
                // The form is the FALLBACK, so it reads as one grouped block
                // rather than as seven equal inputs competing with search.
                const SkSection('Details'),
                SkCard(
                  child: Column(
                    children: [
                      _field(_name, 'Food name',
                          id: 'qa-name', required: true, onChanged: (_) {
                        if (_picked != null) setState(() => _picked = null);
                      }),
                      if (_picked != null)
                        _field(_grams, 'Amount (g)',
                            id: 'qa-grams',
                            number: true,
                            required: true,
                            positive: true,
                            onChanged: (_) => _recomputeFromGrams()),
                      _field(_kcal, 'Calories (kcal)',
                          id: 'qa-kcal',
                          number: true,
                          required: true,
                          positive: true,
                          onChanged: _dropPickedProvenance),
                      Row(children: [
                        Expanded(
                            child: _field(_protein, 'Protein (g)',
                                id: 'qa-protein',
                                number: true,
                                onChanged: _dropPickedProvenance)),
                        const SizedBox(width: Sk.md),
                        Expanded(
                            child: _field(_carb, 'Carbs (g)',
                                id: 'qa-carb',
                                number: true,
                                onChanged: _dropPickedProvenance)),
                        const SizedBox(width: Sk.md),
                        Expanded(
                            child: _field(_fat, 'Fat (g)',
                                id: 'qa-fat',
                                number: true,
                                onChanged: _dropPickedProvenance)),
                      ]),
                      if (_picked != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Semantics(
                            identifier: 'qa-keep-food',
                            button: true,
                            child: TextButton.icon(
                              icon: const Icon(Icons.bookmark_add_outlined,
                                  size: 18),
                              label: const Text('Save this food'),
                              onPressed: _keepPicked,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Sk.xl),
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
                subtitle: Text(
                  '${food.per100g.energyKcal.toStringAsFixed(0)} '
                  'kcal / 100 g · ${food.source}',
                ),
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
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
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
