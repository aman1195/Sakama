import 'package:flutter/material.dart';

import '../../../app/kit/kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/attribution_repository.dart';
import '../domain/data_source_credit.dart';

/// Settings → Data sources & licences.
///
/// Discharges our attribution obligations (ASSET_CREDITS.md): every bundled
/// dataset is credited here, and the list is GENERATED from the provenance
/// columns so nothing can ship uncredited. Also links to the standard
/// open-source licence page for code dependencies (MIT/BSD/Apache notices).
class DataSourcesPage extends ConsumerWidget {
  const DataSourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usedDataSourcesProvider);
    return Semantics(
      identifier: 'data-sources-page',
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load sources: $e')),
          data: (sources) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
            SkTitle('Data sources & licences'),
              Text(
                'Nutrition data in Sakama comes from the sources below. Each '
                'food row records where it came from, under what licence, and '
                'how confident we are in it.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (sources.isEmpty)
                const Text('No reference data loaded yet.')
              else
                for (final s in sources) _CreditCard(usage: s),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'oss-licences',
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.code),
                  label: const Text('Open-source licences'),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Sakama',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.usage});
  final SourceUsage usage;

  @override
  Widget build(BuildContext context) {
    final c = creditFor(usage.source, usage.licence);
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'credit-${usage.source}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: text.titleMedium),
              const SizedBox(height: 4),
              Text('${usage.rowCount} items · ${c.licenceName}',
                  style: text.bodySmall),
              const SizedBox(height: 8),
              _line(text, c.creator),
              if (c.sourceUrl != null) _line(text, 'Source: ${c.sourceUrl}'),
              if (c.licenceUrl != null) _line(text, 'Licence: ${c.licenceUrl}'),
              const SizedBox(height: 8),
              _line(text, c.obligation),
              if (c.modification != null) ...[
                const SizedBox(height: 6),
                _line(text, c.modification!),
              ],
              const SizedBox(height: 6),
              _line(text, c.disclaimer),
              if (usage.isOdbl) ...[
                const SizedBox(height: 6),
                Text(
                  'Kept in a separate database from our own data, as the ODbL '
                  'requires.',
                  style: text.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(TextTheme t, String s) =>
      Padding(padding: const EdgeInsets.only(top: 2), child: Text(s, style: t.bodySmall));
}
