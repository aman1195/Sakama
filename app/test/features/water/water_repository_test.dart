import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/water/data/water_repository.dart';

void main() {
  late SakamaDatabase db;
  late WaterRepository repo;
  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = WaterRepository(db);
  });
  tearDown(() => db.close());

  test('day total sums the day and ignores others', () async {
    await repo.add(date: '2026-07-20', amountMl: 250);
    await repo.add(date: '2026-07-20', amountMl: 500);
    await repo.add(date: '2026-07-19', amountMl: 999);
    expect(await repo.watchDayTotalMl('2026-07-20').first, 750);
  });

  test('empty day totals to 0', () async {
    expect(await repo.watchDayTotalMl('2026-07-20').first, 0);
  });

  test('removeLast undoes the most recent entry only', () async {
    await repo.add(date: '2026-07-20', amountMl: 250);
    await repo.add(date: '2026-07-20', amountMl: 500);
    await repo.removeLast('2026-07-20');
    expect(await repo.watchDayTotalMl('2026-07-20').first, 250);
  });
}
