import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/update_required_screen.dart';
import '../core/providers/app_providers.dart';
import 'router.dart';
import 'theme.dart';

class SakamaApp extends ConsumerWidget {
  const SakamaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        return mustUpdate ? const UpdateRequiredScreen() : (child ?? const SizedBox.shrink());
      },
    );
  }
}
