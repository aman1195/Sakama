import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/onboarding/data/profile_repository.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';
import 'package:sakama/features/onboarding/domain/target_calculator.dart';

void main() {
  late SakamaDatabase db;
  late ProfileRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = ProfileRepository(db);
  });
  tearDown(() => db.close());

  ProfileRecord sample() => ProfileRecord(
        dob: DateTime(1994, 3, 15),
        weightKg: 70,
        heightCm: 175,
        sex: Sex.male,
        activity: ActivityLevel.moderate,
        goal: Goal.loseWeight,
        diet: DietPreference.nonVeg,
        cuisine: CuisinePreference.north,
        conditions: const [HealthCondition.thyroid, HealthCondition.pcod],
        onboardingComplete: true,
      );

  test('save then get round-trips every field, including the conditions list', () async {
    expect(await repo.get(), isNull);
    await repo.save(sample());
    final got = (await repo.get())!;
    expect(got.dob, DateTime(1994, 3, 15));
    expect(got.weightKg, 70);
    expect(got.sex, Sex.male);
    expect(got.goal, Goal.loseWeight);
    expect(got.diet, DietPreference.nonVeg);
    expect(got.conditions, [HealthCondition.thyroid, HealthCondition.pcod]);
    expect(got.onboardingComplete, isTrue);
  });

  test('empty conditions round-trip as an empty list (not [""])', () async {
    await repo.save(sample().copyWith(conditions: const []));
    expect((await repo.get())!.conditions, isEmpty);
  });

  test('save keeps ONE row and updates in place', () async {
    await repo.save(sample());
    await repo.save(sample().copyWith(weightKg: 68));
    final all = await db.select(db.profiles).get();
    expect(all, hasLength(1));
    expect(all.single.weightKg, 68);
  });

  test('ageYearsAt derives from dob (no stale stored age)', () {
    final r = sample(); // dob 1994-03-15
    expect(r.ageYearsAt(DateTime(2026, 3, 14)), 31); // day before birthday
    expect(r.ageYearsAt(DateTime(2026, 3, 15)), 32); // on birthday
  });

  test('toCalculatorInput feeds the target engine end-to-end', () async {
    await repo.save(sample());
    final r = (await repo.get())!;
    final targets = const TargetCalculator().targets(r.toCalculatorInput(DateTime(2026, 6, 1)));
    expect(targets.calories, greaterThan(1500)); // sane, floored
    expect(targets.proteinG, greaterThan(0));
    expect(targets.carbG, greaterThan(0));
  });
}
