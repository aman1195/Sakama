/// Shared validation bounds for body inputs, so onboarding and weight logging
/// (and anything later) cannot drift apart (PR #23 review nit 2).
class BodyMetrics {
  const BodyMetrics._();
  static const minWeightKg = 20.0;
  static const maxWeightKg = 300.0;
  static const minHeightCm = 100.0;
  static const maxHeightCm = 250.0;
  static const minAgeYears = 13;
  static const maxAgeYears = 100;
}
