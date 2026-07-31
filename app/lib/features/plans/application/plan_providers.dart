import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../domain/plan.dart';
import '../domain/plan_day.dart';
import '../domain/plan_interpreter.dart';

/// The active plan ROW, live (config string + startDate intact), or null when
/// the user has no active plan. Tolerant of a split-brain active state — the
/// repository caps the read at the most-recently-activated row (review #69).
final activePlanRowProvider = StreamProvider<UserPlanRow?>((ref) async* {
  final repo = await ref.watch(planRepositoryProvider.future);
  yield* repo.watchActiveRow();
});

/// Every saved plan, newest first (the plan library). Drives the management
/// list where the user switches between or deletes plans.
final savedPlansProvider = StreamProvider<List<UserPlanRow>>((ref) async* {
  final repo = await ref.watch(planRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Today's resolved [PlanDay] for the active plan, or null when there is no
/// active plan (or its stored config is unparseable). This is the single engine
/// output the dashboard, the log-enforcement surfaces, and Vita all read.
///
/// Cyclic schedules index off the row's `start_date`; a null/invalid start
/// resolves to index 0 (the interpreter's documented default).
final activePlanDayProvider = Provider<PlanDay?>((ref) {
  final row = ref.watch(activePlanRowProvider).value;
  if (row == null) return null;
  final plan = Plan.tryParse(row.config);
  if (plan == null) return null;
  final start =
      row.startDate == null ? null : DateTime.tryParse(row.startDate!);
  return const PlanInterpreter()
      .resolve(plan, date: DateTime.now(), planStart: start);
});
