import 'package:envied/envied.dart';

part 'env.g.dart';

/// Compile-time environment config (obfuscated by envied — OWASP M1).
///
/// The anon key is the PUBLIC Supabase key (safe in a client, guarded by RLS).
/// Provider AI keys must NEVER appear here — all LLM calls go through the
/// Edge Function -> managed gateway (ADR 0011).
@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'SUPABASE_URL')
  static final String supabaseUrl = _Env.supabaseUrl;

  @EnviedField(varName: 'SUPABASE_ANON_KEY')
  static final String supabaseAnonKey = _Env.supabaseAnonKey;

  @EnviedField(varName: 'POWERSYNC_URL')
  static final String powersyncUrl = _Env.powersyncUrl;

  /// True until real project values are filled in — sync stays disabled.
  static bool get isConfigured => !supabaseUrl.contains('YOUR-PROJECT');
}
