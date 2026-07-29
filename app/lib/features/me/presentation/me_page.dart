import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env/env.dart';
import '../../weight/presentation/weight_section.dart';
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
          const WeightSection(),
          // Attribution surface — a legal obligation for licensed data
          // (ASSET_CREDITS.md), plus the OSS dependency notices.
          Card(
            margin: const EdgeInsets.only(top: 16),
            child: Semantics(
              identifier: 'nav-data-sources',
              button: true,
              child: ListTile(
                leading: const Icon(Icons.dataset_outlined),
                title: const Text('Data sources & licences'),
                subtitle: const Text('Where our nutrition data comes from'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/data-sources'),
              ),
            ),
          ),
          // Stopgap sign-in until the real auth slice (M3): release device
          // builds need a session too — without one, sync stays off and the
          // AI gateway correctly 401s (found in device dogfood round 3; the
          // kDebugMode gate hid sign-in entirely in release). Env-gated so
          // an unconfigured checkout still runs fully offline.
          if (Env.isConfigured) const _DevSignInCard(),
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
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _busy = true; _error = ''; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text);
      // A fresh session must (re)attach replication.
      await ref.read(syncServiceProvider).connect();
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      // Dev harness uses user-SWITCH semantics: clear local synced data so the
      // next signer-in cannot see the previous user's rows.
      await ref.read(syncServiceProvider).disconnectAndClear();
      await Supabase.instance.client.auth.signOut();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: session == null
            // ---- signed OUT: the sign-in form ----
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sign in', style: text.titleMedium),
                  Text('Dev sign-in — real accounts arrive in M3.',
                      style: text.bodySmall),
                  const SizedBox(height: 8),
                  Semantics(
                    identifier: 'dev-email',
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                  ),
                  Semantics(
                    identifier: 'dev-password',
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    identifier: 'dev-sign-in',
                    child: FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error,
                          style: text.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              )
            // ---- signed IN: account summary + sign out ----
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(session.user.email ?? 'Signed in',
                            style: text.bodyMedium)),
                  ]),
                  Text('Synced across your devices.', style: text.bodySmall),
                  const SizedBox(height: 12),
                  Semantics(
                    identifier: 'dev-sign-out',
                    child: OutlinedButton(
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
