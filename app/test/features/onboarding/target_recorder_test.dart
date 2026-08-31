import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/data/food_log_repository.dart';
import 'package:sakama/features/onboarding/application/target_recorder.dart';
import 'package:sakama/features/onboarding/data/target_history_repository.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

/// One pass of the recorder — where the two worst defects in this feature
/// lived. WHEN a row is written is the behaviour here, which the repository's
/// own tests cannot see.
///
/// Called directly rather than through the widget on purpose: work scheduled
/// under a widget test's fake clock never resumes on real database I/O, so a
/// widget test of this would hang instead of failing, which is worse than not
/// having one.
void main() {
  late SakamaDatabase db;
  late TargetHistoryRepository repo;

  final profile = ProfileRecord(
      dob: DateTime(1994, 1, 1),
      weightKg: 70,
      heightCm: 175,
      sex: Sex.male,
      activity: ActivityLevel.moderate,
      goal: Goal.maintain,
      diet: DietPreference.veg,
      cuisine: CuisinePreference.both,
      onboardingComplete: true);

  const targets = NutritionTargets(
      calories: 2100, proteinG: 130, carbG: 240, fatG: 70, fiberG: 30,
      waterMl: 2500);

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = TargetHistoryRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pass({
    NutritionTargets? t = targets,
    ProfileRecord? p,
    bool planActive = false,
    DateTime? date,
  }) =>
      recordTargetsFor(
        repo: repo,
        targets: t,
        profile: p ?? profile,
        planActive: planActive,
        date: date ?? DateTime(2026, 8, 31),
      );

  test('records today, once', () async {
    await pass();
    await pass();
    final rows = await repo.all();
    expect(rows.length, 1);
    expect(rows.single.date, '2026-08-31');
    expect(rows.single.source, 'computed');
  });

  test('a plan day is recorded as one', () async {
    await pass(planActive: true);
    expect((await repo.all()).single.source, 'plan');
  });

  test('backfills history that arrives AFTER the first pass', () async {
    // The fresh-install trap: a new phone records today at first frame, and
    // PowerSync delivers the old logs afterwards. A seed that only fired on an
    // empty table would be locked out by the row the first pass just wrote,
    // leaving weeks of real history with no ruler behind them — and the same
    // account on the older phone scoring those weeks differently.
    await pass();
    expect((await repo.all()).length, 1, reason: 'today only, so far');

    await FoodLogRepository(db).add(
        date: '2026-07-02', meal: 'lunch', name: 'dal', grams: 200,
        energyKcal: 180, proteinG: 9, carbG: 22, fatG: 6);

    await pass(); // the next launch, a rollover, a goal edit — any later pass

    final rows = await repo.all();
    expect(rows.any((r) => r.source == 'seed'), isTrue,
        reason: 'late-arriving history must still get covered');
    expect(TargetHistoryRepository.resolve(rows, '2026-07-02')?.calories,
        greaterThan(0),
        reason: 'and that day must resolve to a real number, not null');
  });

  test('one pass covers both the oldest logged day and today', () async {
    await FoodLogRepository(db).add(
        date: '2026-07-02', meal: 'lunch', name: 'dal', grams: 200,
        energyKcal: 180, proteinG: 9, carbG: 22, fatG: 6);
    await pass();

    final rows = await repo.all();
    expect(rows.first.date, '2026-07-02',
        reason: 'the seed covers the oldest logged day');
    expect(rows.first.source, 'seed');
    expect(rows.last.date, '2026-08-31');
  });

  test('no profile writes nothing — not a zero row', () async {
    await pass(t: null, p: null);
    expect(await repo.all(), isEmpty);
  });

  test('a non-positive target is skipped, not thrown and not recorded',
      () async {
    // A fasting day type in unvalidated plan JSON can carry calories: 0.
    // Recording it would score every day of that plan as "over"; throwing
    // would take out the pass from a listener that nobody awaits.
    const fasting = NutritionTargets(
        calories: 0, proteinG: 0, carbG: 0, fatG: 0, fiberG: 0, waterMl: 2500);
    await expectLater(pass(t: fasting), completes);
    expect(await repo.all(), isEmpty);
  });

  test('a later pass on a new day adds a row when the target changed',
      () async {
    await pass(date: DateTime(2026, 8, 30));
    const cut = NutritionTargets(
        calories: 1800, proteinG: 140, carbG: 180, fatG: 60, fiberG: 30,
        waterMl: 2500);
    await pass(t: cut, date: DateTime(2026, 8, 31));

    final rows = await repo.all();
    expect(rows.length, 2);
    // The day before the change keeps the number it was lived under.
    expect(TargetHistoryRepository.resolve(rows, '2026-08-30')?.calories, 2100);
    expect(TargetHistoryRepository.resolve(rows, '2026-08-31')?.calories, 1800);
  });
}
