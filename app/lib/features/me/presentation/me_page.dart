import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/kit/kit.dart';
import '../../../core/providers/app_providers.dart';
import '../../weight/presentation/weight_section.dart';
import 'account_section.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      identifier: 'me-page',
      // No AppBar on shell tabs — see coach_page for why bottom:false.
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sk.lg, 0, Sk.lg, Sk.xxl),
          children: [
            const SkTitle('You'),
            const WeightSection(),
            const SkSection('Settings'),
            // ONE grouped card instead of five floating ones (SAK-126).
            // The reference apps group settings rows into a single surface
            // with hairline dividers; five separate cards each holding one
            // row reads as five unrelated things, and wastes 64dp of vertical
            // space that a phone does not have to spare.
            Card(
              child: Column(
                children: [
                  _navRow(context,
                      id: 'nav-plans',
                      icon: Icons.event_note_outlined,
                      title: 'Plans',
                      subtitle: 'Your plan and daily targets',
                      route: '/plans'),
                  _divider(context),
                  _navRow(context,
                      id: 'nav-byok',
                      icon: Icons.vpn_key_outlined,
                      title: 'Your own AI key',
                      subtitle: 'Go unlimited with your OpenRouter key',
                      route: '/byok'),
                  _divider(context),
                  _navRow(context,
                      id: 'nav-ai-privacy',
                      icon: Icons.shield_outlined,
                      title: 'AI & privacy',
                      subtitle: 'What AI sends, and an on/off switch',
                      route: '/ai-privacy'),
                  _divider(context),
                  _navRow(context,
                      id: 'nav-memory',
                      icon: Icons.psychology_outlined,
                      title: 'What Vita remembers',
                      subtitle: 'Stays on your phone — view or delete',
                      route: '/memory'),
                  _divider(context),
                  const _StatusColourSwitch(),
                  _divider(context),
                  _navRow(context,
                      id: 'nav-data-sources',
                      icon: Icons.dataset_outlined,
                      title: 'Data sources & licences',
                      subtitle: 'Where our nutrition data comes from',
                      route: '/data-sources'),
                ],
              ),
            ),
            // Real auth (M3.1, anonymous-first) — replaces the dev card.
            const AccountSection(),
          ],
        ),
      ),
    );
  }
}

/// A settings row: filled icon chip, title, subtitle, chevron.
///
/// The chip is the reference apps' merchant-avatar shape — it gives each row a
/// fixed optical anchor so the list scans as a column rather than as prose.
Widget _navRow(
  BuildContext context, {
  required String id,
  required IconData icon,
  required String title,
  required String subtitle,
  required String route,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Semantics(
    identifier: id,
    button: true,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
      ),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right,
          color: scheme.onSurface.withValues(alpha: 0.35)),
      onTap: () => context.push(route),
    ),
  );
}

/// Hairline, inset past the icon chip so the rows read as one group.
Widget _divider(BuildContext context) => Divider(
      height: 1,
      thickness: 1,
      indent: 72,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
    );

/// The opt-out for colour-as-judgement (PRODUCT.md principle 5).
///
/// Lives in the same grouped card as the navigation rows rather than behind a
/// "Display" sub-screen: a setting that exists for people who find the default
/// uncomfortable should not require finding it first.
class _StatusColourSwitch extends ConsumerWidget {
  const _StatusColourSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final on = ref.watch(statusColourEnabledProvider);
    return Semantics(
      identifier: 'toggle-status-colour',
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.palette_outlined,
              size: 20, color: scheme.onPrimaryContainer),
        ),
        title: Text('Colour my day',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        // Says what it does, not whether it is good for you.
        subtitle: Text(
            on
                ? "Today's card is coloured by how you're tracking"
                : "Today's card stays plain — the numbers are unchanged",
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        value: on,
        onChanged: (v) async {
          await ref.read(statusColourPrefProvider).set(v);
          ref.invalidate(statusColourEnabledProvider);
        },
      ),
    );
  }
}
