import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

/// A normalized seed row (source-agnostic). source / licence / confidence are
/// carried explicitly (CLAUDE.md rule 7) so every reference row proves its
/// provenance regardless of which corpus produced it.
class FoodSeedEntry {
  const FoodSeedEntry({
    required this.id,
    required this.name,
    this.nameHi,
    required this.type,
    this.foodGroup,
    required this.energyKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fiberG,
    this.servingLabel,
    this.servingGrams,
    required this.source,
    required this.licence,
    required this.confidence,
    this.sourceRef,
  });

  final String id;
  final String name;
  final String? nameHi;
  final String type;
  final String? foodGroup;
  final double energyKcal, proteinG, carbG, fatG;
  final double? fiberG;
  final String? servingLabel;
  final double? servingGrams;
  final String source, licence;
  final double confidence;
  final String? sourceRef;
}

/// Supplies the reference rows to seed. Injectable so tests use a tiny
/// in-memory set instead of loading the 1.5 MB USDA asset.
abstract class FoodSeedSource {
  Future<List<FoodSeedEntry>> load();
}

/// A fixed list — for tests and for composing corpora.
class InMemoryFoodSeed implements FoodSeedSource {
  const InMemoryFoodSeed(this.entries);
  final List<FoodSeedEntry> entries;
  @override
  Future<List<FoodSeedEntry>> load() async => entries;
}

/// Production seed: the labelled Indian sample (kept until INDB lands in M2.2b)
/// PLUS USDA SR Legacy (CC0) loaded from the bundled asset. The JSON is parsed
/// off the UI thread (compute) to avoid a jank frame on first launch.
class AssetFoodSeed implements FoodSeedSource {
  const AssetFoodSeed();

  static const _usdaAsset = 'assets/seed/foods_usda.json';

  @override
  Future<List<FoodSeedEntry>> load() async {
    final raw = await rootBundle.loadString(_usdaAsset);
    final usda = await compute(_parseUsda, raw);
    return [...kSampleFoods, ...usda];
  }
}

/// Top-level (compute requires it): parse the compact USDA asset. source /
/// licence / confidence are constant for USDA, so they are set here, not stored
/// per row in the asset.
List<FoodSeedEntry> _parseUsda(String raw) {
  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  return [
    for (final r in list)
      FoodSeedEntry(
        id: r['i'] as String,
        name: r['n'] as String,
        type: 'ingredient',
        foodGroup: r['g'] as String?,
        energyKcal: (r['e'] as num).toDouble(),
        proteinG: (r['p'] as num).toDouble(),
        carbG: (r['c'] as num).toDouble(),
        fatG: (r['f'] as num).toDouble(),
        fiberG: (r['fb'] as num?)?.toDouble(),
        servingLabel: r['sl'] as String?,
        servingGrams: (r['sg'] as num?)?.toDouble(),
        source: 'usda_fdc',
        licence: 'CC0',
        confidence: 0.9,
        sourceRef: r['r'] as String?,
      ),
  ];
}

