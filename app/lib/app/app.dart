import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class SakamaApp extends StatelessWidget {
  const SakamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sakama',
      theme: sakamaTheme(Brightness.light),
      darkTheme: sakamaTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}
