import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/providers/current_date_provider.dart';

void main() {
  group('dateOnly', () {
    test('strips the time component', () {
      expect(dateOnly(DateTime(2026, 8, 3, 23, 59, 59)), DateTime(2026, 8, 3));
      expect(dateOnly(DateTime(2026, 8, 3, 0, 0, 0)), DateTime(2026, 8, 3));
    });
  });

  group('nextMidnightAfter', () {
    test('is the following local midnight', () {
      expect(nextMidnightAfter(DateTime(2026, 8, 3, 9, 0)), DateTime(2026, 8, 4));
      expect(nextMidnightAfter(DateTime(2026, 8, 3, 0, 0, 1)),
          DateTime(2026, 8, 4));
    });

    test('rolls month and year boundaries', () {
      expect(nextMidnightAfter(DateTime(2026, 8, 31, 12)), DateTime(2026, 9, 1));
      expect(
          nextMidnightAfter(DateTime(2026, 12, 31, 23, 59)), DateTime(2027, 1, 1));
    });

    test('is strictly in the future (positive wait) even one tick before midnight',
        () {
      final now = DateTime(2026, 8, 3, 23, 59, 59);
      expect(nextMidnightAfter(now).isAfter(now), isTrue);
    });
  });
}
