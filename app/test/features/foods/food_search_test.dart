import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/foods/domain/food_search.dart';

class _F implements RankableFood {
  _F(this.name, this.confidence);
  @override
  final String name;
  @override
  final double confidence;
}

void main() {
  group('foodMatchScore', () {
    test('exact > prefix > word-start > substring > none', () {
      expect(foodMatchScore('dal', 'Dal'), 3);
      expect(foodMatchScore('dal', 'Dal Tadka'), 2);
      expect(foodMatchScore('tad', 'Dal Tadka'), 1);
      expect(foodMatchScore('adk', 'Dal Tadka'), 0); // substring, no word-start

      expect(foodMatchScore('pizza', 'Dal Tadka'), -1);
    });
    test('case- and whitespace-insensitive', () {
      expect(foodMatchScore('  DAL ', 'dal'), 3);
    });
    test('empty query never matches', () {
      expect(foodMatchScore('', 'Dal'), -1);
      expect(foodMatchScore('   ', 'Dal'), -1);
    });
  });

  group('rankFoods', () {
    test('orders by score, then confidence, then name; drops non-matches', () {
      final input = [
        _F('Dal Makhani', 0.9), // prefix (2)
        _F('Dal', 0.5), // exact (3) — wins on score despite lower confidence
        _F('Tadka Dal', 0.9), // word-start (1)
        _F('Pizza', 1.0), // no match — dropped
        _F('Dal Fry', 0.4), // prefix (2), lower confidence than Makhani
      ];
      final out = rankFoods('dal', input).map((f) => f.name).toList();
      expect(out, ['Dal', 'Dal Makhani', 'Dal Fry', 'Tadka Dal']);
    });
    test('equal score + equal confidence => alphabetical', () {
      final out = rankFoods('a', [_F('Apple', 0.5), _F('Almond', 0.5)])
          .map((f) => f.name)
          .toList();
      expect(out, ['Almond', 'Apple']);
    });
    test('empty query yields nothing', () {
      expect(rankFoods('', [_F('Dal', 0.5)]), isEmpty);
    });
  });
}
