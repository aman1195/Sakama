// Pure food-search scoring/ranking — no DB, so it is exhaustively unit-tested.
//
// The repository does a broad SQL `LIKE` fetch, then ranks in Dart with this:
// verified data must sort above weak matches and AI estimates (CLAUDE.md
// rule 7 — confidence is a ranking signal, not decoration).

/// Match quality of [query] against a food [name]. Higher is better;
/// -1 means "no match" (the caller drops it). Case- and whitespace-insensitive.
///   3 = exact name          ("dal" vs "Dal")
///   2 = name starts with q  ("dal" vs "Dal Tadka")
///   1 = a word starts with q("tad" vs "Dal Tadka")
///   0 = substring anywhere  ("ada" vs "Dal Tadka")
int foodMatchScore(String query, String name) {
  final q = query.trim().toLowerCase();
  final n = name.trim().toLowerCase();
  if (q.isEmpty) return -1;
  if (n == q) return 3;
  if (n.startsWith(q)) return 2;
  if (n.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
  if (n.contains(q)) return 0;
  return -1;
}

/// A rankable candidate — the minimal surface the ranker needs, so the sort is
/// testable without constructing Drift rows.
abstract class RankableFood {
  String get name;
  double get confidence;
}

/// Below this, a row is treated as UNVERIFIED (AI estimates, rough guesses)
/// and is demoted one match tier by [rankFoods]. Our shipped data sits at or
/// above it today (USDA 0.9, labelled sample 0.5), so the demotion is inert
/// until AI estimation lands in M2.4 — which is exactly when it must exist.
const double verifiedConfidenceFloor = 0.5;

/// The ranking decision (issue #27), made explicitly now that mixed-provenance
/// data ships:
///
///  1. **Match tier is primary.** Users expect what they literally typed to
///     rank first; that is what makes search feel correct.
///  2. **Confidence breaks ties within a tier** — so verified USDA (0.9) sorts
///     above a labelled sample (0.5) on an equal textual match.
///  3. **Sub-floor rows are demoted ONE tier.** A low-confidence AI estimate
///     must match *distinctly* better than verified data to outrank it: an
///     exact-name estimate no longer beats a prefix-match verified row, but it
///     still beats a mere substring match. This is the targeted fix for "an
///     ai_estimate with an exact hit outranks a verified source", without
///     letting confidence swamp textual relevance everywhere.
int _effectiveTier(int matchScore, double confidence) =>
    confidence < verifiedConfidenceFloor ? matchScore - 1 : matchScore;

/// Rank [candidates] for [query]: effective tier desc, then confidence desc,
/// then name A→Z. Non-matches are dropped. Stable, pure, returns a new list.
List<T> rankFoods<T extends RankableFood>(String query, List<T> candidates) {
  final scored = <(int, T)>[];
  for (final c in candidates) {
    final s = foodMatchScore(query, c.name);
    if (s >= 0) scored.add((_effectiveTier(s, c.confidence), c));
  }
  scored.sort((a, b) {
    if (a.$1 != b.$1) return b.$1.compareTo(a.$1); // score desc
    final byConf = b.$2.confidence.compareTo(a.$2.confidence);
    if (byConf != 0) return byConf; // confidence desc
    return a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
  });
  return [for (final e in scored) e.$2];
}
