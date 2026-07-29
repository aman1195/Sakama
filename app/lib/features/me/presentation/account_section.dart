import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/providers/app_providers.dart';

/// Account card (M3.1, anonymous-first). Three states:
///  - GUEST (anonymous session): data works + syncs under the silent account;
///    offer "Save your account" (email+password, keeps uid+data) and
///    "Sign in" for an existing account (a user switch).
///  - ACCOUNT: email + sign out.
///  - OFFLINE/unconfigured: honest note; tracking is unaffected.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

enum _Mode { view, save, signIn }

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.view;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthService) op,
      {String? success}) async {
    setState(() { _busy = true; _error = ''; });
    try {
      await op(ref.read(authServiceProvider));
      if (!mounted) return;
      setState(() => _mode = _Mode.view);
      if (success != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('already registered') || s.contains('already been registered')) {
      return 'That email already has an account — use Sign in instead.';
    }
    if (s.contains('Invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (s.contains('SocketException') || s.contains('network')) {
      return 'No connection. Try again when you are online.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (!auth.configured) return const SizedBox.shrink();

    final Widget body;
    if (auth.session == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: text.titleMedium),
          const SizedBox(height: 8),
          Text("You're offline — tracking works as always. We'll set up "
              'sync when you reconnect.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'account-retry',
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run((a) async {
                        await a.ensureSession();
                      }),
              child: const Text('Try now'),
            ),
          ),
        ],
      );
    } else if (auth.isAnonymous) {
      body = switch (_mode) {
        _Mode.view => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account', style: text.titleMedium),
              const SizedBox(height: 6),
              Text('Guest — your data lives on this device and syncs '
                  'privately. Save an account to keep it if you switch '
                  'phones.',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(children: [
                Semantics(
                  identifier: 'account-save',
                  child: FilledButton(
                      onPressed: () => setState(() => _mode = _Mode.save),
                      child: const Text('Save your account')),
                ),
                const SizedBox(width: 10),
                Semantics(
                  identifier: 'account-signin',
                  child: TextButton(
                      onPressed: () => setState(() => _mode = _Mode.signIn),
                      child: const Text('Sign in')),
                ),
              ]),
            ],
          ),
        _Mode.save => _form(
            title: 'Save your account',
            hint: 'Keeps everything you have logged, on every device.',
            cta: 'Save account',
            onSubmit: () => _run(
                (a) => a.saveAccount(
                    emailAddress: _email.text.trim(),
                    password: _password.text),
                success: 'Check your email to confirm your account.'),
          ),
        _Mode.signIn => _form(
            title: 'Sign in',
            hint: 'Signing in switches this device to that account.',
            cta: 'Sign in',
            onSubmit: () => _run(
                (a) => a.signInExisting(
                    emailAddress: _email.text.trim(),
                    password: _password.text),
                success: 'Signed in.'),
          ),
      };
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: text.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.check_circle_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(auth.email ?? 'Signed in', style: text.bodyMedium)),
          ]),
          Text('Synced across your devices.', style: text.bodySmall),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'account-signout',
            child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run((a) => a.signOut(),
                        success: 'Signed out — back to guest mode.'),
                child: const Text('Sign out')),
          ),
        ],
      );
    }

    return Semantics(
      identifier: 'account-section',
      child: Card(
        margin: const EdgeInsets.only(top: 24),
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }

  Widget _form({
    required String title,
    required String hint,
    required String cta,
    required VoidCallback onSubmit,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.titleMedium),
        Text(hint,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Semantics(
          identifier: 'account-email',
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(labelText: 'Email'),
          ),
        ),
        Semantics(
          identifier: 'account-password',
          child: TextField(
            controller: _password,
            obscureText: true,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
                labelText: 'Password (8+ characters)'),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Semantics(
            identifier: 'account-submit',
            child: FilledButton(
              onPressed: _busy ? null : onSubmit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(cta),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
              onPressed:
                  _busy ? null : () => setState(() => _mode = _Mode.view),
              child: const Text('Cancel')),
        ]),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              identifier: 'account-error',
              child: Text(_error,
                  style: text.bodySmall?.copyWith(color: scheme.error)),
            ),
          ),
      ],
    );
  }
}
