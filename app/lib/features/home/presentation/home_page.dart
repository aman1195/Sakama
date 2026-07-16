import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'home-page',
      child: Center(child: Text('Home')),
    );
  }
}
