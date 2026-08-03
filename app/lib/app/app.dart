import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/update_required_screen.dart';
import '../core/providers/app_providers.dart';
import '../core/widgets/date_rollover_observer.dart';
import 'router.dart';
import 'theme.dart';

class SakamaApp extends ConsumerStatefulWidget {
  const SakamaApp({super.key});

  @override
  ConsumerState<SakamaApp> createState() => _SakamaAppState();
}

class _SakamaAppState extends ConsumerState<SakamaApp> {
  @override
  void initState() {
    super.initState();
    // Anonymous-first (M3.1): grab a silent session so AI + budgets work with
    // zero signup friction. Fire-and-forget — offline first launch stays
    // fully usable locally.
    Future.microtask(() => ref.read(authServiceProvider).ensureSession());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sakama',
      theme: sakamaTheme(Brightness.light),
      darkTheme: sakamaTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      // The min-version gate (MOBILE.md): when the server floor exceeds this
      // build, overlay a non-dismissible update screen over every route. Runs
      // in the router's builder so it covers whatever the gate would show.
      // Fail-open while the check loads/errors so an offline user isn't blocked.
      builder: (context, child) {
        final mustUpdate = ref.watch(mustUpdateProvider).value ?? false;
        if (mustUpdate) return const UpdateRequiredScreen();
        // Roll the app into the new day at midnight / on resume (review #70) so
        // the dashboard, targets and active-plan day type never sit stale.
        return DateRolloverObserver(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
