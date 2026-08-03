import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/plans/application/plan_providers.dart';
import 'package:sakama/features/plans/domain/plan.dart';
import 'package:sakama/features/plans/domain/plan_day.dart';
import 'package:sakama/features/plans/presentation/plan_log_notice_card.dart';

PlanDay _day({List<String> blocked = const []}) => PlanDay(
      dayTypeKey: 'reset',
      label: 'Reset',
      targets: const PlanTargets(),
      blockedFoods: blocked,
    );

Future<void> _pump(WidgetTester tester, PlanDay? day) => tester.pumpWidget(
      ProviderScope(
        overrides: [activePlanDayProvider.overrideWithValue(day)],
        child: const MaterialApp(
            home: Scaffold(body: PlanLogNoticeCard())),
      ),
    );

void main() {
  testWidgets('renders the avoid-foods reminder when the plan blocks foods',
      (tester) async {
    await _pump(tester, _day(blocked: ['sugar', 'fried']));
    await tester.pump();

    expect(find.bySemanticsIdentifier('plan-log-notice'), findsOneWidget);
    expect(find.textContaining('avoid today: sugar, fried'), findsOneWidget);
  });

  testWidgets('renders nothing when there is no active plan', (tester) async {
    await _pump(tester, null);
    await tester.pump();

    expect(find.bySemanticsIdentifier('plan-log-notice'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('renders nothing when the plan has nothing to flag', (tester) async {
    await _pump(tester, _day()); // no window, no blocked foods
    await tester.pump();

    expect(find.bySemanticsIdentifier('plan-log-notice'), findsNothing);
  });
}
