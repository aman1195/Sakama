import 'food_search.dart';
import 'food_serving.dart';

/// A food from the reference corpus, as the UI consumes it. Drift-free: the
/// repository maps FoodRow -> Food so the presentation layer never sees a raw
/// database row. Implements [RankableFood] so search results can be ranked.
class Food implements RankableFood {
  const Food({
    required this.id,
    required this.name,
    this.nameHi,
    required this.type,
    required this.per100g,
    required this.source,
    required this.licence,
    required this.confidence,
    this.defaultServingLabel,
    this.defaultServingGrams,
  });

  final String id;
  @override
  final String name;
  final String? nameHi;
  final String type;

  /// Canonical per-100g nutrition; scale with [Macros.scaleTo] at log time.
  final Macros per100g;

  final String source;
  final String licence;
  @override
  final double confidence;

  final String? defaultServingLabel;
  final double? defaultServingGrams;
}
