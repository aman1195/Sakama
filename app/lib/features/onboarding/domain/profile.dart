import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'profile.freezed.dart';

/// The user's onboarding profile — the input to target computation.
/// Not persisted yet; persistence + the profiles table land with the
/// onboarding UI slice.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int ageYears,
    required double weightKg,
    required double heightCm,
    required Sex sex,
    required ActivityLevel activity,
    required Goal goal,
    required DietPreference diet,
    required CuisinePreference cuisine,
    @Default(<HealthCondition>[]) List<HealthCondition> conditions,
  }) = _Profile;
}
