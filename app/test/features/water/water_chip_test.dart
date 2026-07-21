import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/water/data/water_repository.dart';
import 'package:sakama/features/water/presentation/water_chip.dart';

void main() {
  testWidgets('tap +250 adds water; undo removes it; total reflects it',
      (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WaterRepository(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [waterRepositoryProvider.overrideWith((ref) async => repo)],
      child: const MaterialApp(
          home: Scaffold(body: WaterChip(targetMl: 2450))),
    ));
    for (var i = 0;
        i < 20 && tester.widgetList(find.byType(OutlinedButton)).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('0 / 2450 ml'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('water-add-250'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.bySemanticsIdentifier('water-add-500'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('750 / 2450 ml'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('water-undo'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('250 / 2450 ml'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
