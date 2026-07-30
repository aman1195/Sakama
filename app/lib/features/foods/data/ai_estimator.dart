import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/food_estimate.dart';
import '../domain/food_search.dart';

/// Thrown when estimation is unavailable (offline, gateway down, budget hit).
class EstimateException implements Exception {
  EstimateException(this.message,
      {this.budgetExhausted = false, this.notFood = false});
  final String message;
  /// True when the server said the user's daily cap is spent (rule 9) —
  /// the UI words that differently from a transient failure.
  final bool budgetExhausted;
  /// True when the model said the input is not a food — "that doesn't look
  /// like a food" beats a generic failure message (review #46, minor).
  final bool notFood;
  @override
  String toString() => 'EstimateException: $message';
}

/// Estimates nutrition for a dish name. Injectable so tests never touch the
/// network and the UI can be built before the gateway is deployed.
abstract class AiEstimator {
  Future<FoodEstimate> estimate(String dishName, {String? byok});
}

/// Production path per ADR 0011: Supabase Edge Function -> managed gateway ->
/// provider (paid tier). The client sends ONLY the dish name + its JWT; the
/// provider key lives server-side (CLAUDE.md rule 3), and the per-user budget
/// is enforced in the function (rule 9).
class EdgeFunctionAiEstimator implements AiEstimator {
  EdgeFunctionAiEstimator({SupabaseClient? client}) : _client = client; // ignore: prefer_initializing_formals
  final SupabaseClient? _client;

  static const _function = 'estimate-food';

  @override
  Future<FoodEstimate> estimate(String dishName, {String? byok}) async {
    final supabase = _client ?? Supabase.instance.client;
    final FunctionResponse res;
    try {
      res = await supabase.functions
          .invoke(_function, body: {'dish': dishName.trim(), 'byok': ?byok});
    } on FunctionException catch (e) {
      if (e.status == 429) {
        throw EstimateException('daily limit reached', budgetExhausted: true);
      }
      throw EstimateException('gateway error ${e.status}');
    } catch (e) {
      throw EstimateException('network error: $e');
    }
    final data = res.data;
    final raw = data is String ? data : jsonEncode(data);
    if (isNotFood(raw)) {
      throw EstimateException('not a food', notFood: true);
    }
    final parsed = parseEstimate(raw, fallbackName: dishName);
    if (parsed == null) throw EstimateException('malformed estimate');
    return parsed;
  }

  /// The model's in-band "this is not a food" signal.
  static bool isNotFood(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map && j['error'] == 'not_food';
    } catch (_) {
      return false;
    }
  }

  /// Parse + VALIDATE a gateway response. Model output is untrusted input:
  /// missing/absurd numbers are rejected (null), never logged into a health
  /// diary. Confidence is clamped to [0.2, 0.4] — always below
  /// [verifiedConfidenceFloor] so ranking demotes estimates (issue #27).
  static FoodEstimate? parseEstimate(String raw, {required String fallbackName}) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    double? num_(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

    final kcal = num_(j['energy_kcal_100g']);
    final protein = num_(j['protein_g_100g']);
    final carb = num_(j['carb_g_100g']);
    final fat = num_(j['fat_g_100g']);
    if (kcal == null || protein == null || carb == null || fat == null) {
      return null;
    }
    // Sanity bounds per 100 g: kcal 5..900 (oil is ~884), macros 0..100.
    if (kcal < 5 || kcal > 900) return null;
    if ([protein, carb, fat].any((m) => m < 0 || m > 100)) return null;
    // Atwater cross-check: stated kcal within 40% of 4P+4C+9F — catches a
    // model inventing incoherent numbers.
    final atwater = protein * 4 + carb * 4 + fat * 9;
    if (atwater > 0 && (kcal - atwater).abs() / atwater > 0.4) return null;

    final rawConf = num_(j['confidence']) ?? 0.3;
    final confidence = rawConf.clamp(0.2, 0.4).toDouble();
    assert(confidence < verifiedConfidenceFloor);

    // Serving fields get bounds too (review #46, minor — symmetry with the
    // macros): a plausible single serving is 1..2000 g, else drop it and let
    // the user enter an amount.
    final servingGrams = num_(j['serving_grams']);
    final servingOk =
        servingGrams != null && servingGrams >= 1 && servingGrams <= 2000;

    final name = (j['name'] as String?)?.trim();
    return FoodEstimate(
      name: (name == null || name.isEmpty) ? fallbackName : name,
      energyKcal: kcal,
      proteinG: protein,
      carbG: carb,
      fatG: fat,
      fiberG: num_(j['fiber_g_100g']),
      servingLabel: (j['serving_label'] as String?)?.trim(),
      servingGrams: servingOk ? servingGrams : null,
      confidence: confidence,
      assumptions: (j['assumptions'] as String?)?.trim(),
    );
  }
}
