import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/home/presentation/home_page.dart';
import 'package:sakama/features/home/presentation/widgets/calorie_budget_ring.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

/// M4.1b: the active plan's day-type targets overlay the computed maintenance
/// targets on the dashboard (and, via targetsProvider, in Vita's grounding).

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

final _profile = ProfileRecord(
  dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: Sex.male,
  activity: ActivityLevel.moderate, goal: Goal.maintain,
  diet: DietPreference.veg, cuisine: CuisinePreference.both,
  onboardingComplete: true);

// A plan whose default calories are a distinctive 1500 (unlike any computed
// maintenance value); every weekday maps to the sole 'normal' day type.
const _planCalories1500 = '{"schema_version":1,"id":"p","name":"Reset",'
    '"goal":"detox","targets_default":{"calories":1500},'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal","tue":"normal",'
    '"wed":"normal","thu":"normal","fri":"normal","sat":"normal","sun":"normal"}}}';

Future<void> _seedActivePlan(SakamaDatabase db, String config) =>
    db.into(db.userPlans).insert(UserPlansCompanion.insert(
          id: 'plan-1', name: 'Reset', config: config,
          active: const Value(true), createdAt: 1, updatedAt: 1));

void main() {
  testWidgets('active plan target drives the dashboard ring, overlaying computed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'x', date: _today(), meal: 'lunch', name: 'dal tadka',
          energyKcal: 180, createdAt: 1, updatedAt: 1));
    await _seedActivePlan(db, _planCalories1500);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        profileProvider.overrideWith((ref) => Stream.value(_profile)),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    for (var i = 0;
        i < 40 && tester.widgetList(find.byType(CalorieBudgetRing)).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Extra pumps so the plan stream (db future → repo → watchActiveRow) settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The ring shows the PLAN's 1500 target, not the computed maintenance value.
    expect(find.textContaining('180 of 1500 eaten'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('targetsProvider falls back to computed when no plan is active', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      profileProvider.overrideWith((ref) => Stream.value(_profile)),
    ]);
    addTearDown(container.dispose);
    container.listen(targetsProvider, (_, _) {});

    // Let profile + the (empty) plan stream resolve.
    await container.read(databaseProvider.future);
    for (var i = 0;
        i < 50 && !container.read(profileProvider).hasValue;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final computed = container.read(targetsProvider);
    expect(computed, isNotNull);
    // No active plan → equals the raw computed maintenance target (never 1500).
    expect(computed!.calories, isNot(1500));
  });
}
