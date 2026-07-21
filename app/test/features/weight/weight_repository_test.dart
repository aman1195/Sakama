import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/weight/data/weight_repository.dart';

void main() {
  late SakamaDatabase db;
  late WeightRepository repo;
  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = WeightRepository(db);
  });
  tearDown(() => db.close());

  test('watchAll returns entries oldest-first (chart order)', () async {
    await repo.add(date: '2026-07-20', weightKg: 69);
    await repo.add(date: '2026-07-18', weightKg: 70);
    await repo.add(date: '2026-07-19', weightKg: 69.5);
    final all = await repo.watchAll().first;
    expect(all.map((w) => w.date), ['2026-07-18', '2026-07-19', '2026-07-20']);
  });

  test('watchLatest returns the most recent by date', () async {
    await repo.add(date: '2026-07-18', weightKg: 70);
    await repo.add(date: '2026-07-20', weightKg: 68.5);
    expect((await repo.watchLatest().first)!.weightKg, 68.5);
  });

  test('watchLatest tiebreaks same-day entries by createdAt (PR #22 review)',
      () async {
    // Two weigh-ins on the SAME day: the later-created one wins deterministically.
    await repo.add(date: '2026-07-20', weightKg: 70);
    await repo.add(date: '2026-07-20', weightKg: 69);
    expect((await repo.watchLatest().first)!.weightKg, 69);
  });

  test('watchAll orders same-day entries by createdAt (the rendered path)',
      () async {
    // PR #23 nit 1: the UI shows entries.last from watchAll, so same-day order
    // must be deterministic here too — .last is the later-created weigh-in.
    await repo.add(date: '2026-07-20', weightKg: 70);
    await repo.add(date: '2026-07-20', weightKg: 69);
    final all = await repo.watchAll().first;
    expect(all.map((w) => w.weightKg), [70, 69]);
    expect(all.last.weightKg, 69);
  });
}
