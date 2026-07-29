import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/auth/auth_service.dart';
import 'package:sakama/core/sync/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Recording fakes: only the members AuthService touches.
class _FakeGoTrue extends Fake implements GoTrueClient {
  Session? sessionValue;
  final calls = <String>[];
  bool failAnonymous = false;

  @override
  Session? get currentSession => sessionValue;

  @override
  Future<AuthResponse> signInAnonymously(
      {Map<String, dynamic>? data, String? captchaToken}) async {
    calls.add('signInAnonymously');
    if (failAnonymous) throw const AuthException('disabled');
    sessionValue = _session(anonymous: true);
    return AuthResponse(session: sessionValue);
  }

  @override
  Future<UserResponse> updateUser(UserAttributes attributes,
      {String? emailRedirectTo}) async {
    calls.add('updateUser');
    return UserResponse.fromJson({'user': null}) ;
  }

  @override
  Future<AuthResponse> signInWithPassword(
      {String? email, String? phone, required String password,
      String? captchaToken}) async {
    calls.add('signInWithPassword');
    sessionValue = _session(anonymous: false, email: email);
    return AuthResponse(session: sessionValue);
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    calls.add('signOut');
    sessionValue = null;
  }
}

Session _session({required bool anonymous, String? email}) => Session(
      accessToken: 't',
      tokenType: 'bearer',
      user: User(
        id: 'uid-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        isAnonymous: anonymous,
        email: email,
      ),
    );

class _FakeClient extends Fake implements SupabaseClient {
  _FakeClient(this.goTrue);
  final _FakeGoTrue goTrue;
  @override
  GoTrueClient get auth => goTrue;
}

class _FakeSync extends Fake implements SyncService {
  final calls = <String>[];
  @override
  Future<void> connect() async => calls.add('connect');
  @override
  Future<void> disconnectAndClear() async => calls.add('disconnectAndClear');
}

void main() {
  late _FakeGoTrue goTrue;
  late _FakeSync sync;
  late AuthService auth;

  setUp(() {
    goTrue = _FakeGoTrue();
    sync = _FakeSync();
    // configuredOverride: CI runs with placeholder .env (Env.isConfigured
    // false), local runs with real creds — the tests must not depend on that.
    auth = AuthService(sync,
        client: _FakeClient(goTrue), configuredOverride: true);
  });

  test('ensureSession: creates an anonymous session and attaches sync',
      () async {
    expect(await auth.ensureSession(), isTrue);
    expect(goTrue.calls, ['signInAnonymously']);
    expect(sync.calls, ['connect']);
    expect(auth.isAnonymous, isTrue);
    expect(auth.email, isNull);
  });

  test('ensureSession: no-op when a session already exists', () async {
    goTrue.sessionValue = _session(anonymous: false, email: 'a@b.c');
    expect(await auth.ensureSession(), isTrue);
    expect(goTrue.calls, isEmpty);
    expect(sync.calls, isEmpty);
  });

  test('ensureSession: NEVER throws — offline/disabled yields false', () async {
    goTrue.failAnonymous = true;
    expect(await auth.ensureSession(), isFalse);
    expect(sync.calls, isEmpty, reason: 'no session -> no replication attach');
  });

  test('signInExisting is a USER SWITCH: clear BEFORE sign-in, connect after',
      () async {
    goTrue.sessionValue = _session(anonymous: true);
    await auth.signInExisting(emailAddress: 'a@b.c', password: 'pw');
    expect(sync.calls.first, 'disconnectAndClear',
        reason: 'old identity data must be gone before the new session');
    expect(goTrue.calls, ['signInWithPassword']);
    expect(sync.calls.last, 'connect');
    expect(auth.email, 'a@b.c');
    expect(auth.isAnonymous, isFalse);
  });

  test('signOut clears local data and drops back to a FRESH anonymous session',
      () async {
    goTrue.sessionValue = _session(anonymous: false, email: 'a@b.c');
    await auth.signOut();
    expect(sync.calls.first, 'disconnectAndClear');
    expect(goTrue.calls, ['signOut', 'signInAnonymously'],
        reason: 'anonymous-first: the app keeps working after sign-out');
    expect(auth.isAnonymous, isTrue);
  });

  test('saveAccount converts the anonymous user (updateUser), keeping uid',
      () async {
    goTrue.sessionValue = _session(anonymous: true);
    await auth.saveAccount(emailAddress: 'a@b.c', password: 'pw123456');
    expect(goTrue.calls, ['updateUser']);
    expect(sync.calls, isEmpty,
        reason: 'same uid -> no data clear, sync keeps flowing');
  });
}
