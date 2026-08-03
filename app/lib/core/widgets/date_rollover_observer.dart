import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/current_date_provider.dart';

/// Drives [currentDateProvider] to roll over at local midnight and whenever the
/// app returns to the foreground (a backgrounded timer may not fire on time, so
/// resume is the belt-and-braces path). Owns the only timer, so provider and
/// widget unit tests stay timer-free unless they mount this deliberately.
///
/// Renders its [child] unchanged — it is a pure side-effect wrapper.
class DateRolloverObserver extends ConsumerStatefulWidget {
  const DateRolloverObserver({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<DateRolloverObserver> createState() =>
      _DateRolloverObserverState();
}

class _DateRolloverObserverState extends ConsumerState<DateRolloverObserver>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    _timer = Timer(nextMidnightAfter(now).difference(now), () {
      ref.read(currentDateProvider.notifier).refresh();
      _schedule(); // arm the next day
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(currentDateProvider.notifier).refresh();
      _schedule(); // a suspended timer may have drifted; re-arm cleanly
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
