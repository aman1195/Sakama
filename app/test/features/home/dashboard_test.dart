import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/home/presentation/home_page.dart';
import 'package:sakama/features/home/presentation/widgets/calorie_budget_ring.dart';
import 'package:sakama/features/home/presentation/widgets/macro_bars.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

void main() {
  String today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  testWidgets('dashboard renders the ring, macro bars, and 4 meal slots',
      (tester) async {
    // Tall surface so all four meal cards lay out (ListView builds sliver
    // children lazily — off-screen cards otherwise aren't in the tree).
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    // Seed a lunch entry for today.
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'x', date: today(), meal: 'lunch', name: 'dal tadka',
          energyKcal: 180, proteinG: const Value(9), createdAt: 1, updatedAt: 1));

    final profile = ProfileRecord(
      dob: DateTime(1994), weightKg: 70, heightCm: 175, sex: Sex.male,
      activity: ActivityLevel.moderate, goal: Goal.maintain,
      diet: DietPreference.veg, cuisine: CuisinePreference.both,
      onboardingComplete: true);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        profileProvider.overrideWith((ref) => Stream.value(profile)),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    // Pump until the dashboard resolves (db future -> stream -> build).
    for (var i = 0;
        i < 40 && tester.widgetList(find.byType(CalorieBudgetRing)).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(CalorieBudgetRing), findsOneWidget);
    expect(find.byType(MacroBars), findsOneWidget);
    // All four meal slots render (Breakfast/Lunch/Dinner/Snack labels).
    for (final label in ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
      expect(find.text(label), findsOneWidget);
    }
    // The seeded lunch entry shows in its slot.
    expect(find.text('dal tadka'), findsOneWidget);
    // The ring reflects the seeded 180 kcal against the maintain target.
    expect(find.textContaining('180 of'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
