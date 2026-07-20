import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

/// The migration harness required by docs/MOBILE.md and docs/REVIEW.md §6.1:
/// a bad on-device migration destroys user data irrecoverably, so every schema
/// bump must (1) dump a new drift_schemas/drift_schema_vN.json, (2) regenerate
/// test/migration/generated/, and (3) add a vN-1 -> vN data-preservation test
/// here. CI runs this suite on every PR.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v1 -> v2 migration adds profiles AND preserves existing food_logs data',
      () async {
    // The first REAL migration. Start at v1, insert a food_log, migrate to v2,
    // and assert (a) the row survived and (b) the new profiles table exists.
    // This is the harness MOBILE.md mandates: a bad migration destroys user
    // data irrecoverably, so every bump proves preservation here.
    // All newConnection() calls share one underlying sqlite db (drift docs), so
    // data inserted at v1 is present when we migrate a separate handle to v2.
    final schema = await verifier.schemaAt(1);
    final v1Db = v1.DatabaseAtV1(schema.newConnection());
    // The generated v1 helper has no typed companions — raw SQL is the intended
    // way to seed old-schema data.
    await v1Db.customStatement(
      "INSERT INTO food_logs "
      "(id, date, meal, name, energy_kcal, protein_g, carb_g, fat_g, "
      " logged_via, created_at, updated_at) "
      "VALUES ('keep-me','2026-07-20','lunch','dal tadka',180,0,0,0,"
      "'search',1,1)",
    );
    await v1Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 2); // runs onUpgrade, checks == v2 snapshot

    final logs = await db.select(db.foodLogs).get();
    expect(logs.map((r) => r.id), contains('keep-me'),
        reason: 'v1 data must survive the v2 migration');
    // The new table is usable.
    final profiles = await db.select(db.profiles).get();
    expect(profiles, isEmpty);
    await db.close();
  });

  test('database schema matches the committed v2 snapshot', () async {
    // Creates a fresh db from SakamaDatabase's Dart definitions and diffs it
    // against drift_schemas/drift_schema_v1.json. Fails if the code drifts
    // from the committed snapshot without a new schema version + migration.
    final connection = await verifier.startAt(2);
    final db = SakamaDatabase.withExecutor(connection);
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  // v2 onward: use verifier.startAt(N-1), insert representative rows, migrate,
  // and assert the data survived. See drift's step-by-step migration docs.
}
