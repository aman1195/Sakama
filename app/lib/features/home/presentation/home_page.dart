import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../app/kit/kit.dart';
import '../../../app/status_surface.dart';
import 'widgets/today_hero.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/current_date_provider.dart';
import '../../onboarding/domain/nutrition_targets.dart';
import '../../onboarding/domain/target_calculator.dart';
import '../../plans/application/plan_providers.dart';
import '../../water/presentation/water_chip.dart';
import '../domain/day_totals.dart';
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
    final date = ref.watch(currentDateProvider);

    return Semantics(
      identifier: 'home-page',
      child: Scaffold(
        // No AppBar: the reference apps put the title inline with the content
        // and give the hero the top of the screen. A 56dp bar above a bright
        // card wastes the most valuable space on the phone.
        body: SafeArea(
          bottom: false,
          child: logsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (logs) {
              final totals = DayTotals.fromLogs(logs);
              final byMeal = groupByMeal(logs);
              return ListView(
                padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.xxl),
                children: [
                  SkTitle(_greeting(date), trailing: [
                    SkCircleAction(
                      identifier: 'home-history',
                      icon: Icons.calendar_today_outlined,
                      label: 'Diary',
                      size: 40,
                      onTap: () => context.go('/diary'),
                    ),
                  ]),
                  TodayHero(
                    status: ref.watch(statusColourEnabledProvider)
                        ? trackStatus(
                            value: totals.calories,
                            target: (targets?.calories ?? 0).toDouble(),
                          )
                        : TrackStatus.muted,
                    target: targets?.calories ?? 0,
                    eaten: totals.calories,
                    actions: [
                      SkCircleAction(
                          identifier: 'hero-snap',
                          icon: Icons.photo_camera_outlined,
                          label: 'Snap a photo',
                          onTap: () => context.push('/snap')),
                      SkCircleAction(
                          identifier: 'hero-add',
                          icon: Icons.add,
                          label: 'Add food',
                          onTap: () => context.push('/add')),
                      SkCircleAction(
                          identifier: 'hero-scan',
                          icon: Icons.qr_code_scanner,
                          label: 'Scan a barcode',
                          onTap: () => context.push('/scan')),
                      SkCircleAction(
                          identifier: 'hero-coach',
                          icon: Icons.auto_awesome_outlined,
                          label: 'Ask Vita',
                          onTap: () => context.go('/coach')),
                    ],
                    macros: targets == null
                        ? null
                        : MacroRow(
                            protein: totals.proteinG,
                            proteinTarget: targets.proteinG,
                            carbs: totals.carbG,
                            carbTarget: targets.carbG,
                            fat: totals.fatG,
                            fatTarget: targets.fatG,
                          ),
                  ),
                  if (targets != null) ...[
                    const SizedBox(height: Sk.md),
                    WaterChip(targetMl: targets.waterMl),
                  ],
                  const SkSection('Meals'),
                  if (logs.isEmpty)
                    SkCard(
                      padding: EdgeInsets.zero,
                      child: SkEmpty(
                        identifier: 'empty-day',
                        icon: Icons.restaurant_outlined,
                        title: 'Nothing logged yet',
                        body: 'Snap a photo, scan a barcode, or add it by hand '
                            '— whichever is fastest right now.',
                        actionLabel: 'Log your first meal',
                        onAction: () => context.push('/add'),
                      ),
                    )
                  else
                    SkCard(
                      padding: const EdgeInsets.symmetric(vertical: Sk.sm),
                      child: Column(
                        children: [
                          for (final meal in Meal.values)
                            MealSlotCard(
                              meal: meal,
                              entries: byMeal[meal]!,
                              onAdd: () =>
                                  context.push('/add?meal=${meal.key}'),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// A greeting instead of "Today". The reference apps lead with the person,
  /// not with the noun for the screen.
  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
