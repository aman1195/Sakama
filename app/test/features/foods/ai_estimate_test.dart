import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/foods/data/ai_estimator.dart';
import 'package:sakama/features/foods/data/food_repository.dart';
import 'package:sakama/features/foods/domain/food_estimate.dart';
import 'package:sakama/features/foods/domain/food_search.dart';

String _json(Map<String, Object?> overrides) => jsonEncode({
      'name': 'Misal Pav',
      'energy_kcal_100g': 180,
      'protein_g_100g': 7.0,
      'carb_g_100g': 20.0,
      'fat_g_100g': 8.0,
      'fiber_g_100g': 4.0,
      'serving_label': '1 plate',
      'serving_grams': 250,
      'confidence': 0.7,
      'assumptions': 'moderate oil',
      ...overrides,
    });

void main() {
  group('parseEstimate — model output is UNTRUSTED input', () {
    FoodEstimate? parse(Map<String, Object?> o) =>
        EdgeFunctionAiEstimator.parseEstimate(_json(o), fallbackName: 'x');

    test('valid estimate parses, confidence clamped below the verified floor',
        () {
      final e = parse({})!;
      expect(e.name, 'Misal Pav');
      expect(e.energyKcal, 180);
      expect(e.confidence, 0.4,
          reason: 'model said 0.7; clamped to 0.4 < verifiedConfidenceFloor');
      expect(e.confidence, lessThan(verifiedConfidenceFloor));
      expect(e.assumptions, 'moderate oil');
    });

    test('missing macros are rejected, not defaulted', () {
      expect(parse({'protein_g_100g': null}), isNull);
      expect(parse({'energy_kcal_100g': null}), isNull);
    });

    test('absurd values are rejected (kcal bounds, macro bounds)', () {
      expect(parse({'energy_kcal_100g': 2000}), isNull);
      expect(parse({'energy_kcal_100g': 1}), isNull);
      expect(parse({'fat_g_100g': 150}), isNull);
      expect(parse({'protein_g_100g': -3}), isNull);
    });

    test('incoherent macros vs kcal fail the Atwater cross-check', () {
      // 4*2 + 4*2 + 9*1 = 25 kcal claimed as 500 -> nonsense, reject.
      expect(
          parse({
            'energy_kcal_100g': 500,
            'protein_g_100g': 2,
            'carb_g_100g': 2,
            'fat_g_100g': 1,
          }),
          isNull);
    });

    test('garbage / non-JSON / error responses yield null', () {
      expect(EdgeFunctionAiEstimator.parseEstimate('nonsense', fallbackName: 'x'),
          isNull);
      expect(
          EdgeFunctionAiEstimator.parseEstimate('{"error":"not_food"}',
              fallbackName: 'x'),
          isNull);
    });

    test('missing name falls back to the query', () {
      final e = parse({'name': ''})!;
      expect(e.name, 'x');
    });
  });

  group('saveEstimate — provenance', () {
    late SakamaDatabase db;
    late FoodRepository repo;
    setUp(() {
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      repo = FoodRepository(db);
    });
    tearDown(() => db.close());

    test('stores as ai_estimate/generated with sub-floor confidence, findable',
        () async {
      const est = FoodEstimate(
          name: 'Misal Pav', energyKcal: 180, proteinG: 7, carbG: 20, fatG: 8,
          servingLabel: '1 plate', servingGrams: 250, confidence: 0.35);
      final food = await repo.saveEstimate(est);
      expect(food.source, 'ai_estimate');
      expect(food.licence, 'generated');
      expect(food.confidence, lessThan(verifiedConfidenceFloor));

      final rows = await db.select(db.foods).get();
      expect(rows.single.source, 'ai_estimate');

      // Findable in later searches — demoted, but present.
      final results = await repo.search('misal');
      expect(results.map((f) => f.name), contains('Misal Pav'));
    });

    test('re-estimating the same dish upserts, not duplicates', () async {
      const a = FoodEstimate(
          name: 'Misal Pav', energyKcal: 180, proteinG: 7, carbG: 20, fatG: 8,
          confidence: 0.3);
      const b = FoodEstimate(
          name: 'Misal Pav', energyKcal: 200, proteinG: 8, carbG: 22, fatG: 9,
          confidence: 0.35);
      await repo.saveEstimate(a);
      await repo.saveEstimate(b);
      final rows = await db.select(db.foods).get();
      expect(rows, hasLength(1));
      expect(rows.single.energyKcal, 200);
    });
  });
}
