import 'dart:convert';

import '../../home/domain/day_totals.dart' show Meal;

/// A action Vita PROPOSES. Nothing here is written until the user confirms it
/// (ADR 0016 decision 2) — a draft is a suggestion rendered as a confirm card,
/// never a side effect.
sealed class ToolDraft {
  const ToolDraft();

  /// One-line summary for the confirm card.
  String get summary;
}

class LogFoodDraft extends ToolDraft {
  const LogFoodDraft({
    required this.meal,
    required this.name,
    required this.energyKcal,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.grams,
  });

  final Meal meal;
  final String name;
  final double energyKcal, proteinG, carbG, fatG;
  final double? grams;

  @override
  String get summary {
    final g = grams == null ? '' : '${_n(grams!)} g · ';
    return '${meal.label} · $name · $g${_n(energyKcal)} kcal';
  }
}

class LogWaterDraft extends ToolDraft {
  const LogWaterDraft(this.amountMl);
  final int amountMl;
  @override
  String get summary => 'Water · $amountMl ml';
}

class LogWeightDraft extends ToolDraft {
  const LogWeightDraft(this.weightKg);
  final double weightKg;
  @override
  String get summary => 'Weight · ${_n(weightKg)} kg';
}

String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Why a proposed tool call was refused. Surfacing the reason keeps a rejected
/// draft debuggable instead of silently vanishing.
enum ToolRejection {
  notJson,
  unknownTool,
  missingField,
  outOfRange,

  /// Stated calories disagree with 4P+4C+9F beyond tolerance — catches a
  /// transposed or invented number that is individually in range.
  macrosInconsistent,
}

/// Parses UNTRUSTED model output into a [ToolDraft], bounds-checking every
/// argument BEFORE a draft can exist.
///
/// This is the standing requirement from the #82 review: propose-confirm guards
/// *intent* (the user sees what will be logged), but not *magnitude* — a
/// plausible-looking 800 kcal can slip past a distracted tap. An absurd value
/// must therefore never reach the confirm card at all. Mirrors the bounds +
/// Atwater discipline already applied to AI estimates.
class ToolCallParser {
  const ToolCallParser();

  // A single logged entry, not a per-100g reference row.
  static const _kcalMin = 1.0, _kcalMax = 5000.0;
  static const _macroMax = 500.0; // grams of one macro in one entry
  static const _gramsMin = 1.0, _gramsMax = 5000.0;
  static const _waterMinMl = 10, _waterMaxMl = 5000;
  static const _weightMinKg = 20.0, _weightMaxKg = 500.0;
  static const _nameMax = 80;

  /// Atwater tolerance, matching the AI-estimate path.
  static const _atwaterTolerance = 0.4;

  /// Parse one tool call. Returns the draft, or the reason it was refused.
  ({ToolDraft? draft, ToolRejection? rejection}) parse(String rawJson) {
    Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return (draft: null, rejection: ToolRejection.notJson);
    }
    if (decoded is! Map) return (draft: null, rejection: ToolRejection.notJson);
    final j = decoded.cast<String, dynamic>();
    final args = j['arguments'] is Map
        ? (j['arguments'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return switch (_asStr(j['tool'])) {
      'log_food' => _food(args),
      'log_water' => _water(args),
      'log_weight' => _weight(args),
      _ => (draft: null, rejection: ToolRejection.unknownTool),
    };
  }

  ({ToolDraft? draft, ToolRejection? rejection}) _food(
      Map<String, dynamic> a) {
    final name = _asStr(a['name'])?.trim();
    final kcal = _asNum(a['energy_kcal']);
    final mealKey = _asStr(a['meal']);
    final meal = Meal.values.where((m) => m.key == mealKey).firstOrNull;
    if (name == null || name.isEmpty || kcal == null || meal == null) {
      return (draft: null, rejection: ToolRejection.missingField);
    }
    if (name.length > _nameMax) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }
    final protein = _asNum(a['protein_g']) ?? 0;
    final carb = _asNum(a['carb_g']) ?? 0;
    final fat = _asNum(a['fat_g']) ?? 0;
    final grams = _asNum(a['grams']);

    if (kcal < _kcalMin || kcal > _kcalMax) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }
    if ([protein, carb, fat].any((m) => m < 0 || m > _macroMax)) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }
    if (grams != null && (grams < _gramsMin || grams > _gramsMax)) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }

    // Atwater cross-check — only when macros were actually stated, so a
    // calories-only entry ("roughly 200 kcal") is still allowed.
    final atwater = 4 * protein + 4 * carb + 9 * fat;
    if (atwater > 0 &&
        (kcal - atwater).abs() / atwater > _atwaterTolerance) {
      return (draft: null, rejection: ToolRejection.macrosInconsistent);
    }

    return (
      draft: LogFoodDraft(
        meal: meal,
        name: name,
        energyKcal: kcal,
        proteinG: protein,
        carbG: carb,
        fatG: fat,
        grams: grams,
      ),
      rejection: null
    );
  }

  ({ToolDraft? draft, ToolRejection? rejection}) _water(
      Map<String, dynamic> a) {
    final ml = _asNum(a['amount_ml'])?.round();
    if (ml == null) return (draft: null, rejection: ToolRejection.missingField);
    if (ml < _waterMinMl || ml > _waterMaxMl) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }
    return (draft: LogWaterDraft(ml), rejection: null);
  }

  ({ToolDraft? draft, ToolRejection? rejection}) _weight(
      Map<String, dynamic> a) {
    final kg = _asNum(a['weight_kg']);
    if (kg == null) return (draft: null, rejection: ToolRejection.missingField);
    if (kg < _weightMinKg || kg > _weightMaxKg) {
      return (draft: null, rejection: ToolRejection.outOfRange);
    }
    return (draft: LogWeightDraft(kg), rejection: null);
  }

  static String? _asStr(Object? v) => v is String ? v : null;

  /// Non-finite values must be rejected HERE, not by the bounds checks —
  /// every comparison against NaN is false, so a NaN would slip past both the
  /// range guard AND the Atwater check and land in the diary as calories.
  static double? _asNum(Object? v) {
    final d = switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    return (d != null && d.isFinite) ? d : null;
  }
}