/// The labelled Indian sample from M2.1 — approximate values, honestly tagged
/// source='sample' (NOT faked as indb/usda). Replaced by real INDB in M2.2b.
final List<FoodSeedEntry> kSampleFoods = [
  _s('sample-roti', 'Roti (Chapati)', 'dish', 297, 11, 51, 7.5,
      hi: 'रोटी', grp: 'cereals', sl: '1 roti', sg: 40),
  _s('sample-rice', 'Cooked Rice', 'dish', 130, 2.7, 28, 0.3,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-dal-tadka', 'Dal Tadka', 'dish', 120, 6, 15, 4,
      hi: 'दाल तड़का', grp: 'pulses', sl: '1 katori', sg: 150),
  _s('sample-rajma', 'Rajma (cooked)', 'dish', 140, 8, 20, 3,
      grp: 'pulses', sl: '1 katori', sg: 150),
  _s('sample-chole', 'Chole (Chickpea curry)', 'dish', 180, 8, 22, 7,
      grp: 'pulses', sl: '1 katori', sg: 150),
  _s('sample-idli', 'Idli', 'dish', 130, 4, 26, 0.5,
      grp: 'cereals', sl: '1 idli', sg: 35),
  _s('sample-dosa', 'Plain Dosa', 'dish', 168, 4, 29, 4,
      grp: 'cereals', sl: '1 dosa', sg: 80),
  _s('sample-poha', 'Poha', 'dish', 130, 2.5, 27, 2,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-upma', 'Upma', 'dish', 150, 3.5, 25, 4,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-paneer', 'Paneer', 'ingredient', 265, 18, 1.2, 21,
      hi: 'पनीर', grp: 'dairy', sl: '100 g', sg: 100),
  _s('sample-paneer-butter-masala', 'Paneer Butter Masala', 'dish', 230, 9, 10,
      18, grp: 'dishes', sl: '1 katori', sg: 150),
  _s('sample-curd', 'Curd (Dahi)', 'ingredient', 60, 3.5, 4.7, 3.3,
      hi: 'दही', grp: 'dairy', sl: '1 katori', sg: 150),
  _s('sample-milk', 'Milk (whole)', 'ingredient', 62, 3.2, 4.8, 3.3,
      grp: 'dairy', sl: '1 glass', sg: 200),
  _s('sample-egg', 'Boiled Egg', 'ingredient', 155, 13, 1.1, 11,
      grp: 'egg', sl: '1 egg', sg: 50),
  _s('sample-chicken-curry', 'Chicken Curry', 'dish', 180, 15, 5, 11,
      grp: 'meat', sl: '1 katori', sg: 150),
  _s('sample-banana', 'Banana', 'ingredient', 89, 1.1, 23, 0.3,
      hi: 'केला', grp: 'fruits', sl: '1 banana', sg: 120),
  _s('sample-apple', 'Apple', 'ingredient', 52, 0.3, 14, 0.2,
      grp: 'fruits', sl: '1 apple', sg: 180),
  _s('sample-almonds', 'Almonds', 'ingredient', 579, 21, 22, 50,
      grp: 'nuts', sl: '10 pieces', sg: 12),
  _s('sample-aloo-sabzi', 'Aloo Sabzi', 'dish', 120, 2.5, 18, 4.5,
      grp: 'vegetables', sl: '1 katori', sg: 150),
  _s('sample-mixed-veg', 'Mixed Vegetable Curry', 'dish', 110, 3, 14, 5,
      grp: 'vegetables', sl: '1 katori', sg: 150),
  _s('sample-samosa', 'Samosa', 'dish', 262, 4, 32, 13,
      grp: 'snacks', sl: '1 samosa', sg: 60),
  _s('sample-paratha', 'Aloo Paratha', 'dish', 280, 6, 40, 10,
      grp: 'cereals', sl: '1 paratha', sg: 100),
  _s('sample-tea', 'Masala Chai (with milk & sugar)', 'dish', 60, 1.5, 9, 2,
      grp: 'beverages', sl: '1 cup', sg: 120),
  _s('sample-coffee', 'Coffee (with milk & sugar)', 'dish', 55, 1.5, 8, 2,
      grp: 'beverages', sl: '1 cup', sg: 120),
  _s('sample-dal-khichdi', 'Dal Khichdi', 'dish', 130, 5, 20, 3,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-sambar', 'Sambar', 'dish', 85, 3.5, 12, 2.5,
      grp: 'pulses', sl: '1 katori', sg: 150),
  _s('sample-vada', 'Medu Vada', 'dish', 245, 6, 28, 12,
      grp: 'snacks', sl: '1 vada', sg: 50),
  _s('sample-gulab-jamun', 'Gulab Jamun', 'dish', 300, 4, 45, 12,
      grp: 'sweets', sl: '1 piece', sg: 45),
  _s('sample-roti-sabzi', 'Roti with Sabzi', 'dish', 200, 6, 30, 7,
      grp: 'dishes', sl: '1 plate', sg: 200),
  _s('sample-fish-curry', 'Fish Curry', 'dish', 150, 16, 4, 8,
      grp: 'meat', sl: '1 katori', sg: 150),
  _s('sample-peanuts', 'Roasted Peanuts', 'ingredient', 567, 26, 16, 49,
      grp: 'nuts', sl: '1 handful', sg: 30),
  _s('sample-oats', 'Oats (cooked)', 'dish', 71, 2.5, 12, 1.5,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-moong-dal', 'Moong Dal (cooked)', 'dish', 105, 7, 15, 1.5,
      grp: 'pulses', sl: '1 katori', sg: 150),
  _s('sample-palak-paneer', 'Palak Paneer', 'dish', 180, 8, 8, 13,
      grp: 'dishes', sl: '1 katori', sg: 150),
  _s('sample-butter-chicken', 'Butter Chicken', 'dish', 240, 16, 8, 16,
      grp: 'meat', sl: '1 katori', sg: 150),
  _s('sample-naan', 'Naan', 'dish', 310, 9, 50, 8,
      grp: 'cereals', sl: '1 naan', sg: 90),
  _s('sample-jeera-rice', 'Jeera Rice', 'dish', 160, 3, 30, 3,
      grp: 'cereals', sl: '1 katori', sg: 150),
  _s('sample-raita', 'Boondi Raita', 'dish', 90, 3, 8, 5,
      grp: 'dairy', sl: '1 katori', sg: 150),
  _s('sample-pav-bhaji', 'Pav Bhaji', 'dish', 200, 5, 26, 9,
      grp: 'snacks', sl: '1 plate', sg: 200),
  _s('sample-biryani', 'Veg Biryani', 'dish', 190, 4, 30, 6,
      grp: 'dishes', sl: '1 plate', sg: 200),
];

FoodSeedEntry _s(String id, String name, String type, double kcal,
        double protein, double carb, double fat,
        {String? hi, String? grp, String? sl, double? sg}) =>
    FoodSeedEntry(
      id: id,
      name: name,
      nameHi: hi,
      type: type,
      foodGroup: grp,
      energyKcal: kcal,
      proteinG: protein,
      carbG: carb,
      fatG: fat,
      servingLabel: sl,
      servingGrams: sg,
      source: 'sample',
      licence: 'CC0',
      confidence: 0.5,
    );
