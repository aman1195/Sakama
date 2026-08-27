import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Today's water total vs target, with quick +250/+500 and an undo.
/// Reads WaterRepository (offline-first Drift stream).
class WaterChip extends ConsumerWidget {
  const WaterChip({super.key, required this.targetMl});
  final int targetMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(waterRepositoryProvider);
    return repoAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (repo) {
        return StreamBuilder<int>(
          stream: repo.watchDayTotalMl(_today()),
          builder: (context, snap) {
            final ml = snap.data ?? 0;
            final progress =
                targetMl <= 0 ? 0.0 : (ml / targetMl).clamp(0.0, 1.0);
            return Semantics(
              identifier: 'water-chip',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.water_drop_outlined),
                            const SizedBox(width: 8),
                            Text('Water',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ]),
                          Text('$ml / $targetMl ml'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: progress, minHeight: 8),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Semantics(
                            identifier: 'water-add-250',
                            child: OutlinedButton(
                              onPressed: () => repo.add(
                                  date: _today(),
                                  amountMl: 250,
                                  userId: ref.read(currentUserIdProvider)),
                              child: const Text('+250'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            identifier: 'water-add-500',
                            child: OutlinedButton(
                              onPressed: () => repo.add(
                                  date: _today(),
                                  amountMl: 500,
                                  userId: ref.read(currentUserIdProvider)),
                              child: const Text('+500'),
                            ),
                          ),
                          const Spacer(),
                          Semantics(
                            identifier: 'water-undo',
                            child: IconButton(
                              icon: const Icon(Icons.undo),
                              onPressed: ml == 0
                                  ? null
                                  : () => repo.removeLast(_today()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
