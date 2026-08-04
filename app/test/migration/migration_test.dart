import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

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

  test('v2 -> v3 migration adds water_logs + weight_logs AND preserves data',
      () async {
    final schema = await verifier.schemaAt(2);
    final v2Db = v2.DatabaseAtV2(schema.newConnection());
    // Seed a v2 food_log AND a v2 profile; both must survive to v3.
    await v2Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-07-20','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v2Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v2Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);

    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'),
        reason: 'food_logs must survive v3');
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'),
        reason: 'profiles must survive v3');
    // The two new tables exist and are usable.
    expect(await db.select(db.waterLogs).get(), isEmpty);
    expect(await db.select(db.weightLogs).get(), isEmpty);
    await db.close();
  });

  test('v3 -> v4 adds foods + off_foods AND preserves all user data', () async {
    final schema = await verifier.schemaAt(3);
    final v3Db = v3.DatabaseAtV3(schema.newConnection());
    // Seed one row in every EXISTING (synced) table; all must survive v4.
    await v3Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-07-21','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v3Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v3Db.customStatement(
      "INSERT INTO water_logs (id, date, amount_ml, created_at, updated_at) "
      "VALUES ('w','2026-07-21',250,1,1)");
    await v3Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-07-21',70.5,1,1)");
    await v3Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);

    // Every pre-existing row survived the migration (MOBILE.md: a bad
    // migration destroys user data irrecoverably).
    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'));
    expect((await db.select(db.waterLogs).get()).map((r) => r.id), contains('w'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id),
        contains('wt'));
    // The two new reference tables exist and are usable (born empty; seeding
    // is the repository's job, not the migration's).
    expect(await db.select(db.foods).get(), isEmpty);
    expect(await db.select(db.offFoods).get(), isEmpty);
    await db.close();
  });

  test('v4 -> v5 adds user_plans AND preserves all user data', () async {
    final schema = await verifier.schemaAt(4);
    final v4Db = v4.DatabaseAtV4(schema.newConnection());
    // Seed one row in every EXISTING synced table; all must survive v5.
    await v4Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-07-22','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v4Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v4Db.customStatement(
      "INSERT INTO water_logs (id, date, amount_ml, created_at, updated_at) "
      "VALUES ('w','2026-07-22',250,1,1)");
    await v4Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-07-22',70.5,1,1)");
    await v4Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);

    // Every pre-existing row survived (MOBILE.md: a bad migration destroys
    // user data irrecoverably).
    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'));
    expect((await db.select(db.waterLogs).get()).map((r) => r.id), contains('w'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id),
        contains('wt'));
    // The new table exists and is usable (born empty).
    expect(await db.select(db.userPlans).get(), isEmpty);
    await db.close();
  });

  test('v5 -> v6 adds the local-only chat tables AND preserves all user data',
      () async {
    final schema = await verifier.schemaAt(5);
    final v5Db = v5.DatabaseAtV5(schema.newConnection());
    // Seed a row in every EXISTING synced table; all must survive v6.
    await v5Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-08-04','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v5Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v5Db.customStatement(
      "INSERT INTO water_logs (id, date, amount_ml, created_at, updated_at) "
      "VALUES ('w','2026-08-04',250,1,1)");
    await v5Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-08-04',70.5,1,1)");
    await v5Db.customStatement(
      "INSERT INTO user_plans (id, name, config, source, active, created_at, "
      "updated_at) VALUES ('pl','P','{}','user_imported',1,1,1)");
    await v5Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);

    // Every pre-existing row survived (MOBILE.md: a bad migration destroys
    // user data irrecoverably) — including the M4 plan.
    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'));
    expect((await db.select(db.waterLogs).get()).map((r) => r.id), contains('w'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id), contains('wt'));
    expect((await db.select(db.userPlans).get()).map((r) => r.id), contains('pl'));
    // The new local-only tables exist and are usable (born empty).
    expect(await db.select(db.chatThreads).get(), isEmpty);
    expect(await db.select(db.chatMessages).get(), isEmpty);
    await db.close();
  });

  test('database schema matches the committed v6 snapshot', () async {
    // Creates a fresh db from SakamaDatabase's Dart definitions and diffs it
    // against drift_schemas/drift_schema_v6.json. Fails if the code drifts
    // from the committed snapshot without a new schema version + migration.
    final connection = await verifier.startAt(6);
    final db = SakamaDatabase.withExecutor(connection);
    await verifier.migrateAndValidate(db, 6);
    await db.close();
  });

  // v2 onward: use verifier.startAt(N-1), insert representative rows, migrate,
  // and assert the data survived. See drift's step-by-step migration docs.
}
