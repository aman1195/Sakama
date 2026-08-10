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
  ///
  /// Checks BOTH endpoints. It previously checked only Supabase, so a build
  /// with a real Supabase project and a placeholder PowerSync URL counted as
  /// "configured": `connect()` fired and the client then retried a POST to a
  /// non-existent host every 5 seconds, forever, on battery, silently. Sync is
  /// a two-endpoint feature, so both have to be present for it to be on.
  static bool get isConfigured => configuredWith(supabaseUrl, powersyncUrl);

  /// The rule, extracted so it can be tested. `isConfigured` reads compile-time
  /// obfuscated fields, so the placeholder cases are unreachable from a test
  /// without editing .env — which is exactly how the one-endpoint check
  /// survived unnoticed.
  static bool configuredWith(String supabase, String powersync) =>
      supabase.isNotEmpty &&
      powersync.isNotEmpty &&
      !supabase.contains('YOUR-PROJECT') &&
      !powersync.contains('YOUR-INSTANCE');
}
