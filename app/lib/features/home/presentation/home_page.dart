import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/current_date_provider.dart';
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/target_calculator.dart';
import '../../plans/application/plan_providers.dart';
import '../../water/presentation/water_chip.dart';
import '../domain/day_totals.dart';
import 'widgets/calorie_budget_ring.dart';
import 'widgets/empty_day_card.dart';
import 'widgets/macro_bars.dart';
import 'widgets/meal_slot_card.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's targets. Base = the computed maintenance targets from the onboarded
/// profile; when an active plan is in force, its day-type targets overlay that
/// base (each field the plan leaves silent falls back to computed — the last
/// link in the plan engine's day type → targets_default → computed chain).
/// Null only if there is no profile (the gate makes that unreachable in the
/// shell, but handle it).
final targetsProvider = Provider<NutritionTargets?>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return null;
  final computed =
      const TargetCalculator().targets(profile.toCalculatorInput(DateTime.now()));
  final planDay = ref.watch(activePlanDayProvider);
  return planDay == null
      ? computed
      : planDay.targets.toNutritionTargets(computed);
});

/// Today's food logs, live. The date comes from [currentDateProvider], so the
/// dashboard rolls over to the new day at midnight (review #70).
final todayLogsProvider = StreamProvider<List<FoodLog>>((ref) async* {
  final ymd = _ymd(ref.watch(currentDateProvider));
  final db = await ref.watch(databaseProvider.future);
  yield* db.watchDay(ymd);
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
        floatingActionButton: Semantics(
          identifier: 'home-photosnap',
          child: FloatingActionButton.extended(
            onPressed: () => context.push('/snap'),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Snap'),
          ),
        ),
        body: logsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (logs) {
            final totals = DayTotals.fromLogs(logs);
            final byMeal = groupByMeal(logs);
            // Ring + macros belong together — one "today" card, one hero
            // number (visual pass SAK-37, HealthifyMe structure).
            return ListView(
              // Extra bottom inset so the FAB never sits on the last meal
              // card's "+" (seen in the eyes-on pass).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      children: [
                        CalorieBudgetRing(
                          target: targets?.calories ?? 0,
                          eaten: totals.calories,
                        ),
                        if (targets != null) ...[
                          const SizedBox(height: 20),
                          MacroBars(
                            proteinEaten: totals.proteinG,
                            proteinTarget: targets.proteinG,
                            carbEaten: totals.carbG,
                            carbTarget: targets.carbG,
                            fatEaten: totals.fatG,
                            fatTarget: targets.fatG,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (targets != null) WaterChip(targetMl: targets.waterMl),
                const SizedBox(height: 20),
                // Empty day: the teaching card REPLACES the four empty
                // slots (review #53 — card + four "Nothing yet" rows was
                // redundant). Slots appear from the first log onward.
                if (logs.isEmpty)
                  EmptyDayCard(onLog: () => context.push('/add'))
                else
                  for (final meal in Meal.values) ...[
                    MealSlotCard(
                      meal: meal,
                      entries: byMeal[meal]!,
                      onAdd: () => context.push('/add?meal=${meal.key}'),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

}
