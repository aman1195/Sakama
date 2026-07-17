import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';

void main() {
  testWidgets('shell renders five tabs and actually switches branches',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SakamaApp()));
    await tester.pumpAndSettle();

    for (final id in ['nav-home', 'nav-diary', 'nav-capture', 'nav-coach', 'nav-me']) {
      expect(find.byKey(Key(id)), findsOneWidget, reason: '$id missing');
    }

    // Home branch active initially; diary page must NOT be built yet.
    expect(find.bySemanticsIdentifier('home-page'), findsOneWidget);
    expect(find.bySemanticsIdentifier('diary-page'), findsNothing);

    // Tap by stable key (never by localizable label). If goBranch is a no-op,
    // the diary-page assertion below fails — unlike asserting on the tab label,
    // which is always present.
    await tester.tap(find.byKey(const Key('nav-diary')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('diary-page'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-coach')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('coach-page'), findsOneWidget);
  });
}
