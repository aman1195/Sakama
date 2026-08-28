import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/capture/domain/entry_confidence.dart';
import 'package:sakama/features/home/presentation/widgets/today_hero.dart';
import 'package:sakama/app/status_surface.dart';
import 'package:sakama/features/workouts/data/workout_repository.dart';

void main() {
  group('EntryConfidence', () {
    test('separates looked-up numbers from guessed ones', () {
      for (final via in ['search', 'barcode', 'recent']) {
        expect(EntryConfidence.of(via), EntryConfidence.verified,
            reason: '$via came from a database row');
      }
      for (final via in ['photo', 'ai_estimate', 'vita']) {
        expect(EntryConfidence.of(via), EntryConfidence.estimated,
            reason: '$via was produced by a model');
      }
      for (final via in ['manual', 'quick_add', '', 'something-new']) {
        expect(EntryConfidence.of(via), EntryConfidence.manual);
      }
    });

    test('a hand-typed entry gets no badge', () {
      // Marking every manual row would make the badge noise. The two that
      // matter are "we looked this up" and "we guessed".
      expect(EntryConfidence.manual.label, isNull);
      expect(EntryConfidence.verified.label, 'Verified');
      expect(EntryConfidence.estimated.label, 'Estimate');
    });

    test('an unknown logged_via degrades to manual, never to verified', () {
      // A new logging path added later must not silently inherit a trust
      // signal it did not earn.
      expect(EntryConfidence.of('some_future_source'), EntryConfidence.manual);
    });
  });

  group('TodayHero burn', () {
    Future<void> pump(WidgetTester t,
        {double? burned, int unknown = 0}) async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TodayHero(
            status: TrackStatus.muted,
            target: 2000,
            eaten: 800,
            burned: burned,
            burnedUnknown: unknown,
            actions: const [],
          ),
        ),
      ));
      await t.pump();
    }

    testWidgets('burn is shown beside eaten, NOT added to remaining',
        (t) async {
      await pump(t, burned: 300);
      expect(find.textContaining('800 eaten'), findsOneWidget);
      expect(find.textContaining('300 burned'), findsOneWidget);
      // 2000 - 800 = 1200. If burn were netted this would read 1500, and the
      // user would eat 300 kcal off a MET formula and a weigh-in without ever
      // being asked.
      expect(find.text('1200'), findsOneWidget);
    });

    testWidgets('no burn line when nothing was computed', (t) async {
      await pump(t);
      expect(find.textContaining('800 eaten'), findsOneWidget);
      expect(find.textContaining('burned'), findsNothing);
    });

    testWidgets('a zero burn is not reported as a burn', (t) async {
      await pump(t, burned: 0);
      expect(find.textContaining('burned'), findsNothing);
    });

    testWidgets('workouts with no estimate are counted out loud', (t) async {
      // Otherwise "300 burned" reads as the whole day's effort when two
      // sessions contributed nothing we could compute.
      await pump(t, burned: 300, unknown: 2);
      expect(find.textContaining('2 without an estimate'), findsOneWidget);
    });

    testWidgets('unestimated workouts show even with no burn at all',
        (t) async {
      await pump(t, unknown: 3);
      expect(find.textContaining('3 without an estimate'), findsOneWidget);
      expect(find.textContaining('burned'), findsNothing);
    });
  });

  test('dayBurn skips unknowns rather than counting them zero', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    for (final (id, kcal) in [('a', 300.0), ('b', null), ('c', 120.0)]) {
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: id, date: '2026-08-28', name: id,
            energyKcal: Value(kcal), createdAt: 1, updatedAt: 1,
          ));
    }
    // The REAL function the screen calls. An earlier version of this test
    // reimplemented dayBurn locally and passed against its own copy, which
    // proves nothing about the code that ships.
    final burn = WorkoutRepository.dayBurn(await db.select(db.workouts).get());
    expect(burn.kcal, 420, reason: 'the unknown contributes nothing, not zero');
    expect(burn.unknown, 1);
  });
}
