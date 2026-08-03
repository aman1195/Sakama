import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/config/remote_config.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/plans/application/plan_importer.dart';
import 'package:sakama/features/plans/data/plan_generator.dart';
import 'package:sakama/features/plans/data/plan_repository.dart';
import 'package:sakama/features/plans/presentation/plans_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_byok.dart';

const _plan = '{"schema_version":1,"id":"p","name":"AI Plan","goal":"detox",'
    '"day_types":{"normal":{"label":"n"}},'
    '"schedule":{"type":"weekly","map":{"mon":"normal"}}}';

final _profile = ProfileRecord(
  dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: Sex.male,
  activity: ActivityLevel.moderate, goal: Goal.detox,
  diet: DietPreference.veg, cuisine: CuisinePreference.both,
  onboardingComplete: true);

/// Returns a canned result, or throws a canned error.
class _FakeGenerator implements PlanGenerator {
  _FakeGenerator({this.result, this.error});
  final PlanImportResult? result;
  final Object? error;
  bool called = false;
  @override
  Future<PlanImportResult> generate(ProfileRecord profile, {String? byok}) async {
    called = true; // proves whether the consent gate let egress happen
    if (error != null) throw error!;
    return result!;
  }
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  SakamaDatabase db, {
  required bool flagOn,
  PlanGenerator? generator,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async => db),
      profileProvider.overrideWith((ref) => Stream.value(_profile)),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      remoteConfigProvider.overrideWith(
          (ref) async => RemoteConfig(flags: {'plan_generation': flagOn})),
      if (generator != null)
        planGeneratorProvider.overrideWithValue(generator),
    ],
    child: const MaterialApp(home: PlansPage()),
  ));
  // Warm profileProvider: PlansPage doesn't watch it, but the real app's router
  // gate keeps it live, so _generate reads a resolved value (not cold-loading).
  ProviderScope.containerOf(tester.element(find.byType(PlansPage)))
      .listen(profileProvider, (_, _) {});
  await _pumpFrames(tester);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

Future<List<UserPlanRow>> _all(WidgetTester tester, SakamaDatabase db) async =>
    (await tester.runAsync(() => PlanRepository(db).watchAll().first))!;

void main() {
  testWidgets('the generate action is hidden while the kill switch is off',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db, flagOn: false);

    expect(find.bySemanticsIdentifier('plan-generate'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('with the switch on, a successful generation saves + applies it',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ai_data_enabled': true}); // consent
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db,
        flagOn: true,
        generator: _FakeGenerator(
            result: const PlanImporter().validate(_plan)));

    expect(find.bySemanticsIdentifier('plan-generate'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('plan-generate'));
    await _pumpFrames(tester);

    final plans = await _all(tester, db);
    expect(plans.length, 1);
    expect(plans.single.name, 'AI Plan');
    expect(plans.single.source, 'ai_generated',
        reason: 'a generated plan is tagged ai_generated');
    expect(plans.single.active, isTrue);
    await _dispose(tester);
  });

  testWidgets('a budget-exhausted generation shows the limit message, saves nothing',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ai_data_enabled': true}); // consent
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    await _mount(tester, db,
        flagOn: true,
        generator: _FakeGenerator(
            error: PlanGenerationException('cap', budgetExhausted: true)));

    await tester.tap(find.bySemanticsIdentifier('plan-generate'));
    await _pumpFrames(tester);

    expect(find.textContaining("used today's plan generations"), findsOneWidget);
    expect(await _all(tester, db), isEmpty);
    await _dispose(tester);
  });

  testWidgets('AI consent OFF blocks generation — no egress, nothing saved (#60/#62)',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ai_data_enabled': false}); // AI off
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(() => db.close()));
    final gen = _FakeGenerator(result: const PlanImporter().validate(_plan));
    await _mount(tester, db, flagOn: true, generator: gen);

    await tester.tap(find.bySemanticsIdentifier('plan-generate'));
    await _pumpFrames(tester);

    // The consent gate stops before the provider is ever called.
    expect(gen.called, isFalse,
        reason: 'health conditions must not reach the provider without consent');
    expect(find.textContaining('AI features are turned off'), findsOneWidget);
    expect(await _all(tester, db), isEmpty);
    await _dispose(tester);
  });
}
