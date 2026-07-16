import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

/// Seed of the migration suite required by docs/MOBILE.md: a bad on-device
/// migration destroys user data irrecoverably, so every schema bump gets a
/// test here. v1 has no upgrade path yet — this pins creation-from-scratch.
/// From v2 onward, use drift_dev's schema-dump tooling (make migrations) to
/// verify vN -> vN+1 preserves data.
void main() {
  test('schema v1 creates cleanly from scratch', () async {
    final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    expect(db.schemaVersion, 1);
    // Touching the table forces creation; failure here = broken schema.
    expect(await db.select(db.foodLogs).get(), isEmpty);
    await db.close();
  });
}
