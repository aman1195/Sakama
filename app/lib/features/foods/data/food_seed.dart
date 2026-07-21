// Slice-2.1 SAMPLE seed — deliberately labelled, NOT real INDB/USDA data.
//
// I do not have the licensed corpora on hand, and faking provenance (tagging
// invented macros as source=indb/confidence=1.0) would defeat the entire
// point of the provenance columns (CLAUDE.md rule 7) and this project's
// verify-before-asserting rule. So every row here is honestly tagged
// source='sample', licence='CC0', confidence=0.5, with approximate per-100g
// values for well-known foods — enough to prove the schema + search + log
// path. M2.2 replaces this wholesale with real INDB (CC BY 4.0) + USDA (CC0)
// ingestion, source-tagged per row.
//
// Values are per 100 g (CLAUDE.md canonical basis). fiberG omitted where not
// meaningful for the sample.

class SeedFood {
  const SeedFood(this.id, this.name, this.type, this.kcal, this.protein,
      this.carb, this.fat,
      {this.nameHi, this.group, this.servingLabel, this.servingGrams});
  final String id;
  final String name;
  final String type;
  final double kcal, protein, carb, fat;
  final String? nameHi;
  final String? group;
  final String? servingLabel;
  final double? servingGrams;
}

/// ~40 common Indian + generic foods. Approximate, sample-tagged.
const kFoodSeed = <SeedFood>[
  SeedFood('sample-roti', 'Roti (Chapati)', 'dish', 297, 11, 51, 7.5,
      nameHi: 'रोटी', group: 'cereals', servingLabel: '1 roti', servingGrams: 40),
  SeedFood('sample-rice', 'Cooked Rice', 'dish', 130, 2.7, 28, 0.3,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-dal-tadka', 'Dal Tadka', 'dish', 120, 6, 15, 4,
      nameHi: 'दाल तड़का', group: 'pulses', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-rajma', 'Rajma (cooked)', 'dish', 140, 8, 20, 3,
      group: 'pulses', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-chole', 'Chole (Chickpea curry)', 'dish', 180, 8, 22, 7,
      group: 'pulses', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-idli', 'Idli', 'dish', 130, 4, 26, 0.5,
      group: 'cereals', servingLabel: '1 idli', servingGrams: 35),
  SeedFood('sample-dosa', 'Plain Dosa', 'dish', 168, 4, 29, 4,
      group: 'cereals', servingLabel: '1 dosa', servingGrams: 80),
  SeedFood('sample-poha', 'Poha', 'dish', 130, 2.5, 27, 2,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-upma', 'Upma', 'dish', 150, 3.5, 25, 4,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-paneer', 'Paneer', 'ingredient', 265, 18, 1.2, 21,
      nameHi: 'पनीर', group: 'dairy', servingLabel: '100 g', servingGrams: 100),
  SeedFood('sample-paneer-butter-masala', 'Paneer Butter Masala', 'dish', 230,
      9, 10, 18, group: 'dishes', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-curd', 'Curd (Dahi)', 'ingredient', 60, 3.5, 4.7, 3.3,
      nameHi: 'दही', group: 'dairy', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-milk', 'Milk (whole)', 'ingredient', 62, 3.2, 4.8, 3.3,
      group: 'dairy', servingLabel: '1 glass', servingGrams: 200),
  SeedFood('sample-egg', 'Boiled Egg', 'ingredient', 155, 13, 1.1, 11,
      group: 'egg', servingLabel: '1 egg', servingGrams: 50),
  SeedFood('sample-chicken-curry', 'Chicken Curry', 'dish', 180, 15, 5, 11,
      group: 'meat', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-banana', 'Banana', 'ingredient', 89, 1.1, 23, 0.3,
      nameHi: 'केला', group: 'fruits', servingLabel: '1 banana', servingGrams: 120),
  SeedFood('sample-apple', 'Apple', 'ingredient', 52, 0.3, 14, 0.2,
      group: 'fruits', servingLabel: '1 apple', servingGrams: 180),
  SeedFood('sample-almonds', 'Almonds', 'ingredient', 579, 21, 22, 50,
      group: 'nuts', servingLabel: '10 pieces', servingGrams: 12),
  SeedFood('sample-aloo-sabzi', 'Aloo Sabzi', 'dish', 120, 2.5, 18, 4.5,
      group: 'vegetables', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-mixed-veg', 'Mixed Vegetable Curry', 'dish', 110, 3, 14, 5,
      group: 'vegetables', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-samosa', 'Samosa', 'dish', 262, 4, 32, 13,
      group: 'snacks', servingLabel: '1 samosa', servingGrams: 60),
  SeedFood('sample-paratha', 'Aloo Paratha', 'dish', 280, 6, 40, 10,
      group: 'cereals', servingLabel: '1 paratha', servingGrams: 100),
  SeedFood('sample-tea', 'Masala Chai (with milk & sugar)', 'dish', 60, 1.5, 9,
      2, group: 'beverages', servingLabel: '1 cup', servingGrams: 120),
  SeedFood('sample-coffee', 'Coffee (with milk & sugar)', 'dish', 55, 1.5, 8, 2,
      group: 'beverages', servingLabel: '1 cup', servingGrams: 120),
  SeedFood('sample-dal-khichdi', 'Dal Khichdi', 'dish', 130, 5, 20, 3,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-sambar', 'Sambar', 'dish', 85, 3.5, 12, 2.5,
      group: 'pulses', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-vada', 'Medu Vada', 'dish', 245, 6, 28, 12,
      group: 'snacks', servingLabel: '1 vada', servingGrams: 50),
  SeedFood('sample-gulab-jamun', 'Gulab Jamun', 'dish', 300, 4, 45, 12,
      group: 'sweets', servingLabel: '1 piece', servingGrams: 45),
  SeedFood('sample-roti-sabzi', 'Roti with Sabzi', 'dish', 200, 6, 30, 7,
      group: 'dishes', servingLabel: '1 plate', servingGrams: 200),
  SeedFood('sample-fish-curry', 'Fish Curry', 'dish', 150, 16, 4, 8,
      group: 'meat', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-peanuts', 'Roasted Peanuts', 'ingredient', 567, 26, 16, 49,
      group: 'nuts', servingLabel: '1 handful', servingGrams: 30),
  SeedFood('sample-oats', 'Oats (cooked)', 'dish', 71, 2.5, 12, 1.5,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-moong-dal', 'Moong Dal (cooked)', 'dish', 105, 7, 15, 1.5,
      group: 'pulses', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-palak-paneer', 'Palak Paneer', 'dish', 180, 8, 8, 13,
      group: 'dishes', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-butter-chicken', 'Butter Chicken', 'dish', 240, 16, 8, 16,
      group: 'meat', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-naan', 'Naan', 'dish', 310, 9, 50, 8,
      group: 'cereals', servingLabel: '1 naan', servingGrams: 90),
  SeedFood('sample-jeera-rice', 'Jeera Rice', 'dish', 160, 3, 30, 3,
      group: 'cereals', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-raita', 'Boondi Raita', 'dish', 90, 3, 8, 5,
      group: 'dairy', servingLabel: '1 katori', servingGrams: 150),
  SeedFood('sample-pav-bhaji', 'Pav Bhaji', 'dish', 200, 5, 26, 9,
      group: 'snacks', servingLabel: '1 plate', servingGrams: 200),
  SeedFood('sample-biryani', 'Veg Biryani', 'dish', 190, 4, 30, 6,
      group: 'dishes', servingLabel: '1 plate', servingGrams: 200),
];
