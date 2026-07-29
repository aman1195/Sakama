import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../home/domain/day_totals.dart';
import '../domain/barcode_result.dart';
import '../domain/food.dart';

/// Resolves a scanned barcode and, on a hit, lets the user pick an amount and
/// log it. Deliberately camera-FREE so the whole resolve→confirm→log path is
/// unit-testable; [ScanPage] supplies the barcode from the camera.
class ScanResultView extends ConsumerWidget {
  const ScanResultView({super.key, required this.barcode, this.onDone});

  final String barcode;

  /// Called after a successful log or a dismiss, so the scanner can resume.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(barcodeLookupProvider(barcode));
    return Semantics(
      identifier: 'scan-result',
      // A resolved-but-failed lookup is `data` (a BarcodeResult), not `error`;
      // the only real error/loading here is the DB/provider plumbing.
      child: async.when(
        loading: () => const _Padded(
            child: Center(child: CircularProgressIndicator())),
        error: (e, _) => _Message(
            id: 'scan-offline',
            icon: Icons.error_outline,
            text: 'Something went wrong. Try again or add the food manually.',
            onDone: onDone),
        data: (result) => switch (result) {
          BarcodeFound(:final food) => _ConfirmForm(food: food, onDone: onDone),
          BarcodeNotFound() => _Message(
              id: 'scan-not-found',
              icon: Icons.help_outline,
              text: 'No product found for this barcode — common for Indian '
                  'products, our packaged-food data is still growing.',
              // The dead-end was reported twice in dogfood (#51): hand back
              // to Quick-Add, where search + the AI-estimate offer take over.
              // pop(), not pushReplacement: /scan is only ever entered FROM
              // Quick-Add, so popping returns to the origin page without
              // stacking a duplicate (review #54 nit).
              action: ('Add it manually', () => context.pop()),
              onDone: onDone),
          BarcodeRateLimited() => _Message(
              id: 'scan-rate-limited',
              icon: Icons.timer_outlined,
              text: 'Too many scans just now. Try again in a moment.',
              onDone: onDone),
          BarcodeOffline() => _Message(
              id: 'scan-offline',
              icon: Icons.wifi_off,
              text: 'Could not reach the food database. Check your connection '
                  'and try again — or add it manually.',
              onDone: onDone),
        },
      ),
    );
  }
}

class _ConfirmForm extends ConsumerStatefulWidget {
  const _ConfirmForm({required this.food, this.onDone});
  final Food food;
  final VoidCallback? onDone;

  @override
  ConsumerState<_ConfirmForm> createState() => _ConfirmFormState();
}

class _ConfirmFormState extends ConsumerState<_ConfirmForm> {
  late final _grams = TextEditingController(
      text: (widget.food.defaultServingGrams ?? 100).toStringAsFixed(0));
  late Meal _meal = _defaultMeal();
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
    _grams.dispose();
    super.dispose();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final grams = double.tryParse(_grams.text.trim());
    if (grams == null || grams <= 0) return;
    setState(() => _saving = true);
    final m = widget.food.per100g.scaleTo(grams);
    final repo = await ref.read(foodLogRepositoryProvider.future);
    await repo.add(
      date: _today(),
      meal: _meal.key,
      name: widget.food.name,
      energyKcal: m.energyKcal,
      proteinG: m.proteinG,
      carbG: m.carbG,
      fatG: m.fatG,
      grams: grams,
      loggedVia: 'barcode',
      userId: ref.read(currentUserIdProvider),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logged ${widget.food.name}')));
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final text = Theme.of(context).textTheme;
    final grams = double.tryParse(_grams.text.trim()) ?? 0;
    final m = f.per100g.scaleTo(grams);
    return _Padded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.name, style: text.titleLarge),
          Text('${f.per100g.energyKcal.toStringAsFixed(0)} kcal / 100 g',
              style: text.bodySmall),
          const SizedBox(height: 16),
          SegmentedButton<Meal>(
            segments: [
              for (final mm in Meal.values)
                ButtonSegment(value: mm, label: Text(mm.label)),
            ],
            selected: {_meal},
            onSelectionChanged: (s) => setState(() => _meal = s.first),
          ),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'scan-grams',
            child: TextField(
              controller: _grams,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Amount (g)', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          Text('${m.energyKcal.toStringAsFixed(0)} kcal · '
              'P ${m.proteinG.toStringAsFixed(1)} · '
              'C ${m.carbG.toStringAsFixed(1)} · '
              'F ${m.fatG.toStringAsFixed(1)}'),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'scan-log',
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Log it'),
            ),
          ),
          const SizedBox(height: 12),
          // ODbL §4.3: attribution on each public use of the data, not just in
          // Settings. Costs nothing and is the stronger position (#44).
          Text(
            'Product data from Open Food Facts, under the Open Database Licence '
            '(ODbL).',
            style: text.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.id,
      required this.icon,
      required this.text,
      this.action,
      this.onDone});
  final String id, text;
  final IconData icon;
  /// Optional primary action (label, handler) shown above "Scan again".
  final (String, VoidCallback)? action;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return _Padded(
      child: Semantics(
        identifier: id,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (action != null)
              Semantics(
                identifier: '$id-action',
                child: FilledButton(
                    onPressed: action!.$2, child: Text(action!.$1)),
              ),
            TextButton(
                onPressed: onDone, child: const Text('Scan again')),
          ],
        ),
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: child,
      );
}
