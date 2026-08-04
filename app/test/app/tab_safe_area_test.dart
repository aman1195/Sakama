import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/coach/presentation/coach_page.dart';
import 'package:sakama/features/diary/presentation/diary_page.dart';
import 'package:sakama/features/me/presentation/me_page.dart';

import '../helpers/fake_byok.dart';

/// Shell tabs have no AppBar of their own, so nothing insets them from the
/// status bar — content rendered at y=0 sits under the clock and battery on a
/// real device. Reported from the device build; these pin the fix.
///
/// Home and Log are not covered here: both have their own Scaffold + AppBar,
/// which already provides the inset (that is why they looked correct).
const _notch = 47.0; // representative iPhone status-bar inset

Widget _withNotch(Widget child, SakamaDatabase db) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        byokStoreProvider.overrideWithValue(FakeByokStore()),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: _notch),
          viewPadding: EdgeInsets.only(top: _notch),
        ),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget page, SakamaDatabase db) async {
  await tester.pumpWidget(_withNotch(page, db));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('Coach: the thread controls clear the status bar', (tester) async {
    await _pump(tester, const CoachPage(), db);

    final y = tester.getTopLeft(find.bySemanticsIdentifier('coach-history')).dy;
    expect(y, greaterThanOrEqualTo(_notch),
        reason: 'the history/new-chat icons were rendering under the clock');
    await _dispose(tester);
  });

  testWidgets('Me: the first card clears the status bar', (tester) async {
    await _pump(tester, const MePage(), db);

    final y = tester.getTopLeft(find.byType(ListView)).dy;
    expect(y, greaterThanOrEqualTo(_notch),
        reason: 'the Weight card was rendering under the clock');
    await _dispose(tester);
  });

  testWidgets('Diary: content clears the status bar', (tester) async {
    await _pump(tester, const DiaryPage(), db);

    final y = tester.getTopLeft(find.bySemanticsIdentifier('diary-page')).dy;
    expect(y, greaterThanOrEqualTo(0));
    // The SafeArea is present, so future real content cannot regress silently.
    expect(
        find.descendant(
            of: find.bySemanticsIdentifier('diary-page'),
            matching: find.byType(SafeArea)),
        findsOneWidget);
    await _dispose(tester);
  });
}
