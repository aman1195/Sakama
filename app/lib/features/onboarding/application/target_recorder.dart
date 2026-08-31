import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/current_date_provider.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../plans/application/plan_providers.dart';
import '../domain/nutrition_targets.dart';
import '../domain/target_calculator.dart';

/// Writes down what today's targets are, whenever they change.
///
/// Mounted app-wide rather than on Home, because a target can change while the
/// user is anywhere — activating a plan from Plans, editing a goal in Me — and
/// a change nobody was looking at is still a change history has to record.
///
/// Renders its [child] unchanged; it is a pure side-effect wrapper in the same
/// shape as [DateRolloverObserver].
class TargetRecorder extends ConsumerStatefulWidget {
  const TargetRecorder({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<TargetRecorder> createState() => _TargetRecorderState();
}

class _TargetRecorderState extends ConsumerState<TargetRecorder> {
  @override
  void initState() {
    super.initState();
    // After the first frame, not during it: this writes to the database, and
    // the providers it reads may still be resolving at mount.
    WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  @override
  Widget build(BuildContext context) {
    // Targets are a freezed value, so this fires on a REAL change — a new
    // goal, a plan activating, a day type turning over — not on every rebuild.
    ref.listen<NutritionTargets?>(targetsProvider, (_, _) => _record());
    ref.listen(currentDateProvider, (_, _) => _record());
    return widget.child;
  }

  Future<void> _record() async {
    if (!mounted) return;
    final targets = ref.read(targetsProvider);
    if (targets == null) return; // no profile yet; nothing to record

    final repo = await ref.read(targetHistoryRepositoryProvider.future);
    if (!mounted) return;

    final date = _ymd(ref.read(currentDateProvider));
    final userId = ref.read(currentUserIdProvider);

    // One-time backfill for everything logged before this table existed, dated
    // at the oldest logged day and tagged `seed`. Deliberately the COMPUTED
    // targets, never the plan overlay: a plan active today says nothing about
    // last month.
    final profile = ref.read(profileProvider).value;
    if (profile != null) {
      final earliest = await repo.earliestLoggedDate();
      if (earliest != null && earliest.compareTo(date) < 0) {
        await repo.seedIfEmpty(
          date: earliest,
          targets: const TargetCalculator()
              .targets(profile.toCalculatorInput(DateTime.now())),
          userId: userId,
        );
      }
    }

    // A plan-shaped day is recorded as such, so the row says why it was that
    // number and not merely what it was.
    final source =
        ref.read(activePlanDayProvider) == null ? 'computed' : 'plan';
    await repo.recordIfChanged(
        date: date, targets: targets, source: source, userId: userId);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
