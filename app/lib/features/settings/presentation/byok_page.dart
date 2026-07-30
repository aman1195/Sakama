import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/byok_store.dart';
import '../../../core/providers/app_providers.dart';

/// Bring Your Own Key — the launch "unlock". A user pastes their own OpenRouter
/// key and their AI (PhotoSnap, estimate, Vita) becomes unlimited, at their
/// cost. The key never leaves the device except to be forwarded upstream; we
/// never store or log it (ADR 0011).
class ByokPage extends ConsumerStatefulWidget {
  const ByokPage({super.key});
  @override
  ConsumerState<ByokPage> createState() => _ByokPageState();
}

class _ByokPageState extends ConsumerState<ByokPage> {
  final _key = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (!ByokStore.looksValid(key)) {
      setState(() => _error = 'That doesn\'t look like an OpenRouter key '
          '(starts with "sk-").');
      return;
    }
    setState(() { _busy = true; _error = ''; });
    await ref.read(byokStoreProvider).save(key);
    ref.invalidate(hasByokProvider);
    if (!mounted) return;
    _key.clear();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your key is saved — AI is now unlimited.')));
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    await ref.read(byokStoreProvider).clear();
    ref.invalidate(hasByokProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Key removed — back to the free daily limits.')));
  }

  @override
  Widget build(BuildContext context) {
    final has = ref.watch(hasByokProvider).value ?? false;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'byok-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Your own AI key')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Sakama\'s AI (photo, estimates, coach) is free with a daily '
              'limit. Add your own OpenRouter key and it becomes unlimited — '
              'you pay OpenRouter directly, and your key stays only on this '
              'phone.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (has)
              Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: scheme.primary),
                  title: const Text('Your key is active'),
                  subtitle: const Text('AI is unlimited on this device.'),
                  trailing: Semantics(
                    identifier: 'byok-remove',
                    child: TextButton(
                        onPressed: _busy ? null : _remove,
                        child: const Text('Remove')),
                  ),
                ),
              )
            else ...[
              Semantics(
                identifier: 'byok-input',
                child: TextField(
                  controller: _key,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'OpenRouter API key',
                    hintText: 'sk-or-...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'byok-save',
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save key'),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    identifier: 'byok-error',
                    child: Text(_error,
                        style: text.bodySmall?.copyWith(color: scheme.error)),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Get a key at openrouter.ai → Keys. We never see or store '
                  'it on our servers.',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
