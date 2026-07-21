import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/weight/data/weight_repository.dart';
import 'package:sakama/features/weight/presentation/weight_section.dart';

void main() {
  testWidgets('empty state prompts to log; >=2 entries render the chart',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WeightRepository(db);

    Future<void> pump() => tester.pumpWidget(ProviderScope(
          overrides: [weightRepositoryProvider.overrideWith((ref) async => repo)],
          child: const MaterialApp(home: Scaffold(body: WeightSection())),
        ));

    await pump();
    for (var i = 0;
        i < 20 && tester.widgetList(find.byType(WeightSection)).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));
    // Fewer than 2 entries: prompt, no chart.
    expect(find.textContaining('trend'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);

    // Two entries -> chart appears, latest shown.
    await repo.add(date: '2026-07-19', weightKg: 70);
    await repo.add(date: '2026-07-20', weightKg: 69);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('69.0 kg'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
