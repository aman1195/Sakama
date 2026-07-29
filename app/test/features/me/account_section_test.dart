import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/auth/auth_service.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/core/sync/sync_service.dart';
import 'package:sakama/features/me/presentation/account_section.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGoTrue extends Fake implements GoTrueClient {
  _FakeGoTrue(this.sessionValue);
  Session? sessionValue;
  @override
  Session? get currentSession => sessionValue;
}

class _FakeClient extends Fake implements SupabaseClient {
  _FakeClient(this.goTrue);
  final _FakeGoTrue goTrue;
  @override
  GoTrueClient get auth => goTrue;
}

class _FakeSync extends Fake implements SyncService {
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnectAndClear() async {}
}

Session _session({required bool anonymous, String? email}) => Session(
    accessToken: 't', tokenType: 'bearer',
    user: User(id: 'u', appMetadata: const {}, userMetadata: const {},
        aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z',
        isAnonymous: anonymous, email: email));

Widget _harness(Session? session) => ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(AuthService(_FakeSync(),
            client: _FakeClient(_FakeGoTrue(session)),
            configuredOverride: true)),
      ],
      child: const MaterialApp(home: Scaffold(body: AccountSection())),
    );

void main() {
  testWidgets('guest state: save + sign-in offers, no uuid anywhere',
      (tester) async {
    await tester.pumpWidget(_harness(_session(anonymous: true)));
    await tester.pump();
    expect(find.bySemanticsIdentifier('account-save'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-signin'), findsOneWidget);
    expect(find.textContaining('Guest'), findsOneWidget);
    expect(find.textContaining('uid'), findsNothing);
  });

  testWidgets('save flow: form appears with email/password/submit',
      (tester) async {
    await tester.pumpWidget(_harness(_session(anonymous: true)));
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('account-save'));
    await tester.pump();
    expect(find.bySemanticsIdentifier('account-email'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-password'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-submit'), findsOneWidget);
    expect(find.text('Save account'), findsOneWidget);
  });

  testWidgets('signed-in state: email shown + sign out, never a uuid',
      (tester) async {
    await tester
        .pumpWidget(_harness(_session(anonymous: false, email: 'a@b.c')));
    await tester.pump();
    expect(find.text('a@b.c'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-signout'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-save'), findsNothing);
  });

  testWidgets('offline (no session): honest note + retry', (tester) async {
    await tester.pumpWidget(_harness(null));
    await tester.pump();
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.bySemanticsIdentifier('account-retry'), findsOneWidget);
  });
}
