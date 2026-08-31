import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/core/providers/current_date_provider.dart';
import 'package:sakama/features/diary/presentation/diary_page.dart';
import 'package:sakama/features/onboarding/data/target_history_repository.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/nutrition_targets.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/workouts/data/workout_repository.dart';
import 'package:sakama/features/workouts/domain/workout_set.dart';

/// The Diary was a stub that rendered the word "Diary". These pin the two
/// things that make it a feature: it groups history by day, and its summary
/// counts "on target" honestly.
/// Pins "today" so the window boundary and the "Today" label are deterministic
/// rather than dependent on when the suite runs.
class _FixedDate extends CurrentDateNotifier {
  _FixedDate(this._d);
  final DateTime _d;
  @override
  DateTime build() => _d;
}

final _onboarded = ProfileRecord(
    dob: DateTime(1994, 1, 1),
    weightKg: 70,
    heightCm: 175,
    sex: Sex.male,
    activity: ActivityLevel.moderate,
    goal: Goal.maintain,
    diet: DietPreference.veg,
    cuisine: CuisinePreference.both,
    onboardingComplete: true);

void main() {
  late SakamaDatabase db;
  final today = DateTime(2026, 8, 26);

  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> log(String date, String name, double kcal) =>
      db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
            id: '$date-$name',
            date: date,
            meal: 'lunch',
            name: name,
            energyKcal: kcal,
            createdAt: 1,
            updatedAt: 1,
          ));

  /// [profile] matters for exactly one thing: with a profile, targetsProvider
  /// yields a real number, so a call site that falls back to "today's target"
  /// for an unknown day produces a VISIBLE wrong answer. Without one it
  /// produces 0 and the bug hides. Tests of the unscorable path are worthless
  /// unless they pass a profile.
  Future<void> pump(WidgetTester t, {ProfileRecord? profile}) async {
    await t.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        currentDateProvider.overrideWith(() => _FixedDate(today)),
        if (profile != null)
          profileProvider.overrideWith((ref) => Stream.value(profile)),
      ],
      child: const MaterialApp(home: DiaryPage()),
    ));
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('with no history it explains rather than showing a void',
      (t) async {
    await pump(t);
    expect(find.bySemanticsIdentifier('diary-empty'), findsOneWidget);
    expect(find.textContaining('No history yet'), findsOneWidget);
    await dispose(t);
  });

  testWidgets('days are grouped, newest first, and today is named', (t) async {
    await t.runAsync(() async {
      await log('2026-08-26', 'dal', 300);
      await log('2026-08-26', 'roti', 200);
      await log('2026-08-24', 'poha', 250);
    });
    await pump(t);

    // Two DAYS from three entries — the grouping is the feature.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('24 Aug'), findsOneWidget);
    // Today's row totals both entries rather than listing them twice.
    expect(find.textContaining('500 kcal'), findsOneWidget);
    await dispose(t);
  });

  testWidgets('the window excludes anything older than 28 days', (t) async {
    await t.runAsync(() async {
      await log('2026-08-26', 'recent', 300);
      await log('2026-06-01', 'ancient', 300); // ~86 days back
    });
    await pump(t);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('1 Jun'), findsNothing,
        reason: 'the query is bounded; an unbounded diary is a scroll that '
            'gets slower every day the app is used');
    await dispose(t);
  });

  testWidgets('a day expands to its entries, each openable', (t) async {
    await t.runAsync(() => log('2026-08-26', 'dal tadka', 300));
    await pump(t);

    await t.tap(find.text('Today'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('dal tadka'), findsOneWidget);
    expect(find.bySemanticsIdentifier('diary-entry-2026-08-26-dal tadka'),
        findsOneWidget);
    await dispose(t);
  });

  testWidgets('a day with only a workout still gets a row', (t) async {
    // Keying the list off food alone would hide the gym session of someone
    // who did not log lunch.
    await WorkoutRepository(db).add(
      date: '2026-08-25',
      name: 'bench press',
      sets: [const WorkoutSet(reps: 10, weightKg: 80)],
    );
    await pump(t);

    expect(find.text('25 Aug'), findsOneWidget);
    expect(find.textContaining('1 workout'), findsOneWidget);
    // ...and it does not claim a day of zero eating.
    expect(find.textContaining('0 kcal'), findsNothing);
    await dispose(t);
  });

  testWidgets('an uncomputed burn shows nothing, never 0 kcal', (t) async {
    await log('2026-08-26', 'dal', 200);
    // Strength work with no duration: nothing to compute a burn from.
    await WorkoutRepository(db).add(
      date: '2026-08-26',
      name: 'squats',
      sets: [const WorkoutSet(reps: 5, weightKg: 100)],
    );
    await pump(t);

    await t.tap(find.text('Today'));
    await t.pumpAndSettle();

    expect(find.text('MOVEMENT'), findsOneWidget);
    expect(find.textContaining('squats'), findsOneWidget);
    // "0 kcal out" for a real session would be a lie by rounding.
    expect(find.textContaining('kcal out'), findsNothing);
    await dispose(t);
  });

  testWidgets('a computed burn is shown on the day row', (t) async {
    await WorkoutRepository(db).add(
      date: '2026-08-26',
      name: 'evening run',
      kind: 'cardio',
      durationMin: 30,
      energyKcal: 412,
    );
    await pump(t);
    expect(find.textContaining('412 kcal out'), findsOneWidget);
    await dispose(t);
  });

  /// A day is scored by the target that was in force THAT day. These pin the
  /// wiring, not the arithmetic: the domain rule has its own tests, and the
  /// bug that shipped twice was a call site quietly answering an unknown day
  /// with today's number.
  Future<void> recordTarget(String date, int calories) =>
      TargetHistoryRepository(db).recordIfChanged(
        date: date,
        targets: NutritionTargets(
            calories: calories, proteinG: 100, carbG: 200, fatG: 60,
            fiberG: 30, waterMl: 2500),
      );

  testWidgets('with no recorded target a day is unscorable, not scored at 0',
      (t) async {
    await t.runAsync(() => log('2026-08-26', 'dal', 300));
    // WITH a profile, so today's computed target exists and could be borrowed.
    await pump(t, profile: _onboarded);

    // "—", not a count: nothing recorded a target for this day, and inventing
    // one (today's, or zero) is the bug this table exists to stop.
    expect(find.text('—'), findsOneWidget);
    // The day row reads "300 kcal", never "300 kcal of <something>".
    expect(find.textContaining('kcal of'), findsNothing,
        reason: 'no target may appear on the day row either');
    await dispose(t);
  });

  testWidgets('each day is scored against the target in force that day',
      (t) async {
    await t.runAsync(() async {
      // 2,400 until the 25th, then a cut to 1,900.
      await recordTarget('2026-08-01', 2400);
      await recordTarget('2026-08-25', 1900);
      await log('2026-08-20', 'old day', 2400); // on target under the old goal
      await log('2026-08-26', 'new day', 1900); // on target under the new one
    });
    await pump(t);

    // BOTH days count. Scored against today's 1,900 the older day would read
    // as over, and the user would watch a week they had already lived change
    // its verdict because they changed a goal.
    expect(find.text('2'), findsWidgets);
    expect(find.textContaining('of 2400'), findsOneWidget);
    expect(find.textContaining('of 1900'), findsOneWidget);
    await dispose(t);
  });
}
