import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/plans/presentation/plan_detail_page.dart';

/// A plan exercising every rendered section: default targets, a day type with
/// window + blocked foods + checklist + its own targets, and a weekly schedule.
const _config = '{"schema_version":1,"id":"p","name":"Metabolic Reset",'
    '"goal":"lose_weight","duration_days":28,'
    '"targets_default":{"calories":1600,'
    '"macros":{"protein_g":90,"carb_g":150,"fat_g":50,"fiber_g":30},'
    '"water_ml":3000},'
    '"day_types":{'
    '"normal":{"label":"Normal day","blocked_foods":["sugar"],'
    '"checklist":["10k steps"]},'
    '"reset":{"label":"Tuesday reset",'
    '"targets":{"calories":1200},'
    '"fasting_window":{"eat_start":"12:00","eat_end":"20:00"},'
    '"blocked_foods":["grains","dairy"],"checklist":["3L water"]}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"reset",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _seed(WidgetTester tester, SakamaDatabase db,
        {String id = 'plan-1', String config = _config}) =>
    tester.runAsync(() => db.into(db.userPlans).insert(UserPlansCompanion.insert(
          id: id, name: 'Metabolic Reset', config: config,
          source: const Value('ai_generated'),
          active: const Value(true), createdAt: 1, updatedAt: 1)));

Future<void> _mount(WidgetTester tester, SakamaDatabase db,
    {String id = 'plan-1'}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWith((ref) async => db)],
    child: MaterialApp(home: PlanDetailPage(planId: id)),
  ));
  await _pumpFrames(tester);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the plan: header, targets, day types, schedule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db);
    await _mount(tester, db);

    // Header: name, provenance, goal, duration, active badge.
    expect(find.text('Metabolic Reset'), findsOneWidget);
    expect(find.textContaining('Generated for you'), findsOneWidget);
    expect(find.textContaining('Lose weight'), findsOneWidget);
    expect(find.textContaining('28 days'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    // Default targets, formatted with units.
    expect(find.text('1600 kcal'), findsOneWidget);
    expect(find.text('90 g'), findsOneWidget);
    expect(find.text('3000 ml'), findsOneWidget);

    // Both day types, with their rules. Each label appears in its day-type
    // card AND once per weekday the schedule maps to it, hence findsWidgets.
    expect(find.text('Normal day'), findsWidgets);
    expect(find.text('Tuesday reset'), findsWidgets);
    expect(find.textContaining('Eating window 12:00–20:00'), findsOneWidget);
    expect(find.textContaining('Avoid: grains, dairy'), findsOneWidget);
    expect(find.textContaining('3L water'), findsOneWidget);
    // The reset day overrides calories.
    expect(find.text('1200 kcal'), findsOneWidget);

    // Weekly schedule maps weekdays to day-type LABELS (not raw keys).
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('raw JSON is hidden until toggled, then shown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db);
    await _mount(tester, db);

    expect(find.bySemanticsIdentifier('plan-raw-json'), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('plan-raw-toggle'));
    await _pumpFrames(tester, 6);
    expect(find.bySemanticsIdentifier('plan-raw-json'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('an unreadable config still shows the stored text, not a dead end',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db, config: 'not json at all {{{');
    await _mount(tester, db);

    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.bySemanticsIdentifier('plan-raw-json'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('a day type that only repeats the default hides "Targets this day"',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    // Day-type targets identical to targets_default → redundant, must be hidden.
    await _seed(tester, db,
        config: '{"schema_version":1,"id":"p","name":"Flat",'
            '"targets_default":{"calories":1800},'
            '"day_types":{"normal":{"label":"Standard day",'
            '"targets":{"calories":1800}}},'
            '"schedule":{"type":"weekly","map":{"mon":"normal"}}}');
    await _mount(tester, db);

    expect(find.text('Targets this day'), findsNothing,
        reason: 'restating the plan default is noise, not information');
    // The default itself is still shown once.
    expect(find.text('1800 kcal'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('a day type that genuinely differs still shows its targets',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db); // _config: the reset day overrides to 1200
    await _mount(tester, db);
    expect(find.text('Targets this day'), findsOneWidget);
    expect(find.text('1200 kcal'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('coaching messages from rules render on their day type',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _seed(tester, db,
        config: '{"schema_version":1,"id":"p","name":"Coached",'
            '"day_types":{"reset":{"label":"Reset day"},'
            '"normal":{"label":"Normal day"}},'
            '"schedule":{"type":"weekly","map":{"mon":"reset"}},'
            '"rules":[{"id":"r1","when":{"day_type":"reset"},'
            '"message":"Electrolytes matter more today."}]}');
    await _mount(tester, db);

    expect(find.textContaining('Electrolytes matter more today'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('a deleted/unknown plan id says so instead of crashing',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db, id: 'does-not-exist');

    expect(find.textContaining('no longer saved'), findsOneWidget);
    await _dispose(tester);
  });

  /// The 'reset' day above states 1200 kcal — the same number as the canonical
  /// example plan in docs/architecture/04-plan-engine.md, and below the 1500
  /// floor for men. Rendering it bare tells a user they are on 1200 when
  /// targetsProvider will refuse it.
  group('a day type below the floor is marked as not applied', () {
    ProfileRecord profileFor(Sex sex) => ProfileRecord(
        dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: sex,
        activity: ActivityLevel.moderate, goal: Goal.maintain,
        diet: DietPreference.veg, cuisine: CuisinePreference.both,
        onboardingComplete: true);

    Future<void> mountWith(WidgetTester tester, SakamaDatabase db, Sex sex) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          profileProvider.overrideWith((ref) => Stream.value(profileFor(sex))),
        ],
        child: const MaterialApp(home: PlanDetailPage(planId: 'plan-1')),
      ));
      await _pumpFrames(tester);
    }

    testWidgets('marked for a man, whose floor is 1500', (tester) async {
      final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(tester, db);
      await mountWith(tester, db, Sex.male);

      expect(find.bySemanticsIdentifier('plan-target-below-floor'),
          findsOneWidget);
      expect(find.textContaining('not applied'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('not marked at exactly the floor', (tester) async {
      // 1200 is the floor for women, so the same plan is honoured and marking
      // it would be a false alarm on a legitimate plan.
      final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(tester, db);
      await mountWith(tester, db, Sex.female);

      expect(find.bySemanticsIdentifier('plan-target-below-floor'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
