/// Deterministic exercise-energy estimation.
///
/// Burn is COMPUTED, never asked of the model. A number the LLM invents would
/// be subtracted from the day's calorie target and change what the user eats,
/// so it has to come from a formula whose inputs we can show them.
///
/// Formula: kcal/min = MET * 3.5 * kg / 200 (standard ACSM form).
/// MET values are the commonly published figures for these activities; only a
/// handful are listed, chosen by hand, deliberately NOT a bulk ingest of a
/// compiled table (same discipline as CLAUDE.md rule 6 on food data).
///
/// Contrast with the weight-blind `caloriesPerHour / 60 * minutes` used
/// elsewhere in this space: at 40 minutes of running, a 55 kg and a 95 kg user
/// differ by roughly 270 kcal. Weight is not a rounding error.
abstract final class EnergyBurn {
  /// Activity -> (MET, phrases that mean it).
  ///
  /// Aliases are written out rather than stemmed. Stemming looks tidy and is
  /// wrong: "running" minus "ing" is "runn", which never matches "run". An
  /// explicit list is longer but every entry is reviewable.
  static const _table = <({double met, List<String> match})>[
    (met: 4.3, match: ['brisk walk', 'power walk', 'fast walk']),
    (met: 3.5, match: ['walk', 'stroll']),
    (met: 9.8, match: ['run', 'sprint']),
    (met: 7.0, match: ['jog']),
    (met: 7.5, match: ['cycl', 'bike', 'biking', 'spin class']),
    (met: 7.0, match: ['swim']),
    (met: 12.3, match: ['skipping', 'jump rope', 'skip rope']),
    (met: 7.0, match: ['row']),
    (met: 5.0, match: ['elliptical', 'cross trainer']),
    (met: 8.8, match: ['stair', 'step climb']),
    (met: 8.0, match: ['hiit', 'interval training']),
    (met: 2.5, match: ['yoga']),
    (met: 2.3, match: ['stretch', 'mobility']),
    (met: 3.0, match: ['pilates']),
    (met: 5.0, match: ['weight training', 'lifting', 'gym session', 'strength training']),
    (met: 7.2, match: ['circuit']),
    (met: 7.0, match: ['football', 'soccer']),
    (met: 4.8, match: ['cricket']),
    (met: 5.5, match: ['badminton']),
    (met: 7.3, match: ['tennis']),
    (met: 6.5, match: ['basketball']),
    (met: 5.0, match: ['danc', 'zumba']),
  ];

  /// MET for a free-text activity name, or null when we do not recognise it.
  ///
  /// Substring match on a lowercased name, longest matching phrase wins, so
  /// "evening brisk walk" scores as a brisk walk rather than a stroll. Table
  /// order is irrelevant by design: an ordering-dependent lookup is a bug
  /// waiting for someone to insert a row in the wrong place.
  static double? metFor(String activity) {
    final n = activity.toLowerCase().trim();
    if (n.isEmpty) return null;
    double? met;
    var bestLen = 0;
    for (final row in _table) {
      for (final phrase in row.match) {
        if (phrase.length > bestLen && n.contains(phrase)) {
          bestLen = phrase.length;
          met = row.met;
        }
      }
    }
    return met;
  }

  /// Estimated kcal, or null when the activity is unknown, the duration is
  /// missing, or we have no body weight. Null means "we do not know" and must
  /// stay null all the way to the row — a 0 would read as a measurement.
  static double? estimate({
    required String activity,
    required int? durationMin,
    required double? weightKg,
  }) {
    if (durationMin == null || durationMin <= 0) return null;
    if (weightKg == null || weightKg <= 0 || !weightKg.isFinite) return null;
    final met = metFor(activity);
    if (met == null) return null;
    final kcal = met * 3.5 * weightKg / 200 * durationMin;
    return kcal.isFinite ? double.parse(kcal.toStringAsFixed(0)) : null;
  }
}
