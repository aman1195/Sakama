import 'package:flutter/material.dart';

class CoachPage extends StatelessWidget {
  const CoachPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'coach-page',
      child: Center(child: Text('Coach')),
    );
  }
}
