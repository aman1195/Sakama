import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase/PowerSync init lands here once .env has real project values
  // (Env.isConfigured) — offline-first means the app must run fully without it.
  runApp(const ProviderScope(child: SakamaApp()));
}
