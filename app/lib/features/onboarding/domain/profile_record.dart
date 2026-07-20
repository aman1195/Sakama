import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'profile.dart';

part 'profile_record.freezed.dart';

/// The persisted user profile. Holds date-of-birth (stable), unlike the
/// calculator's [Profile] which needs an age in years — so `age` never goes
/// stale on disk. `toCalculatorInput(now)` is the one place "now" enters, which
/// keeps the calculator pure.
@freezed
abstract class ProfileRecord with _$ProfileRecord {
  const ProfileRecord._();

  const factory ProfileRecord({
    required DateTime dob,
    required double weightKg,
    required double heightCm,
    required Sex sex,
    required ActivityLevel activity,
    required Goal goal,
    required DietPreference diet,
    required CuisinePreference cuisine,
    @Default(<HealthCondition>[]) List<HealthCondition> conditions,
    @Default(false) bool onboardingComplete,
  }) = _ProfileRecord;

  /// Whole years from dob as of [now]. Pure given [now].
  int ageYearsAt(DateTime now) {
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  /// Project to the calculator's input for a given day.
  Profile toCalculatorInput(DateTime now) => Profile(
        ageYears: ageYearsAt(now),
        weightKg: weightKg,
        heightCm: heightCm,
        sex: sex,
        activity: activity,
        goal: goal,
        diet: diet,
        cuisine: cuisine,
        conditions: conditions,
      );
}
