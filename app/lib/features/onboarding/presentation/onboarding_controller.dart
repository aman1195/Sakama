import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../domain/enums.dart';
import 'onboarding_draft.dart';

/// Holds the onboarding draft and persists it on completion.
class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void setGoal(Goal g) => state = state.copyWith(goal: g);
  void setDob(DateTime d) => state = state.copyWith(dob: d);
  void setWeight(double kg) => state = state.copyWith(weightKg: kg);
  void setHeight(double cm) => state = state.copyWith(heightCm: cm);
  void setSex(Sex s) => state = state.copyWith(sex: s);
  void setDiet(DietPreference d) => state = state.copyWith(diet: d);
  void setCuisine(CuisinePreference c) => state = state.copyWith(cuisine: c);
  void setActivity(ActivityLevel a) => state = state.copyWith(activity: a);

  void toggleCondition(HealthCondition c) {
    final list = [...state.conditions];
    // `none` is exclusive: choosing it clears the rest, and vice-versa.
    if (c == HealthCondition.none) {
      state = state.copyWith(
          conditions: list.contains(c) ? const [] : const [HealthCondition.none]);
      return;
    }
    list.remove(HealthCondition.none);
    list.contains(c) ? list.remove(c) : list.add(c);
    state = state.copyWith(conditions: list);
  }

  /// Persist the draft as the profile. Returns false if incomplete/invalid.
  Future<bool> finish() async {
    final now = DateTime.now();
    final d = state;
    if (!d.complete(now)) return false;
    final record = d.toRecord(onboardingComplete: true);
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.save(record, userId: ref.read(currentUserIdProvider));
    return true;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
        OnboardingController.new);
