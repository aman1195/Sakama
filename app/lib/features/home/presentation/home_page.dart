import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/target_calculator.dart';
import '../domain/day_totals.dart';
import 'widgets/calorie_budget_ring.dart';
import 'widgets/macro_bars.dart';
import 'widgets/meal_slot_card.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Today's targets, derived from the onboarded profile. Null only if there is
/// no profile (the gate makes that unreachable in the shell, but handle it).
final targetsProvider = Provider<NutritionTargets?>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return null;
  return const TargetCalculator().targets(profile.toCalculatorInput(DateTime.now()));
});

/// Today's food logs, live.
final todayLogsProvider = StreamProvider<List<FoodLog>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.watchDay(_today());
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(targetsProvider);
    final logsAsync = ref.watch(todayLogsProvider);

    return Semantics(
      identifier: 'home-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Today')),
        // Debug-only sample entry so the dashboard has data before slice 5's
        // real search-logging exists. kDebugMode -> tree-shaken from release.
        floatingActionButton: kDebugMode
            ? Semantics(
                identifier: 'dev-add-log',
                child: FloatingActionButton(
                  onPressed: () => _addSample(ref),
                  child: const Icon(Icons.add),
                ),
              )
            : null,
        body: logsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (logs) {
            final totals = DayTotals.fromLogs(logs);
            final byMeal = groupByMeal(logs);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CalorieBudgetRing(
                    target: targets?.calories ?? 0,
                    eaten: totals.calories,
                  ),
                ),
                const SizedBox(height: 24),
                if (targets != null)
                  MacroBars(
                    proteinEaten: totals.proteinG,
                    proteinTarget: targets.proteinG,
                    carbEaten: totals.carbG,
                    carbTarget: targets.carbG,
                    fatEaten: totals.fatG,
                    fatTarget: targets.fatG,
                  ),
                const SizedBox(height: 16),
                for (final meal in Meal.values)
                  MealSlotCard(
                    meal: meal,
                    entries: byMeal[meal]!,
                    onAdd: () => context.go('/capture'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addSample(WidgetRef ref) async {
    final db = await ref.read(databaseProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;
    final meal = Meal.values[(now ~/ 1000) % Meal.values.length];
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: uuid.v4(),
          userId: Value(ref.read(currentUserIdProvider)),
          date: _today(),
          meal: meal.key,
          name: 'dal tadka',
          energyKcal: 180,
          proteinG: const Value(9),
          carbG: const Value(22),
          fatG: const Value(6),
          createdAt: now,
          updatedAt: now,
        ));
  }
}
