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
      final food = await repo.saveEstimate(est, query: 'misal pav');
      expect(food.source, 'ai_estimate');
      expect(food.licence, 'generated');
      expect(food.confidence, lessThan(verifiedConfidenceFloor));

      final rows = await db.select(db.foods).get();
      expect(rows.single.source, 'ai_estimate');

      // Findable in later searches — demoted, but present.
      final results = await repo.search('misal');
      expect(results.map((f) => f.name), contains('Misal Pav'));
    });

    test('re-estimating the same QUERY upserts even if the model renames (#46.3)', () async {
      const a = FoodEstimate(
          name: 'Misal Pav', energyKcal: 180, proteinG: 7, carbG: 20, fatG: 8,
          confidence: 0.3);
      const b = FoodEstimate(
          name: 'Misal Pav (restaurant style)', // model renamed it — id must not care
          energyKcal: 200, proteinG: 8, carbG: 22, fatG: 9,
          confidence: 0.35);
      await repo.saveEstimate(a, query: 'misal pav');
      await repo.saveEstimate(b, query: 'Misal Pav '); // same query, different case/space
      final rows = await db.select(db.foods).get();
      expect(rows, hasLength(1));
      expect(rows.single.energyKcal, 200);
    });

    test('native-script queries never collide (#46.2 — Devanagari slugs)',
        () async {
      const dal = FoodEstimate(
          name: 'Dal', energyKcal: 120, proteinG: 6, carbG: 15, fatG: 4,
          confidence: 0.3);
      const paneer = FoodEstimate(
          name: 'Paneer', energyKcal: 265, proteinG: 18, carbG: 1.2, fatG: 21,
          confidence: 0.3);
      final a = await repo.saveEstimate(dal, query: 'दाल');
      final b = await repo.saveEstimate(paneer, query: 'पनीर');
      expect(a.id, isNot(b.id),
          reason: 'a bare a-z slug degenerates to ai-- for Devanagari; the '
              'stable query hash must keep them distinct');
      expect(await db.select(db.foods).get(), hasLength(2));
    });
  });

  group('review #46 minors', () {
    test('not_food is detected as its own signal', () {
      expect(EdgeFunctionAiEstimator.isNotFood('{"error":"not_food"}'), isTrue);
      expect(EdgeFunctionAiEstimator.isNotFood('{"name":"Dal"}'), isFalse);
      expect(EdgeFunctionAiEstimator.isNotFood('garbage'), isFalse);
    });

    test('absurd serving_grams is dropped, macros kept (#46.4)', () {
      final e = EdgeFunctionAiEstimator.parseEstimate(
          jsonEncode({
            'name': 'Dal', 'energy_kcal_100g': 120, 'protein_g_100g': 6.0,
            'carb_g_100g': 15.0, 'fat_g_100g': 4.0,
            'serving_grams': 99999, 'serving_label': '1 katori',
            'confidence': 0.3,
          }),
          fallbackName: 'dal')!;
      expect(e.servingGrams, isNull);
      expect(e.energyKcal, 120);
    });
  });
}
