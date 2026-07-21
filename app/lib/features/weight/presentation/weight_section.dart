import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Weight tracking for the Me tab: latest weight, an "add" action, and a trend
/// chart (our first fl_chart). Reads WeightRepository (offline-first).
class WeightSection extends ConsumerWidget {
  const WeightSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(weightRepositoryProvider);
    return repoAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Weight: $e'),
      data: (repo) => StreamBuilder<List<WeightLog>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          final entries = snap.data ?? const [];
          final latest = entries.isEmpty ? null : entries.last;
          return Semantics(
            identifier: 'weight-section',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Weight',
                            style: Theme.of(context).textTheme.titleMedium),
                        Semantics(
                          identifier: 'weight-add',
                          child: FilledButton.tonal(
                            onPressed: () => _addDialog(context, ref),
                            child: const Text('Log weight'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (latest != null)
                      Text('${latest.weightKg} kg',
                          style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    if (entries.length < 2)
                      const Text('Log a couple of days to see your trend.')
                    else
                      SizedBox(height: 180, child: _WeightChart(entries)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log weight'),
        content: Form(
          key: formKey,
          child: Semantics(
            identifier: 'weight-input',
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null) return 'Enter a number';
                if (n < 20 || n > 400) return 'Out of range';
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          Semantics(
            identifier: 'weight-save',
            child: FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      final repo = await ref.read(weightRepositoryProvider.future);
      await repo.add(
        date: _today(),
        weightKg: double.parse(controller.text.trim()),
        userId: ref.read(currentUserIdProvider),
      );
    }
    controller.dispose();
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart(this.entries);
  final List<WeightLog> entries;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].weightKg),
    ];
    final ys = entries.map((e) => e.weightKg);
    final minY = (ys.reduce((a, b) => a < b ? a : b) - 1);
    final maxY = (ys.reduce((a, b) => a > b ? a : b) + 1);
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
