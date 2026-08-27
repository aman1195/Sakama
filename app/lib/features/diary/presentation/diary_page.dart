import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/kit/kit.dart';
import '../../../app/status_surface.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/current_date_provider.dart';
import '../../home/domain/day_totals.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../home/presentation/log_entry_sheet.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/workout_set.dart';

/// How far back the Diary looks. Four weeks is enough to see a pattern and
/// small enough that the whole window is one query and one build.
const _windowDays = 28;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _diaryLogsProvider = StreamProvider<List<FoodLog>>((ref) async* {
  final from = ref.watch(currentDateProvider)
      .subtract(const Duration(days: _windowDays));
  final repo = await ref.watch(foodLogRepositoryProvider.future);
  yield* repo.watchSince(_ymd(from));
});

final _diaryWorkoutsProvider = StreamProvider<List<WorkoutRow>>((ref) async* {
  final from = ref.watch(currentDateProvider)
      .subtract(const Duration(days: _windowDays));
  final repo = await ref.watch(workoutRepositoryProvider.future);
  yield* repo.watchSince(_ymd(from));
});

/// Your history: one row per day, newest first.
///
/// This screen did not exist — it rendered the word "Diary" in the middle of
/// an empty page. What it needed to answer is the question a tracker exists
/// for and a single day cannot show: *what does my week actually look like?*
class DiaryPage extends ConsumerWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_diaryLogsProvider);
    // Workouts share the day rows rather than getting their own screen: a day
    // is one thing that happened, not two parallel logs.
    final workouts = ref.watch(_diaryWorkoutsProvider).value ?? const [];
    final targets = ref.watch(targetsProvider);
    final today = ref.watch(currentDateProvider);

    return Semantics(
      identifier: 'diary-page',
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (logs) {
              final byDay = <String, List<FoodLog>>{};
              for (final l in logs) {
                (byDay[l.date] ??= []).add(l);
              }
              final workoutsByDay = <String, List<WorkoutRow>>{};
              for (final w in workouts) {
                (workoutsByDay[w.date] ??= []).add(w);
              }
              // A day with only a workout still deserves a row. Keying off
              // food alone would hide the gym session of someone who did not
              // log lunch.
              final days = {...byDay.keys, ...workoutsByDay.keys}.toList()
                ..sort((a, b) => b.compareTo(a));

              return ListView(
                padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.xxl),
                children: [
                  const SkTitle('Diary'),
                  if (days.isEmpty)
                    SkCard(
                      padding: EdgeInsets.zero,
                      child: const SkEmpty(
                        identifier: 'diary-empty',
                        icon: Icons.event_note_outlined,
                        title: 'No history yet',
                        body: 'Once you log a few days, this is where the '
                            'pattern shows up — which days you hit your '
                            'targets and which you did not.',
                      ),
                    )
                  else ...[
                    _Summary(
                      days: byDay.keys.toList(),
                      byDay: byDay,
                      target: targets?.calories ?? 0,
                    ),
                    const SkSection('Every day'),
                    SkCard(
                      padding: const EdgeInsets.symmetric(vertical: Sk.sm),
                      child: Column(
                        children: [
                          for (final d in days)
                            _DayRow(
                              ymd: d,
                              entries: byDay[d] ?? const [],
                              workouts: workoutsByDay[d] ?? const [],
                              target: targets?.calories ?? 0,
                              isToday: d == _ymd(today),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The window at a glance — the thing a per-day list cannot tell you.
class _Summary extends StatelessWidget {
  const _Summary(
      {required this.days, required this.byDay, required this.target});

  /// FOOD days only. A workout-only day must not enter this as a 0 kcal
  /// entry: it would drag the average down and count as a day logged.
  final List<String> days;
  final Map<String, List<FoodLog>> byDay;
  final int target;

  @override
  Widget build(BuildContext context) {
    final totals = [
      for (final d in days) DayTotals.fromLogs(byDay[d] ?? const []).calories
    ];
    final avg = totals.isEmpty
        ? 0.0
        : totals.reduce((a, b) => a + b) / totals.length;
    // "On target" counts days within the band, not days under it. Under-eating
    // is not success, and a tracker that scores it as such teaches the wrong
    // thing.
    final onTarget = target <= 0
        ? 0
        : totals.where((t) => t >= target * 0.85 && t <= target * 1.05).length;

    return SkHero(
      identifier: 'diary-summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAST ${days.length} DAYS LOGGED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: SakamaPalette.onAccent.withValues(alpha: 0.6),
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: Sk.md),
          Row(
            children: [
              Expanded(
                child: SkStat(
                    value: avg.round().toString(),
                    label: 'AVERAGE',
                    sub: 'kcal a day',
                    color: SakamaPalette.onAccent),
              ),
              Expanded(
                child: SkStat(
                    value: target <= 0 ? '—' : '$onTarget',
                    label: 'ON TARGET',
                    sub: 'days in range',
                    color: SakamaPalette.onAccent),
              ),
              Expanded(
                child: SkStat(
                    value: days.length.toString(),
                    label: 'LOGGED',
                    sub: 'of $_windowDays days',
                    color: SakamaPalette.onAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.ymd,
    required this.entries,
    required this.workouts,
    required this.target,
    required this.isToday,
  });

  final String ymd;
  final List<FoodLog> entries;
  final List<WorkoutRow> workouts;
  final int target;
  final bool isToday;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Food first, then movement, and only what exists. A day with a workout
  /// and no food must not read "0 kcal · 0 items".
  String _subtitle(int kcal) {
    final parts = <String>[];
    if (entries.isNotEmpty) {
      parts.add('$kcal kcal${target > 0 ? " of $target" : ""}');
      parts.add('${entries.length} ${entries.length == 1 ? "item" : "items"}');
    }
    if (workouts.isNotEmpty) {
      final burn = WorkoutRepository.dayBurn(workouts);
      final n = workouts.length;
      // The burn is only shown when we actually computed one. "0 kcal burned"
      // for three logged lifts would be a lie by rounding.
      parts.add(burn.kcal > 0
          ? '$n ${n == 1 ? "workout" : "workouts"} · ${burn.kcal.round()} kcal out'
          : '$n ${n == 1 ? "workout" : "workouts"}');
    }
    return parts.isEmpty ? 'Nothing logged' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final totals = DayTotals.fromLogs(entries);
    final d = DateTime.parse(ymd);
    final label = isToday
        ? 'Today'
        : '${d.day} ${_months[d.month - 1]}';
    final status = trackStatus(
        value: totals.calories, target: target.toDouble());

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: Sk.lg),
      childrenPadding: const EdgeInsets.only(left: 70, right: Sk.lg, bottom: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          // A dot of status colour, not a whole coloured row: at a list
          // density this size, full-bleed status would make the screen a
          // scoreboard.
          color: status.surface(Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Center(
          child: Text('${d.day}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: status.on(Theme.of(context).brightness),
                  fontWeight: FontWeight.w800)),
        ),
      ),
      title: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(_subtitle(totals.calories.round()),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      children: [
        for (final e in entries)
          Semantics(
            identifier: 'diary-entry-${e.id}',
            button: true,
            child: InkWell(
              onTap: () => LogEntrySheet.show(context, e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(e.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium)),
                    Text('${e.energyKcal.round()} kcal',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                  ],
                ),
              ),
            ),
          ),
        if (workouts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: Sk.sm, bottom: 2),
            child: Text('MOVEMENT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          for (final w in workouts)
            Semantics(
              identifier: 'diary-workout-${w.id}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(_workoutLine(w),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium)),
                    // Blank, not "0 kcal", when we could not compute a burn.
                    Text(w.energyKcal == null
                        ? ''
                        : '${w.energyKcal!.round()} kcal',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  static String _workoutLine(WorkoutRow w) {
    final sets = WorkoutSet.decode(w.sets);
    if (sets.isNotEmpty) {
      final reps = sets.map((s) => s.reps).toSet();
      final loads = sets.map((s) => s.weightKg).nonNulls.toSet();
      final r = reps.length == 1 ? '×${reps.first}' : '';
      final l = loads.length == 1 ? ' @ ${_kg(loads.first)} kg' : '';
      return '${w.name} · ${sets.length} sets$r$l';
    }
    if (w.durationMin != null) return '${w.name} · ${w.durationMin} min';
    return w.name;
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
