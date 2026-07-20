import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    );
  }
}
