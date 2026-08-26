import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/env/env.dart';
import 'core/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-first (CLAUDE.md rule 1): Supabase init is auth/sync plumbing only.
  // With placeholder .env values the app runs fully local — nothing awaits the
  // network on the startup path.
  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }
  // Read the display preference BEFORE first paint. Resolving it
  // asynchronously meant a user who had opted OUT of status colouring saw
  // their day graded in colour for a frame on cold start, then watched it snap
  // to neutral — a flash of exactly the thing they turned off (review of
  // #127). SharedPreferences is a local read of a few bytes; it costs nothing
  // on the startup path and it is not a network call, so offline-first is
  // untouched.
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const SakamaApp(),
  ));
}
