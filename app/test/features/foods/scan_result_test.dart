import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/foods/data/off_client.dart';
import 'package:sakama/features/foods/data/off_repository.dart';
import 'package:sakama/features/foods/presentation/scan_result_view.dart';

String _productJson() => jsonEncode({
      'status': 1,
      'product': {
        'product_name': 'Parle-G Biscuits',
        'brands': 'Parle',
        'serving_size': '30 g',
        'nutriments': {
          'energy-kcal_100g': 450,
          'proteins_100g': 7.0,
          'carbohydrates_100g': 75.0,
          'fat_100g': 14.0,
        },
      },
    });

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget harness(MockClient client) => ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          offRepositoryProvider
              .overrideWith((ref) async => OffRepository(db, OffClient(httpClient: client))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ScanResultView(barcode: '8901719101083'),
          ),
        ),
      );

  Future<void> settle(WidgetTester t, Finder until) async {
    for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('found → confirm shows ODbL notice; logging tags via=barcode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        harness(MockClient((_) async => http.Response(_productJson(), 200))));
    await settle(tester, find.bySemanticsIdentifier('scan-log'));

    expect(find.text('Parle-G Biscuits (Parle)'), findsOneWidget);
    // ODbL attribution appears on the result itself (#44), not just settings.
    expect(find.textContaining('Open Food Facts'), findsOneWidget);
    expect(find.textContaining('ODbL'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('scan-log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final rows = await db.select(db.foodLogs).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Parle-G Biscuits (Parle)');
    expect(rows.single.loggedVia, 'barcode');
    expect(rows.single.grams, 30); // default serving from "30 g"
    expect(rows.single.energyKcal, closeTo(135, 0.5)); // 450/100g × 30g

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('unknown barcode → not-found message, nothing logged',
      (tester) async {
    await tester.pumpWidget(
        harness(MockClient((_) async => http.Response('', 404))));
    await settle(tester, find.bySemanticsIdentifier('scan-not-found'));
    expect(find.bySemanticsIdentifier('scan-not-found'), findsOneWidget);
    // #51 handoff: a dead end twice reported in dogfood — the not-found state
    // must offer a way into Quick-Add.
    expect(find.bySemanticsIdentifier('scan-not-found-action'), findsOneWidget);
    expect(find.text('Add it manually'), findsOneWidget);
    expect(await db.select(db.foodLogs).get(), isEmpty);
  });

  testWidgets('429 → rate-limited message (distinct from offline)',
      (tester) async {
    await tester.pumpWidget(harness(
        MockClient((_) async => http.Response('', 429))));
    await settle(tester, find.bySemanticsIdentifier('scan-rate-limited'));
    expect(find.bySemanticsIdentifier('scan-rate-limited'), findsOneWidget);
  });

  testWidgets('network failure → offline message', (tester) async {
    await tester.pumpWidget(
        harness(MockClient((_) async => throw Exception('no net'))));
    await settle(tester, find.bySemanticsIdentifier('scan-offline'));
    expect(find.bySemanticsIdentifier('scan-offline'), findsOneWidget);
  });
}
