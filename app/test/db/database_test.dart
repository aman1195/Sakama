import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

void main() {
  late SakamaDatabase db;

  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('insert and watch a food log offline', () async {
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'log-1',
          date: '2026-07-16',
          meal: 'lunch',
          name: 'dal tadka',
          energyKcal: 180,
          proteinG: const Value(9),
          createdAt: 1,
          updatedAt: 1,
        ));

    final day = await db.watchDay('2026-07-16').first;
    expect(day, hasLength(1));
    expect(day.single.name, 'dal tadka');
    expect(day.single.energyKcal, 180);
  });
}
