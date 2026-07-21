import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/onboarding/domain/enums.dart';
import 'package:sakama/features/onboarding/domain/profile_record.dart';

ProfileRecord _onboarded() => ProfileRecord(
      dob: DateTime(1994, 1, 1), weightKg: 70, heightCm: 175, sex: Sex.male,
      activity: ActivityLevel.moderate, goal: Goal.maintain,
      diet: DietPreference.veg, cuisine: CuisinePreference.both,
      onboardingComplete: true);

Widget _app(SakamaDatabase db, {required bool mustUpdate}) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        profileProvider.overrideWith((ref) => Stream.value(_onboarded())),
        mustUpdateProvider.overrideWith((ref) async => mustUpdate),
      ],
      child: const SakamaApp(),
    );

void main() {
  testWidgets('below floor => update screen overlays the app', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, mustUpdate: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsIdentifier('update-required'), findsOneWidget);
    // The gate must fully replace the app: no bottom nav underneath.
    expect(find.byKey(const Key('nav-home')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('at/above floor => app renders, no update screen', (tester) async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, mustUpdate: false));
    for (var i = 0;
        i < 40 && tester.widgetList(find.byKey(const Key('nav-home'))).isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.bySemanticsIdentifier('update-required'), findsNothing);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
