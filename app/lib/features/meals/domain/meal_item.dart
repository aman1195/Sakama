import 'dart:convert';

/// One entry in a saved meal: a pointer to a `user_foods` row, plus how much.
///
/// IDS AND PORTIONS, NEVER NUTRITION. A meal is a reusable definition, so
/// copying macros in would put OFF-derived values into a proprietary synced
/// table — the merge docs/architecture/08 §3 exists to prevent. The nutrition
/// is read from `user_foods` at display time, which follows a pointer to its
/// source rather than freezing it.
class MealItem {
  const MealItem({required this.userFoodId, this.servingQty = 1});
  final String userFoodId;

  /// Multiples of the saved food's own portion. 2 rotis is qty 2 against a
  /// user_food whose serving is one roti.
  final double servingQty;

  Map<String, Object?> toJson() =>
      {'user_food_id': userFoodId, 'serving_qty': servingQty};

  /// Parse stored JSON defensively — it round-trips through sync and through
  /// whatever a future version writes.
  static List<MealItem> decode(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is! List) return const [];
      final out = <MealItem>[];
      for (final item in d) {
        if (item is! Map) continue;
        final id = item['user_food_id'];
        if (id is! String || id.isEmpty) continue;
        final qty = _qty(item['serving_qty']);
        // A zero or absurd quantity is not a portion. Dropped rather than
        // defaulted to 1, which would invent an amount nobody chose.
        if (qty == null) continue;
        out.add(MealItem(userFoodId: id, servingQty: qty));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<MealItem> items) =>
      jsonEncode(items.map((i) => i.toJson()).toList());

  /// The single quantity rule, used on BOTH the write and the read path.
  ///
  /// It lived only in [decode] once, so [MealRepository.create] happily wrote a
  /// `serving_qty: 0` item that synced and then vanished on read — a stored
  /// meal that resolves to nothing, which is worse than a refusal because
  /// nobody is told. A validity rule enforced on one side of a round trip is
  /// not a rule, it is a filter.
  static bool isValidQty(double q) => q.isFinite && q > 0 && q <= 100;

  /// True when this item can survive a round trip. An item that cannot must
  /// never be written.
  bool get isValid => userFoodId.trim().isNotEmpty && isValidQty(servingQty);

  static double? _qty(Object? v) {
    final d = switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    // Non-finite must die at coercion: every comparison against NaN is false,
    // so it would pass both bounds and become a portion multiplier.
    if (d == null || !isValidQty(d)) return null;
    return d;
  }
}
