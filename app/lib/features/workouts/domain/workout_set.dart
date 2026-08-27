import 'dart:convert';

/// One set of a strength exercise.
class WorkoutSet {
  const WorkoutSet({required this.reps, this.weightKg});
  final int reps;

  /// Null for bodyweight. NOT zero: "10 push-ups" and "10 reps at 0 kg" are
  /// the same event, but a stored 0 reads as a measurement that was taken.
  final double? weightKg;

  Map<String, Object?> toJson() =>
      {'reps': reps, if (weightKg != null) 'weight_kg': weightKg};

  /// Parse UNTRUSTED set JSON — it arrives from the model as well as from our
  /// own writes, so it is validated the same way tool calls are.
  static List<WorkoutSet> decode(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is! List) return const [];
      final out = <WorkoutSet>[];
      for (final item in d) {
        if (item is! Map) continue;
        final reps = _int(item['reps']);
        // A set with no reps is not a set. Dropped rather than defaulted to 1,
        // which would invent volume the user never did.
        if (reps == null || reps <= 0 || reps > 1000) continue;
        out.add(WorkoutSet(reps: reps, weightKg: _weight(item['weight_kg'])));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<WorkoutSet> sets) =>
      jsonEncode(sets.map((s) => s.toJson()).toList());

  static int? _int(Object? v) => switch (v) {
        int i => i,
        double d => d.isFinite ? d.round() : null,
        String s => int.tryParse(s),
        _ => null,
      };

  /// Non-finite must be rejected at coercion: every comparison against NaN is
  /// false, so a NaN would pass a range check and land in the volume total.
  /// Same trap as the tool-call parser and the memory extractor.
  static double? _weight(Object? v) {
    final d = switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    if (d == null || !d.isFinite || d < 0 || d > 1000) return null;
    return d;
  }
}
