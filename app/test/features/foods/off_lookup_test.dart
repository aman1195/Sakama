import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/foods/data/off_client.dart';
import 'package:sakama/features/foods/data/off_repository.dart';

String _productJson({
  String name = 'Parle-G Biscuits',
  String brands = 'Parle',
  Object? kcal = 450,
  String? servingSize = '30 g',
}) =>
    jsonEncode({
      'code': '8901719101083',
      'status': 1,
      'product': {
        'product_name': name,
        'brands': brands,
        'serving_size': servingSize,
        'nutriments': {
          'energy-kcal_100g': kcal,
          'proteins_100g': 7.0,
          'carbohydrates_100g': 75.0,
          'fat_100g': 14.0,
          'fiber_100g': 1.5,
        },
      },
    });

void main() {
  group('OffClient parsing', () {
    test('maps per-100g nutriments and parses grams from serving_size', () {
      final p = OffClient.parseProduct('123', (jsonDecode(_productJson())
          as Map<String, dynamic>)['product'] as Map<String, dynamic>)!;
      expect(p.name, 'Parle-G Biscuits');
      expect(p.displayName, 'Parle-G Biscuits (Parle)');
      expect(p.energyKcal, 450);
      expect(p.carbG, 75.0);
      expect(p.fiberG, 1.5);
      expect(p.servingGrams, 30);
    });

    test('non-gram serving sizes yield null grams, not a wrong number', () {
      final p = OffClient.parseProduct(
          '123',
          (jsonDecode(_productJson(servingSize: '1 cup'))
              as Map<String, dynamic>)['product'] as Map<String, dynamic>)!;
      expect(p.servingLabel, '1 cup');
      expect(p.servingGrams, isNull);
    });

    test('rejects records with no name or no energy — unusable in a diary', () {
      final noName = OffClient.parseProduct(
          '123',
          (jsonDecode(_productJson(name: '')) as Map<String, dynamic>)['product']
              as Map<String, dynamic>);
      expect(noName, isNull);
      final noKcal = OffClient.parseProduct(
          '123',
          (jsonDecode(_productJson(kcal: null))
              as Map<String, dynamic>)['product'] as Map<String, dynamic>);
      expect(noKcal, isNull);
    });

    test('sends the identifying User-Agent OFF requires', () async {
      String? ua;
      final client = OffClient(
          httpClient: MockClient((req) async {
        ua = req.headers['User-Agent'];
        return http.Response(_productJson(), 200);
      }));
      await client.fetch('8901719101083');
      expect(ua, isNotNull);
      expect(ua, contains('Sakama/'),
          reason: 'anonymous clients are blocked by OFF');
    });

    test('404 and status:0 both mean "not found", not an error', () async {
      final c404 = OffClient(
          httpClient: MockClient((_) async => http.Response('', 404)));
      expect(await c404.fetch('000'), isNull);
      final cStatus0 = OffClient(
          httpClient: MockClient(
              (_) async => http.Response(jsonEncode({'status': 0}), 200)));
      expect(await cStatus0.fetch('000'), isNull);
    });

    test('server/network failure throws (distinct from not-found)', () async {
      final c = OffClient(
          httpClient: MockClient((_) async => http.Response('boom', 500)));
      expect(() => c.fetch('000'), throwsA(isA<OffLookupException>()));
    });
  });

  group('OffRepository — ODbL containment + cache-first', () {
    late SakamaDatabase db;
    setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a fetched product is cached into off_foods ONLY, ODbL-tagged',
        () async {
      final repo = OffRepository(
          db,
          OffClient(
              httpClient: MockClient((_) async => http.Response(_productJson(), 200))));
      final food = await repo.lookup('8901719101083');
      expect(food, isNotNull);
      expect(food!.licence, 'ODbL');
      expect(food.source, 'openfoodfacts');

      final offRows = await db.select(db.offFoods).get();
      expect(offRows, hasLength(1));
      expect(offRows.single.licence, 'ODbL');
      expect(offRows.single.sourceRef, 'OFF:8901719101083');

      // THE containment invariant (CLAUDE.md rule 5): the proprietary table
      // must remain untouched by any OFF write.
      expect(await db.select(db.foods).get(), isEmpty,
          reason: 'OFF data must never enter the proprietary foods table');
    });

    test('a second lookup is served from cache with NO network call', () async {
      var calls = 0;
      final repo = OffRepository(
          db,
          OffClient(httpClient: MockClient((_) async {
            calls++;
            return http.Response(_productJson(), 200);
          })));
      await repo.lookup('8901719101083');
      expect(calls, 1);

      final again = await repo.lookup('8901719101083');
      expect(again, isNotNull);
      expect(calls, 1, reason: 'cached barcode must resolve offline');
      expect(await db.select(db.offFoods).get(), hasLength(1));
    });

    test('unknown barcode returns null without writing a row', () async {
      final repo = OffRepository(
          db, OffClient(httpClient: MockClient((_) async => http.Response('', 404))));
      expect(await repo.lookup('000'), isNull);
      expect(await db.select(db.offFoods).get(), isEmpty);
    });

    test('offline on a NEW barcode surfaces as an exception, not a silent miss',
        () async {
      final repo = OffRepository(
          db,
          OffClient(
              httpClient: MockClient((_) async => throw Exception('no net'))));
      expect(() => repo.lookup('999'), throwsA(isA<OffLookupException>()));
    });
  });
}
