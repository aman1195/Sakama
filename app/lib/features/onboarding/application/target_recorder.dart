import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/current_date_provider.dart';
import '../../home/presentation/home_page.dart' show targetsProvider;
import '../../plans/application/plan_providers.dart';
import '../data/target_history_repository.dart';
import '../domain/nutrition_targets.dart';
import '../domain/profile_record.dart';
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
  /// Passes run one at a time, in order.
  ///
  /// A date rollover that also changes the plan's day type fires both
  /// listeners in the same turn. The repository's transaction makes that safe,
  /// but serializing here makes it CHEAP — the second pass sees the first
  /// pass's row and takes the no-op branch instead of racing it. Chained
  /// rather than dropped: a dropped pass could be the one carrying a real
  /// change.
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    // After the first frame, not during it: this writes to the database, and
    // the providers it reads may still be resolving at mount.
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  @override
  Widget build(BuildContext context) {
    // Targets are a freezed value, so this fires on a REAL change — a new
    // goal, a plan activating, a day type turning over — not on every rebuild.
    ref.listen<NutritionTargets?>(targetsProvider, (_, _) => _schedule());
    ref.listen(currentDateProvider, (_, _) => _schedule());
    return widget.child;
  }

  void _schedule() {
    _queue = _queue.then((_) => _record());
  }

  Future<void> _record() async {
    // NOTHING HERE MAY THROW INTO THE VOID. This runs unawaited from a
    // listener, so an escaped exception would be an unhandled async error and
    // the day would silently go unrecorded — leaving history with a hole that
    // later reads as "no target" forever.
    try {
      if (!mounted) return;
      final targets = ref.read(targetsProvider);
      final profile = ref.read(profileProvider).value;
      final planActive = ref.read(activePlanDayProvider) != null;
      final date = ref.read(currentDateProvider);
      final userId = ref.read(currentUserIdProvider);

      final repo = await ref.read(targetHistoryRepositoryProvider.future);
      if (!mounted) return;

      await recordTargetsFor(
        repo: repo,
        targets: targets,
        profile: profile,
        planActive: planActive,
        date: date,
        userId: userId,
      );
    } catch (e) {
      // Never silent: a day that failed to record is diagnosable, and the
      // fallback is the previous row rather than a wrong number.
      debugPrint('target recorder: $e');
    }
  }
}

/// One pass of the recorder, with the widget taken out of it.
///
/// Separate from [TargetRecorder] because this is the part with decisions in
/// it — backfill before record, what counts as a target worth recording, which
/// source a row gets — and a widget test cannot reach them: work scheduled
/// under a widget test's fake clock never resumes on real database I/O, so the
/// only way to exercise this honestly is to call it directly.
Future<void> recordTargetsFor({
  required TargetHistoryRepository repo,
  required NutritionTargets? targets,
  required ProfileRecord? profile,
  required bool planActive,
  required DateTime date,
  String? userId,
}) async {
  if (targets == null) return; // no profile yet; nothing to record

  // A plan day type may legitimately carry no calorie figure (a fasting day),
  // and plan JSON is unvalidated input. Recording zero would score every day of
  // that plan as "over"; refusing to record leaves the previous row in force,
  // which is the honest answer until A2's floor lands in the target maths.
  if (targets.calories <= 0) {
    debugPrint('target recorder: skipping non-positive target');
    return;
  }

  final ymd = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // Coverage FIRST, and re-checked on every pass rather than only when the
  // table is empty. On a fresh install of an existing account the logs arrive
  // by sync AFTER the first pass, and a once-only seed would be locked out by
  // the row this pass is about to write.
  if (profile != null) {
    final earliest = await repo.earliestLoggedDate();
    if (earliest != null && earliest.compareTo(ymd) < 0) {
      await repo.backfillIfUncovered(
        earliestLogged: earliest,
        targets: const TargetCalculator()
            .targets(profile.toCalculatorInput(DateTime.now())),
        userId: userId,
      );
    }
  }

  // A plan-shaped day is recorded as such, so the row says why it was that
  // number and not merely what it was.
  await repo.recordIfChanged(
    date: ymd,
    targets: targets,
    source: planActive ? 'plan' : 'computed',
    userId: userId,
  );
}
