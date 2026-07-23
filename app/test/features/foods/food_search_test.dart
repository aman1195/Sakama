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
        // All fixtures stay AT/ABOVE verifiedConfidenceFloor so this test
        // isolates tier+confidence ordering; sub-floor demotion has its own
        // group below.
        _F('Dal Fry', 0.6), // prefix (2), lower confidence than Makhani
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

  // Issue #27 — the explicit ranking decision, now that mixed-provenance data
  // ships (USDA 0.9 alongside the labelled sample 0.5).
  group('sub-floor demotion (unverified data must earn its rank)', () {
    test('an exact-match AI estimate does NOT outrank a prefix-match verified',
        () {
      final out = rankFoods('poha', [
        _F('Poha', 0.3), // exact (3) but unverified -> demoted to 2
        _F('Poha, prepared', 0.9), // prefix (2), verified
      ]).map((f) => f.name).toList();
      expect(out.first, 'Poha, prepared',
          reason: 'verified data wins the tie the demotion creates');
    });

    test('but a sub-floor row still beats a much weaker textual match', () {
      final out = rankFoods('poha', [
        _F('Poha', 0.3), // exact (3) -> demoted to 2
        _F('Flattened rice (poha) mix', 0.9), // substring (0)
      ]).map((f) => f.name).toList();
      expect(out.first, 'Poha',
          reason: 'demotion is one tier, not a blanket penalty');
    });

    test('rows AT the floor are not demoted (the shipped sample data)', () {
      final out = rankFoods('dal', [
        _F('Dal', verifiedConfidenceFloor), // exact, at floor -> stays 3
        _F('Dal Tadka', 0.9), // prefix (2)
      ]).map((f) => f.name).toList();
      expect(out.first, 'Dal',
          reason: 'the floor is exclusive — 0.5 sample data is not demoted');
    });

    test('verified rows are unaffected: tier first, confidence within tier',
        () {
      final out = rankFoods('rice', [
        _F('Rice, brown', 0.9),
        _F('Rice', 0.6), // exact beats prefix even at lower confidence
        _F('Rice, white', 0.95),
      ]).map((f) => f.name).toList();
      expect(out, ['Rice', 'Rice, white', 'Rice, brown']);
    });
  });
}
