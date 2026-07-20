import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/app_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  String get _today {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addTestLog(SakamaDatabase db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // userId deliberately null when signed out AND when signed in it is set:
    // the M0 exit test verifies both paths (the null-omission upload bet from
    // the PR #10 review, and the normal session path).
    final uid = Supabase.instance.client.auth.currentSession?.user.id;
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: uuid.v4(),
          date: _today,
          meal: 'lunch',
          name: 'dal tadka',
          energyKcal: 180,
          proteinG: const Value(9),
          carbG: const Value(22),
          fatG: const Value(6),
          userId: Value(uid),
          createdAt: now,
          updatedAt: now,
        ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);
    return Semantics(
      identifier: 'home-page',
      child: dbAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('db error: $e')),
        data: (db) => Scaffold(
          // Debug-only harness for the M0 exit test: create a local row, watch
          // the day's rows live. Becomes the real dashboard in M1.
          floatingActionButton: kDebugMode
              ? Semantics(
                  identifier: 'dev-add-log',
                  child: FloatingActionButton(
                    onPressed: () => _addTestLog(db),
                    child: const Icon(Icons.add),
                  ),
                )
              : null,
          body: StreamBuilder<List<FoodLog>>(
            stream: db.watchDay(_today),
            builder: (context, snap) {
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const Center(child: Text('Home — no logs today'));
              }
              final kcal = rows.fold<double>(0, (a, r) => a + r.energyKcal);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Text('${kcal.round()} kcal today',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  const SizedBox(height: 8),
                  for (final r in rows)
                    ListTile(
                      dense: true,
                      title: Text(r.name),
                      subtitle: Text(
                          '${r.meal} · ${r.energyKcal.round()} kcal · '
                          'uid=${r.userId ?? "null"}'),
                      trailing: Text(r.id.substring(0, 8)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
