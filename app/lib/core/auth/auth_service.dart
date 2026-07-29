import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';
import '../sync/sync_service.dart';

/// Anonymous-first auth (M3.1, product decision 2026-07-29).
///
/// Every install silently gets an ANONYMOUS Supabase session on first launch,
/// so AI features + per-user budgets work with zero signup friction
/// (PRODUCT.md: "friction is the enemy"). The user can later SAVE the account
/// (anonymous -> email+password conversion, keeping uid and all synced data)
/// or SIGN IN to an existing account (a user switch: local data cleared per
/// the M0 isolation semantics).
///
/// Offline-first invariant: nothing here ever blocks the UI. A failed
/// anonymous sign-in (offline first launch) leaves the app fully usable
/// locally; [ensureSession] is retried opportunistically.
class AuthService {
  AuthService(this._sync, {SupabaseClient? client, bool? configuredOverride})
      // Private fields cannot be named constructor params, hence no
      // initializing formals here.
      // ignore: prefer_initializing_formals
      : _client = client,
        // ignore: prefer_initializing_formals
        _configuredOverride = configuredOverride;

  final SyncService _sync;
  final SupabaseClient? _client;
  final bool? _configuredOverride; // tests: Env is compile-time, so inject
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  bool get configured => _configuredOverride ?? Env.isConfigured;

  Session? get session {
    if (!configured) return null;
    try {
      return _supabase.auth.currentSession;
    } catch (_) {
      return null; // Supabase not initialized (tests / very early startup)
    }
  }

  /// True when the current session is the silent anonymous one.
  bool get isAnonymous => session?.user.isAnonymous ?? false;

  /// Signed-in email for the account UI; null when anonymous/absent.
  String? get email => session?.user.email?.isEmpty ?? true
      ? null
      : session!.user.email;

  /// Make sure SOME session exists (anonymous if none). Safe to call often;
  /// no-ops when already signed in, never throws (offline -> false).
  Future<bool> ensureSession() async {
    if (!configured) return false;
    try {
      if (session != null) return true;
      await _supabase.auth.signInAnonymously();
      await _sync.connect(); // replication attaches to the new session
      return true;
    } catch (e) {
      debugPrint('anonymous sign-in unavailable: $e');
      return false; // offline or provider disabled — app stays local-only
    }
  }

  /// SAVE the current anonymous account: attach email+password, KEEPING the
  /// uid and everything synced under it. Supabase sends a confirmation email;
  /// data keeps flowing meanwhile.
  Future<void> saveAccount({
    required String emailAddress,
    required String password,
  }) async {
    await _supabase.auth.updateUser(
        UserAttributes(email: emailAddress, password: password));
  }

  /// Sign IN to an existing account — a USER SWITCH: local synced data of the
  /// old identity is cleared first (M0 isolation semantics), then replication
  /// reattaches as the new user and their data syncs down.
  Future<void> signInExisting({
    required String emailAddress,
    required String password,
  }) async {
    await _sync.disconnectAndClear();
    await _supabase.auth
        .signInWithPassword(email: emailAddress, password: password);
    await _sync.connect();
  }

  /// Sign out of a real account. Local data is cleared (switch semantics) and
  /// the app drops back to a FRESH anonymous session, so it keeps working.
  Future<void> signOut() async {
    await _sync.disconnectAndClear();
    await _supabase.auth.signOut();
    await ensureSession();
  }
}
