import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/enums.dart';
import '../domain/profile_record.dart';

part 'onboarding_draft.freezed.dart';

/// In-progress onboarding answers. All nullable until the user chooses. The
/// controller validates ranges before it will build a ProfileRecord.
@freezed
abstract class OnboardingDraft with _$OnboardingDraft {
  const OnboardingDraft._();

  const factory OnboardingDraft({
    Goal? goal,
    DateTime? dob,
    double? weightKg,
    double? heightCm,
    Sex? sex,
    DietPreference? diet,
    @Default(<HealthCondition>[]) List<HealthCondition> conditions,
    CuisinePreference? cuisine,
    ActivityLevel? activity,
  }) = _OnboardingDraft;

  // Validation bounds (also the UI's accepted input ranges). Health context:
  // reject absurd/typo values so garbage never reaches the calculator.
  static const minAge = 13, maxAge = 100;
  static const minWeight = 20.0, maxWeight = 300.0;
  static const minHeight = 100.0, maxHeight = 250.0;

  int? ageAt(DateTime now) {
    final d = dob;
    if (d == null) return null;
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  bool get goalOk => goal != null;
  bool profileOk(DateTime now) {
    final a = ageAt(now);
    return a != null && a >= minAge && a <= maxAge &&
        weightKg != null && weightKg! >= minWeight && weightKg! <= maxWeight &&
        heightCm != null && heightCm! >= minHeight && heightCm! <= maxHeight &&
        sex != null;
  }
  bool get dietOk => diet != null;
  bool get cuisineOk => cuisine != null;
  bool get activityOk => activity != null;

  bool complete(DateTime now) =>
      goalOk && profileOk(now) && dietOk && cuisineOk && activityOk;

  /// Build the persisted record. Call only when [complete] is true (the bang
  /// operators are guarded by that contract). `none` is dropped from conditions.
  ProfileRecord toRecord({bool onboardingComplete = false}) => ProfileRecord(
        dob: dob!,
        weightKg: weightKg!,
        heightCm: heightCm!,
        sex: sex!,
        activity: activity!,
        goal: goal!,
        diet: diet!,
        cuisine: cuisine!,
        conditions:
            conditions.where((c) => c != HealthCondition.none).toList(),
        onboardingComplete: onboardingComplete,
      );
}
