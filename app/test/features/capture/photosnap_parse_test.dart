import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/capture/data/photosnap_service.dart';

String _items(List<Map<String, Object?>> items) => jsonEncode({'items': items});

Map<String, Object?> _thali() => {
      'name': 'Dal Tadka',
      'portion_label': '1 katori',
      'grams': 150,
      'energy_kcal': 180,
      'protein_g': 9.0,
      'carb_g': 22.0,
      'fat_g': 6.0,
      'confidence': 0.8,
    };

void main() {
  group('PhotoSnap parseItems — untrusted model output', () {
    test('valid items parse; confidence clamped below the verified floor', () {
      final items = EdgeFunctionPhotoSnap.parseItems(_items([_thali()]));
      expect(items, hasLength(1));
      expect(items.first.name, 'Dal Tadka');
      expect(items.first.portionLabel, '1 katori');
      expect(items.first.energyKcal, 180);
      expect(items.first.confidence, 0.6); // 0.8 clamped
      expect(items.first.confidence, lessThanOrEqualTo(0.6));
    });

    test('a hallucinated item is DROPPED, the good ones survive', () {
      final items = EdgeFunctionPhotoSnap.parseItems(_items([
        _thali(),
        {..._thali(), 'name': 'Rice', 'energy_kcal': 9000}, // absurd -> drop
        {..._thali(), 'name': 'Roti', 'protein_g': null},   // missing -> drop
        {..._thali(), 'name': 'Sabzi', 'energy_kcal': 500,  // incoherent kcal
          'protein_g': 2, 'carb_g': 2, 'fat_g': 1},         // -> Atwater drop
      ]));
      expect(items.map((i) => i.name), ['Dal Tadka']);
    });

    test('missing name is dropped', () {
      expect(EdgeFunctionPhotoSnap.parseItems(_items([{..._thali(), 'name': ''}])),
          isEmpty);
    });

    test('caps at 8 items', () {
      final many = List.generate(20, (i) => {..._thali(), 'name': 'Item $i'});
      expect(EdgeFunctionPhotoSnap.parseItems(_items(many)).length, 8);
    });

    test('garbage / no items key / non-JSON -> empty', () {
      expect(EdgeFunctionPhotoSnap.parseItems('nonsense'), isEmpty);
      expect(EdgeFunctionPhotoSnap.parseItems('{}'), isEmpty);
      expect(EdgeFunctionPhotoSnap.parseItems('{"items":"x"}'), isEmpty);
    });

    test('absurd grams drops the item', () {
      expect(
          EdgeFunctionPhotoSnap.parseItems(
              _items([{..._thali(), 'grams': 99999}])),
          isEmpty);
    });
  });
}
