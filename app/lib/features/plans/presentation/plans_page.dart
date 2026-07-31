import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';
import '../application/plan_providers.dart';

/// The plans surface (M4, ADR 0007): what plan is active today, the library of
/// saved plans, and the entry to import a new one. Switching or deleting here
/// flows straight to the dashboard targets (4.1b) via the shared providers.
class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});
  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  Future<void> _activate(String id) async {
    final repo = await ref.read(planRepositoryProvider.future);
    await repo.setActive(id);
  }

  Future<void> _confirmDelete(UserPlanRow plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${plan.name}"?'),
        content: const Text('This removes the saved plan from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(planRepositoryProvider.future);
    await repo.deletePlan(plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(savedPlansProvider);
    final activeDay = ref.watch(activePlanDayProvider);

    return Semantics(
      identifier: 'plans-page',
      child: Scaffold(
        appBar: AppBar(title: const Text('Plans')),
        floatingActionButton: Semantics(
          identifier: 'plans-import',
          button: true,
          child: FloatingActionButton.extended(
            onPressed: () => context.push('/plans/import'),
            icon: const Icon(Icons.add),
            label: const Text('Import a plan'),
          ),
        ),
        body: plansAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load plans: $e')),
          data: (plans) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // Active-plan summary — or the maintenance-default fallback.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        activeDay == null
                            ? 'No active plan — using your maintenance targets.'
                            : activeDay.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Saved plans',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (plans.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No saved plans yet. Import one to set your daily targets.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...plans.map((p) => _PlanTile(
                      plan: p,
                      onActivate: p.active ? null : () => _activate(p.id),
                      onDelete: () => _confirmDelete(p),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.onActivate,
    required this.onDelete,
  });
  final UserPlanRow plan;
  final VoidCallback? onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'plan-row-${plan.id}',
      child: Card(
        child: ListTile(
          title: Text(plan.name.isEmpty ? 'Untitled plan' : plan.name),
          subtitle: Text(_sourceLabel(plan.source)),
          leading: Icon(
            plan.active ? Icons.check_circle : Icons.circle_outlined,
            color: plan.active ? Theme.of(context).colorScheme.primary : null,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (plan.active)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Active'),
                )
              else
                Semantics(
                  identifier: 'plan-activate-${plan.id}',
                  button: true,
                  child: TextButton(
                    onPressed: onActivate,
                    child: const Text('Use'),
                  ),
                ),
              Semantics(
                identifier: 'plan-delete-${plan.id}',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(String source) => switch (source) {
        'ai_generated' => 'Generated for you',
        'template' => 'Template',
        _ => 'Imported',
      };
}
