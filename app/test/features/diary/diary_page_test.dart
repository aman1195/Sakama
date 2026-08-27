import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/core/providers/current_date_provider.dart';
import 'package:sakama/features/diary/presentation/diary_page.dart';
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

  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        currentDateProvider.overrideWith(() => _FixedDate(today)),
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
}
