import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env/env.dart';
import '../../../core/providers/app_providers.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: 'me-page',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: Text('Me')),
          // Debug-only: the real auth UI is M1. This exists so the M0 exit test
          // and the two-account isolation test can obtain a session at all.
          if (kDebugMode && Env.isConfigured) const _DevSignInCard(),
        ],
      ),
    );
  }
}

class _DevSignInCard extends ConsumerStatefulWidget {
  const _DevSignInCard();

  @override
  ConsumerState<_DevSignInCard> createState() => _DevSignInCardState();
}

class _DevSignInCardState extends ConsumerState<_DevSignInCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _status = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    try {
      final res = await Supabase.instance.client.auth
          .signInWithPassword(email: _email.text.trim(), password: _password.text);
      // A fresh session must (re)attach replication.
      await ref.read(syncServiceProvider).connect();
      setState(() => _status = 'signed in: ${res.user?.id ?? '?'}');
    } on AuthException catch (e) {
      setState(() => _status = 'auth error: ${e.message}');
    }
  }

  Future<void> _signOut() async {
    // Dev harness uses user-SWITCH semantics: clear local synced data so the
    // next signer-in cannot see the previous user's rows.
    await ref.read(syncServiceProvider).disconnectAndClear();
    await Supabase.instance.client.auth.signOut();
    setState(() => _status = 'signed out');
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return Card(
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('DEV sign-in (debug builds only)',
                style: Theme.of(context).textTheme.labelLarge),
            Semantics(
              identifier: 'dev-email',
              child: TextField(
                controller: _email,
                decoration: const InputDecoration(hintText: 'email'),
              ),
            ),
            Semantics(
              identifier: 'dev-password',
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'password'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Semantics(
                  identifier: 'dev-sign-in',
                  child: FilledButton(onPressed: _signIn, child: const Text('Sign in')),
                ),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'dev-sign-out',
                  child: OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              session == null ? 'no session\n$_status' : 'uid: ${session.user.id}\n$_status',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
