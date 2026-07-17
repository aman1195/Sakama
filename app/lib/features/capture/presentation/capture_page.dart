import 'package:flutter/material.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'capture-page',
      child: Center(child: Text('Capture')),
    );
  }
}
