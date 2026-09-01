import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../onboarding/domain/target_calculator.dart';
import '../application/plan_providers.dart';
import '../domain/plan.dart';

/// Read-only view of a saved plan: what it actually says, not just its effects.
/// Plans are DATA (ADR 0007) — this renders that data (targets, day types,
/// windows, foods, checklist, schedule) so a user can inspect a plan they
/// imported or had generated, and a developer can see exactly what the AI
/// returned (the raw-JSON toggle).
class PlanDetailPage extends ConsumerStatefulWidget {
  const PlanDetailPage({required this.planId, super.key});
  final String planId;

  @override
  ConsumerState<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends ConsumerState<PlanDetailPage> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(savedPlansProvider);

    return Semantics(
      identifier: 'plan-detail-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Plan')),
        body: plansAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load the plan: $e')),
          data: (plans) {
            final row =
                plans.where((p) => p.id == widget.planId).firstOrNull;
            if (row == null) {
              return const Center(child: Text('This plan is no longer saved.'));
            }
            final plan = Plan.tryParse(row.config);
            if (plan == null) {
              // The stored config is unreadable — still let the user see the
              // raw text rather than a dead end.
              return _RawOnly(config: row.config);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(plan: plan, source: row.source, active: row.active),
                const SizedBox(height: 16),
                _TargetsCard(
                    title: 'Daily targets', targets: plan.targetsDefault),
                const SizedBox(height: 16),
                Text('Day types',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (plan.dayTypes.isEmpty)
                  const Text('This plan declares no day types.')
                else
                  ...plan.dayTypes.entries.map((e) => _DayTypeCard(
                        keyName: e.key,
                        dayType: e.value,
                        planDefault: plan.targetsDefault,
                        messages: plan.rules
                            .where((r) => r.whenDayType == e.key)
                            .map((r) => r.message)
                            .whereType<String>()
                            .toList(),
                      )),
                const SizedBox(height: 16),
                Text('Schedule', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _ScheduleCard(schedule: plan.schedule, dayTypes: plan.dayTypes),
                const SizedBox(height: 24),
                // Developer affordance: exactly what was imported/generated.
                Semantics(
                  identifier: 'plan-raw-toggle',
                  button: true,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showRaw = !_showRaw),
                    icon: Icon(_showRaw
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down),
                    label: Text(_showRaw ? 'Hide raw plan' : 'Show raw plan'),
                  ),
                ),
                if (_showRaw) _RawJson(config: row.config),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.plan, required this.source, required this.active});
  final Plan plan;
  final String source;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      switch (source) {
        'ai_generated' => 'Generated for you',
        'template' => 'Template',
        _ => 'Imported',
      },
      if (plan.goal != null) _goalLabel(plan.goal!),
      if (plan.durationDays != null) '${plan.durationDays} days',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name.isEmpty ? 'Untitled plan' : plan.name,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (active)
                  Chip(
                    label: const Text('Active'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(bits.join(' · '),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  static String _goalLabel(String g) => switch (g) {
        'lose_weight' || 'loseWeight' => 'Lose weight',
        'build_muscle' || 'buildMuscle' => 'Build muscle',
        'manage_condition' || 'manageCondition' => 'Manage a condition',
        'detox' => 'Detox',
        'maintain' => 'Maintain',
        _ => g,
      };
}

class _TargetsCard extends ConsumerWidget {
  const _TargetsCard({required this.title, required this.targets});
  final String title;
  final PlanTargets targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A stated target below the clinical floor is never applied for this user
    // (targetsProvider refuses it), so showing the number bare would tell them
    // they are on 900 kcal when they are not. Reads the profile here rather
    // than taking it as a parameter so both call sites are covered by one rule.
    final profile = ref.watch(profileProvider).value;
    final belowFloor = profile != null &&
        targets.calories != null &&
        targets.calories! <
            TargetCalculator.calorieFloor(
                profile.toCalculatorInput(DateTime.now()).sex);

    final rows = <(String, int?)>[
      ('Calories', targets.calories),
      ('Protein', targets.proteinG),
      ('Carbs', targets.carbG),
      ('Fat', targets.fatG),
      ('Fibre', targets.fiberG),
      ('Water', targets.waterMl),
    ];
    if (rows.every((r) => r.$2 == null)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$title: follows your computed targets.',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (belowFloor) ...[
              const SizedBox(height: 6),
              Semantics(
                identifier: 'plan-target-below-floor',
                child: Text(
                  'Below a safe minimum, so this is not applied — your usual '
                  'target is used on these days.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              if (value != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label),
                      Text(_fmt(label, value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _fmt(String label, int v) => switch (label) {
        'Calories' => '$v kcal',
        'Water' => '$v ml',
        _ => '$v g',
      };
}

class _DayTypeCard extends StatelessWidget {
  const _DayTypeCard({
    required this.keyName,
    required this.dayType,
    required this.planDefault,
    this.messages = const [],
  });
  final String keyName;
  final DayType dayType;

  /// The plan's default targets — used to hide a day's targets when they merely
  /// restate the default (redundant noise).
  final PlanTargets planDefault;

  /// Coaching messages from `rules` scoped to this day type.
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final w = dayType.fastingWindow;
    return Semantics(
      identifier: 'plan-day-type-$keyName',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayType.label,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (w != null)
                _line(context, Icons.schedule,
                    'Eating window ${w.eatStart}–${w.eatEnd}'),
              if (dayType.allowedFoods != null)
                _line(context, Icons.check_circle_outline,
                    'Only: ${dayType.allowedFoods!.join(', ')}'),
              if (dayType.blockedFoods.isNotEmpty)
                _line(context, Icons.block,
                    'Avoid: ${dayType.blockedFoods.join(', ')}'),
              for (final item in dayType.checklist)
                _line(context, Icons.checklist, item),
              for (final m in messages)
                _line(context, Icons.format_quote, m),
              // Day-type targets ONLY when they actually differ from the plan
              // default — restating identical numbers is noise, not information.
              if (_differsFrom(dayType.targets, planDefault)) ...[
                const SizedBox(height: 8),
                _TargetsCard(
                    title: 'Targets this day', targets: dayType.targets),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// True when [t] states at least one value that differs from [base]. A day
  /// type that only repeats the plan default adds nothing worth rendering.
  static bool _differsFrom(PlanTargets t, PlanTargets base) =>
      (t.calories != null && t.calories != base.calories) ||
      (t.proteinG != null && t.proteinG != base.proteinG) ||
      (t.carbG != null && t.carbG != base.carbG) ||
      (t.fatG != null && t.fatG != base.fatG) ||
      (t.fiberG != null && t.fiberG != base.fiberG) ||
      (t.waterMl != null && t.waterMl != base.waterMl);

  Widget _line(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule, required this.dayTypes});
  final Schedule schedule;
  final Map<String, DayType> dayTypes;

  static const _dayNames = {
    'mon': 'Monday', 'tue': 'Tuesday', 'wed': 'Wednesday', 'thu': 'Thursday',
    'fri': 'Friday', 'sat': 'Saturday', 'sun': 'Sunday',
  };

  String _label(String key) => dayTypes[key]?.label ?? key;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    switch (schedule) {
      case WeeklySchedule(:final map):
        if (map.isEmpty) {
          children.add(const Text('No weekly schedule set.'));
        }
        for (final d in _dayNames.keys) {
          final key = map[d];
          if (key == null) continue;
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(_dayNames[d]!), Text(_label(key))],
            ),
          ));
        }
      case CyclicSchedule(:final cycle):
        children.add(Text('Repeating cycle of ${cycle.length} days:'));
        for (var i = 0; i < cycle.length; i++) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Day ${i + 1}'), Text(_label(cycle[i]))],
            ),
          ));
        }
      case ExplicitSchedule(:final dates):
        for (final e in dates.entries) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(e.key), Text(_label(e.value))],
            ),
          ));
        }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

/// Pretty-printed original config. Falls back to the raw string when it is not
/// re-encodable (which is exactly the case worth showing verbatim).
class _RawJson extends StatelessWidget {
  const _RawJson({required this.config});
  final String config;

  @override
  Widget build(BuildContext context) {
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(config));
    } catch (_) {
      pretty = config;
    }
    return Semantics(
      identifier: 'plan-raw-json',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(pretty,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
      ),
    );
  }
}

/// Shown when the stored config cannot be parsed at all — the user still gets
/// to see (and copy) what is stored instead of an error dead end.
class _RawOnly extends StatelessWidget {
  const _RawOnly({required this.config});
  final String config;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("This plan's contents could not be read. The stored text "
              'is shown below.'),
          const SizedBox(height: 12),
          _RawJson(config: config),
        ],
      );
}
