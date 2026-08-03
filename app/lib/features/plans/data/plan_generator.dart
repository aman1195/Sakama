import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../onboarding/domain/profile_record.dart';
import '../application/plan_importer.dart';

/// A compact, PII-light projection of the profile for the model: age (not dob),
/// no user_id, no free text. Pure given [now] so it is trivially tested.
Map<String, dynamic> planProfileProjection(ProfileRecord p, DateTime now) => {
      'age': p.ageYearsAt(now),
      'sex': p.sex.name,
      'height_cm': p.heightCm,
      'weight_kg': p.weightKg,
      'activity': p.activity.name,
      'goal': p.goal.name,
      'diet': p.diet.name,
      'cuisine': p.cuisine.name,
      'conditions': p.conditions.map((c) => c.name).toList(),
    };

/// Thrown when generation is unavailable for a transport reason (offline,
/// gateway down, or the daily budget is spent). A *validation* failure of the
/// model output is NOT this — that comes back as a [PlanImportError] so the UI
/// can word it differently.
class PlanGenerationException implements Exception {
  PlanGenerationException(this.message, {this.budgetExhausted = false});
  final String message;

  /// True when the server said the user's daily plan-generation cap is spent
  /// (rule 9) — the UI words that differently from a transient failure.
  final bool budgetExhausted;

  @override
  String toString() => 'PlanGenerationException: $message';
}

/// Turns an onboarded profile into a validated plan. Injectable so tests never
/// touch the network and the UI can be built before the gateway is deployed
/// (mirrors [AiEstimator]).
abstract class PlanGenerator {
  /// Returns [PlanImportOk] with a ready-to-save plan, or a [PlanImportError]
  /// when even a retry produced an invalid plan. Throws
  /// [PlanGenerationException] for transport/budget failures.
  Future<PlanImportResult> generate(ProfileRecord profile, {String? byok});
}

/// Production path (ADR 0011): Supabase Edge Function `generate-plan` → managed
/// gateway → provider (paid tier). The client sends only a compact profile
/// projection + its JWT; the provider key lives server-side (CLAUDE.md rule 3),
/// and the per-user budget is enforced in the function (rule 9).
///
/// The model output is untrusted: it is validated here with the SAME
/// [PlanImporter] used by manual import (#71) — one validation path. One silent
/// retry covers a transient unparseable/day-type-less generation (design §8);
/// a schema-version rejection is not retried (a retry cannot fix it).
class EdgeFunctionPlanGenerator implements PlanGenerator {
  EdgeFunctionPlanGenerator({SupabaseClient? client, DateTime Function()? now})
      : _client = client, // ignore: prefer_initializing_formals
        _now = now ?? DateTime.now;
  final SupabaseClient? _client;
  final DateTime Function() _now;

  static const _function = 'generate-plan';
  static const _importer = PlanImporter();

  @override
  Future<PlanImportResult> generate(ProfileRecord profile,
      {String? byok}) async {
    final first = await _attempt(profile, byok);
    if (first is PlanImportOk) return first;
    if (first is PlanImportError &&
        first.problem == PlanImportProblem.unsupportedVersion) {
      return first; // a newer-schema plan won't validate on retry either
    }
    return _attempt(profile, byok); // one silent retry
  }

  Future<PlanImportResult> _attempt(ProfileRecord profile, String? byok) async {
    final raw = await fetchRaw(profile, byok);
    return _importer.validate(raw);
  }

  /// The raw model-JSON string from the Edge Function. Isolated (overridable)
  /// so the generate() orchestration (retry + validation) can be tested without
  /// the network.
  Future<String> fetchRaw(ProfileRecord profile, String? byok) async {
    final supabase = _client ?? Supabase.instance.client;
    final FunctionResponse res;
    try {
      res = await supabase.functions.invoke(_function, body: {
        'profile': planProfileProjection(profile, _now()),
        'byok': ?byok,
      });
    } on FunctionException catch (e) {
      if (e.status == 429) {
        throw PlanGenerationException('daily limit reached',
            budgetExhausted: true);
      }
      throw PlanGenerationException('gateway error ${e.status}');
    } catch (e) {
      throw PlanGenerationException('network error: $e');
    }
    final data = res.data;
    return data is String ? data : jsonEncode(data);
  }
}
