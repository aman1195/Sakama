import '../../../core/db/database.dart';

/// How to write a logged portion back to the user.
///
/// Grams are the truth in the database, and the wrong thing to show. Nobody
/// weighs a katori, so "1.5 katori" is the number they can check against the
/// bowl in front of them while "225 g" is one they have to take on trust.
///
/// Falls back to grams when no portion was stated, and to nothing at all when
/// neither exists — never to an invented "1 serving".
String? portionLabel(FoodLog e) {
  final label = e.servingLabel;
  final qty = e.servingQty;
  if (label != null && label.isNotEmpty && qty != null && qty > 0) {
    // "1 katori", "1.5 katori" — the unit is not pluralised. Indian serving
    // words do not take an English -s, and "2 rotis" versus "2 roti" is a
    // regional preference we should not pick a side on inside a diary row.
    return '${_n(qty)} $label';
  }
  final g = e.grams;
  if (g != null && g > 0) return '${_n(g)} g';
  return null;
}

String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
