import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/current_date_provider.dart';
import 'package:sakama/core/widgets/date_rollover_observer.dart';
import 'package:sakama/features/plans/application/plan_providers.dart';

/// A currentDate we can drive from the test (the real one moves at midnight /
/// on resume via DateRolloverObserver).
class _FixedDate extends CurrentDateNotifier {
  _FixedDate(this._d);
  DateTime _d;
  @override
  DateTime build() => _d;
  void set(DateTime d) {
    _d = d;
    state = d;
  }
}

// Explicit (date-keyed) schedule: two days, two day types — so the resolved day
// type is a pure function of the date the provider is handed.
const _config = '{"schema_version":1,"id":"a","name":"P",'
    '"day_types":{"fast":{"label":"F"},"normal":{"label":"N"}},'
    '"schedule":{"type":"explicit","dates":'
    '{"2026-08-03":"fast","2026-08-04":"normal"}}}';

UserPlanRow _row() => UserPlanRow(
      id: 'a', userId: null, name: 'P', config: _config,
      source: 'user_imported', active: true, startDate: null,
      createdAt: 1, updatedAt: 1);

void main() {
  test('active plan day type rolls over when currentDate changes (review #70)',
      () async {
    final container = ProviderContainer(overrides: [
      activePlanRowProvider.overrideWith((ref) => Stream.value(_row())),
      currentDateProvider.overrideWith(() => _FixedDate(DateTime(2026, 8, 3))),
    ]);
    addTearDown(container.dispose);
    container.listen(activePlanDayProvider, (_, _) {});

    await container.read(activePlanRowProvider.future); // let the row emit
    expect(container.read(activePlanDayProvider)?.dayTypeKey, 'fast',
        reason: 'on 2026-08-03 the explicit schedule selects the fast day');

    // Midnight passes: the ticker moves to the next day.
    (container.read(currentDateProvider.notifier) as _FixedDate)
        .set(DateTime(2026, 8, 4));
    expect(container.read(activePlanDayProvider)?.dayTypeKey, 'normal',
        reason: 'the day type re-resolves for the new date without a restart');
  });

  test('CurrentDateNotifier.refresh is a no-op when the day is unchanged', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(currentDateProvider);
    container.read(currentDateProvider.notifier).refresh();
    expect(container.read(currentDateProvider), before);
  });

  testWidgets('DateRolloverObserver renders its child and disposes cleanly',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DateRolloverObserver(child: Text('child')),
      ),
    ));
    expect(find.text('child'), findsOneWidget);
    // Disposing cancels the midnight timer — no pending-timer failure follows.
    await tester.pumpWidget(const SizedBox());
  });
}
