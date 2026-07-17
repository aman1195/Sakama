import 'package:flutter/material.dart';

class DiaryPage extends StatelessWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'diary-page',
      child: Center(child: Text('Diary')),
    );
  }
}
