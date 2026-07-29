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
          // Real auth (M3.1, anonymous-first) — replaces the dev card.
          const AccountSection(),
        ],
      ),
    );
  }
}
