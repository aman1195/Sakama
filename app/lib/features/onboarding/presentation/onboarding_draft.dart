import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/body_metrics.dart';
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

  // Validation bounds = the shared BodyMetrics (single source of truth, so
  // onboarding and weight logging can't diverge). Reject absurd/typo values so
  // garbage never reaches the calculator.
  static const minAge = BodyMetrics.minAgeYears, maxAge = BodyMetrics.maxAgeYears;
  static const minWeight = BodyMetrics.minWeightKg, maxWeight = BodyMetrics.maxWeightKg;
  static const minHeight = BodyMetrics.minHeightCm, maxHeight = BodyMetrics.maxHeightCm;

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
