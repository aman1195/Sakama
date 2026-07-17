import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/env/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-first (CLAUDE.md rule 1): Supabase init is auth/sync plumbing only.
  // With placeholder .env values the app runs fully local — nothing awaits the
  // network on the startup path.
  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }
  runApp(const ProviderScope(child: SakamaApp()));
}
