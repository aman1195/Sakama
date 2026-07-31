import 'dart:convert';

import '../domain/plan.dart';

/// Why an import was rejected — drives both the user-facing message and tests.
enum PlanImportProblem {
  /// Nothing pasted.
  empty,

  /// Not valid JSON, or not a JSON object at the top level (review #68 note 1:
  /// the string guard in front of the tolerant [Plan.fromJson]).
  malformedJson,

  /// The plan is tagged for a schema newer than this client understands
  /// (review #68 note 2). Parsing it best-effort would silently misread it, so
  /// we refuse rather than apply a plan we cannot honour.
  unsupportedVersion,

  /// Parses, but defines no day types — it would do nothing if applied.
  noDayTypes,
}

/// The outcome of validating a pasted/loaded plan string. Sealed so the caller
/// must handle both branches.
sealed class PlanImportResult {
  const PlanImportResult();
}

class PlanImportOk extends PlanImportResult {
  const PlanImportOk(this.plan, this.config);

  /// The parsed plan (for a name/summary preview).
  final Plan plan;

  /// The exact string to persist — stored verbatim so the engine reads what was
  /// authored ([PlanRepository.savePlan]).
  final String config;
}

class PlanImportError extends PlanImportResult {
  const PlanImportError(this.problem, this.message);
  final PlanImportProblem problem;
  final String message;
}

/// Validates a plan authored elsewhere (pasted by the user, or produced by AI
/// in 4.4) before it is saved. This is the operational home of review #68's two
/// notes: the malformed-JSON / non-Map guard (note 1) and the schema-version
/// gate (note 2). Pure — no I/O — so it is trivially testable.
class PlanImporter {
  const PlanImporter();

  PlanImportResult validate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const PlanImportError(
          PlanImportProblem.empty, 'Paste a plan to import.');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const PlanImportError(PlanImportProblem.malformedJson,
          "That doesn't look like valid JSON.");
    }
    if (decoded is! Map) {
      return const PlanImportError(PlanImportProblem.malformedJson,
          'A plan must be a JSON object.');
    }

    // Safe: fromJson is tolerant and never throws on a Map. We parse only to
    // read the tagged version and day types; we do not APPLY it until it clears
    // the gates below.
    final plan = Plan.fromJson(decoded.cast<String, dynamic>());

    if (plan.schemaVersion > kPlanSchemaVersion) {
      return PlanImportError(
          PlanImportProblem.unsupportedVersion,
          'This plan needs a newer version of Sakama (plan format '
          'v${plan.schemaVersion}). Please update the app, then try again.');
    }
    if (plan.dayTypes.isEmpty) {
      return const PlanImportError(PlanImportProblem.noDayTypes,
          'This plan has no day types, so it would not change anything.');
    }

    return PlanImportOk(plan, text);
  }
}
