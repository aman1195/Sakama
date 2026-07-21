import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/foods/domain/food_serving.dart';

void main() {
  group('Macros.scaleTo (per-100g -> portion)', () {
    const per100 =
        Macros(energyKcal: 130, proteinG: 6, carbG: 15, fatG: 4, fiberG: 3);

    test('scales all macros linearly by grams/100', () {
      final s = per100.scaleTo(150);
      expect(s.energyKcal, closeTo(195, 1e-9));
      expect(s.proteinG, closeTo(9, 1e-9));
      expect(s.carbG, closeTo(22.5, 1e-9));
      expect(s.fatG, closeTo(6, 1e-9));
      expect(s.fiberG, closeTo(4.5, 1e-9));
    });

    test('100 g is identity', () {
      final s = per100.scaleTo(100);
      expect(s.energyKcal, 130);
      expect(s.proteinG, 6);
    });

    test('0 g is all-zero', () {
      final s = per100.scaleTo(0);
      expect(s.energyKcal, 0);
      expect(s.fatG, 0);
    });

    test('null fiber stays null', () {
      const noFiber = Macros(energyKcal: 100, proteinG: 1, carbG: 2, fatG: 3);
      expect(noFiber.scaleTo(200).fiberG, isNull);
    });
  });
}
