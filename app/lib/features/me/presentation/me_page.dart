import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
          padding: const EdgeInsets.all(16),
          children: [
            const WeightSection(),
            // Plans (M4, ADR 0007): the plan library — active plan, switch, import.
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Semantics(
                identifier: 'nav-plans',
                button: true,
                child: ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: const Text('Plans'),
                  subtitle: const Text('Your plan and daily targets'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/plans'),
                ),
              ),
            ),
            // BYOK: the launch "unlock" for unlimited AI.
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Semantics(
                identifier: 'nav-byok',
                button: true,
                child: ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: const Text('Your own AI key'),
                  subtitle: const Text('Go unlimited with your OpenRouter key'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/byok'),
                ),
              ),
            ),
            // AI & privacy: the data-disclosure surface + the master AI toggle
            // (#60). Legally required before shipping AI that sends logged data
            // (incl. health conditions) off-device.
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Semantics(
                identifier: 'nav-ai-privacy',
                button: true,
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('AI & privacy'),
                  subtitle: const Text('What AI sends, and an on/off switch'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ai-privacy'),
                ),
              ),
            ),
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
            // Real auth (M3.1, anonymous-first) — replaces the dev card.
            const AccountSection(),
          ],
        ),
      ),
    );
  }
}
