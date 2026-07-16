import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/app/app.dart';

void main() {
  testWidgets('shell renders all five tabs and navigates', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SakamaApp()));
    await tester.pumpAndSettle();

    for (final label in ['Home', 'Diary', 'Log', 'Coach', 'Me']) {
      expect(find.text(label), findsWidgets, reason: 'tab $label missing');
    }

    await tester.tap(find.text('Diary'));
    await tester.pumpAndSettle();
    expect(find.text('Diary'), findsWidgets);
  });
}
