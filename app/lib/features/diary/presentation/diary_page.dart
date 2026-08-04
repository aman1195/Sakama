import 'package:flutter/material.dart';

class DiaryPage extends StatelessWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'diary-page',
      // Same shell-tab inset rule as coach/me — applied now so real content
      // does not land under the status bar later.
      child: SafeArea(bottom: false, child: Center(child: Text('Diary'))),
    );
  }
}
