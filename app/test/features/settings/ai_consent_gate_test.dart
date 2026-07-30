import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/ai/ai_consent_store.dart';
import 'package:sakama/features/settings/presentation/ai_disclosure.dart';
import 'package:sakama/features/settings/presentation/ai_privacy_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host: a button that runs [ensureAiConsent] and records the result.
class _Harness extends ConsumerWidget {
  const _Harness(this.onResult);
  final void Function(bool) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('go'),
          onPressed: () async => onResult(await ensureAiConsent(context, ref)),
          child: const Text('go'),
        ),
      ),
    );
  }
}

Widget _app(Widget home) => ProviderScope(child: MaterialApp(home: home));

void main() {
  group('ensureAiConsent gate (#60)', () {
    testWidgets('never-asked shows the disclosure; accepting grants + proceeds',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      bool? result;
      await tester.pumpWidget(_app(_Harness((r) => result = r)));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      // Disclosure sheet is up, naming the health-condition transmission.
      expect(find.bySemanticsIdentifier('ai-disclosure-sheet'), findsOneWidget);
      expect(find.textContaining('health conditions', findRichText: true),
          findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('ai-disclosure-accept'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      // Consent persisted, so a second run does NOT re-prompt.
      expect(await AiConsentStore().read(), isTrue);
    });

    testWidgets('declining does NOT proceed and does NOT persist a choice',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      bool? result;
      await tester.pumpWidget(_app(_Harness((r) => result = r)));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('ai-disclosure-decline'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      // Still null: "Not now" is not "off" — the gate may ask again.
      expect(await AiConsentStore().read(), isNull);
    });

    testWidgets('already granted proceeds with no sheet', (tester) async {
      SharedPreferences.setMockInitialValues({'ai_data_enabled': true});
      bool? result;
      await tester.pumpWidget(_app(_Harness((r) => result = r)));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('ai-disclosure-sheet'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('explicitly off does not proceed, no sheet', (tester) async {
      SharedPreferences.setMockInitialValues({'ai_data_enabled': false});
      bool? result;
      await tester.pumpWidget(_app(_Harness((r) => result = r)));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('ai-disclosure-sheet'), findsNothing);
      expect(result, isFalse);
    });
  });

  testWidgets('AiPrivacyPage toggle records explicit consent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const AiPrivacyPage()));
    await tester.pumpAndSettle();

    // Off by default (never-asked reads as off in the toggle).
    Switch sw() => tester.widget<Switch>(find.descendant(
        of: find.bySemanticsIdentifier('ai-enabled-toggle'),
        matching: find.byType(Switch)));
    expect(sw().value, isFalse);

    await tester.tap(find.bySemanticsIdentifier('ai-enabled-toggle'));
    await tester.pumpAndSettle();

    expect(sw().value, isTrue);
    expect(await AiConsentStore().read(), isTrue);
  });
}
