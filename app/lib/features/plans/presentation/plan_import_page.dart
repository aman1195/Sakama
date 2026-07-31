import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../application/plan_importer.dart';

/// Paste a plan (JSON) and apply it. Plans are DATA (ADR 0007): the user, or a
/// coach, or AI (4.4) hands over a JSON plan and it becomes the active plan that
/// drives the dashboard targets and (4.5) the enforcement surfaces.
///
/// Validation runs before anything is saved: malformed JSON / non-object and a
/// too-new schema version are rejected with a clear message (review #68 notes
/// 1 & 2), so a bad paste can never crash or be silently misread.
class PlanImportPage extends ConsumerStatefulWidget {
  const PlanImportPage({super.key});
  @override
  ConsumerState<PlanImportPage> createState() => _PlanImportPageState();
}

class _PlanImportPageState extends ConsumerState<PlanImportPage> {
  final _input = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final result = const PlanImporter().validate(_input.text);
    switch (result) {
      case PlanImportError(:final message):
        setState(() => _error = message);
      case PlanImportOk(:final plan, :final config):
        setState(() {
          _busy = true;
          _error = '';
        });
        final repo = await ref.read(planRepositoryProvider.future);
        await repo.savePlan(name: plan.name, config: config);
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Applied "${plan.name.isEmpty ? 'plan' : plan.name}".')));
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'plan-import-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Import a plan')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Paste a plan below. It becomes your active plan and sets your '
                'daily targets. You can switch back anytime.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Semantics(
                  identifier: 'plan-import-input',
                  child: TextField(
                    controller: _input,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Paste plan JSON here…',
                    ),
                  ),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Semantics(
                identifier: 'plan-import-apply',
                button: true,
                child: FilledButton(
                  onPressed: _busy ? null : _import,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Apply plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
