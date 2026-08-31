import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;

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

    // Migrates to the CURRENT version, not to 6. Once a table's Dart
    // definition gains columns, createTable() in an earlier step emits the
    // NEW shape, so an old database can never be made to match an
    // intermediate snapshot again. Production only ever migrates to the
    // latest version anyway; what must be proven is that data survives the
    // whole journey, which is what this now asserts.
    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 8);

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

  test('v6 -> v7 adds user_foods AND preserves all user data', () async {
    final schema = await verifier.schemaAt(6);
    final v6Db = v6.DatabaseAtV6(schema.newConnection());
    // Seed a row in EVERY existing table, synced and local-only alike.
    await v6Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-08-06','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v6Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v6Db.customStatement(
      "INSERT INTO water_logs (id, date, amount_ml, created_at, updated_at) "
      "VALUES ('w','2026-08-06',250,1,1)");
    await v6Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-08-06',70.5,1,1)");
    await v6Db.customStatement(
      "INSERT INTO user_plans (id, name, config, source, active, created_at, "
      "updated_at) VALUES ('pl','P','{}','user_imported',1,1,1)");
    await v6Db.customStatement(
      "INSERT INTO chat_threads (id, title, created_at, updated_at) "
      "VALUES ('t','Knee injury',1,1)");
    await v6Db.customStatement(
      "INSERT INTO chat_messages (id, thread_id, role, content, synthetic, "
      "created_at) VALUES ('m','t','user','hello',0,1)");
    await v6Db.close();

    // To the CURRENT version, for the reason given in the v5 -> v6 test.
    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 8);

    // Every pre-existing row survived (MOBILE.md: a bad migration destroys
    // user data irrecoverably) — including the device-local conversation.
    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'));
    expect((await db.select(db.waterLogs).get()).map((r) => r.id), contains('w'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id), contains('wt'));
    expect((await db.select(db.userPlans).get()).map((r) => r.id), contains('pl'));
    expect((await db.select(db.chatThreads).get()).map((r) => r.id), contains('t'));
    expect((await db.select(db.chatMessages).get()).map((r) => r.id), contains('m'));
    // The new table exists and is usable (born empty).
    expect(await db.select(db.userFoods).get(), isEmpty);
    await db.close();
  });

  test('v7 -> v8 adds memory_facts, ALTERS chat_threads, and preserves all data',
      () async {
    // The FIRST migration in this database that alters an existing table
    // rather than only adding new ones, so this test asserts more than
    // survival: it checks the pre-existing chat_threads VALUES are intact and
    // that the two added columns take their defaults on old rows.
    final schema = await verifier.schemaAt(7);
    final v7Db = v7.DatabaseAtV7(schema.newConnection());
    await v7Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-08-06','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v7Db.customStatement(
      "INSERT INTO profiles (id, dob, weight_kg, height_cm, sex, activity, "
      "goal, diet, cuisine, conditions, onboarding_complete, created_at, "
      "updated_at) VALUES ('p','1994-01-01',70,175,'male','moderate','maintain',"
      "'veg','both','',1,1,1)");
    await v7Db.customStatement(
      "INSERT INTO water_logs (id, date, amount_ml, created_at, updated_at) "
      "VALUES ('w','2026-08-06',250,1,1)");
    await v7Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-08-06',70.5,1,1)");
    await v7Db.customStatement(
      "INSERT INTO user_plans (id, name, config, source, active, created_at, "
      "updated_at) VALUES ('pl','P','{}','user_imported',1,1,1)");
    await v7Db.customStatement(
      "INSERT INTO user_foods (id, name, kind, use_count, created_at, "
      "updated_at) VALUES ('uf','rajma','custom',3,1,1)");
    await v7Db.customStatement(
      "INSERT INTO chat_threads (id, title, created_at, updated_at) "
      "VALUES ('t','Knee injury',11,22)");
    await v7Db.customStatement(
      "INSERT INTO chat_messages (id, thread_id, role, content, synthetic, "
      "created_at) VALUES ('m','t','user','hello',0,1)");
    await v7Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 8);

    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.profiles).get()).map((r) => r.id), contains('p'));
    expect((await db.select(db.waterLogs).get()).map((r) => r.id), contains('w'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id), contains('wt'));
    expect((await db.select(db.userPlans).get()).map((r) => r.id), contains('pl'));
    expect((await db.select(db.userFoods).get()).map((r) => r.id), contains('uf'));
    expect((await db.select(db.chatMessages).get()).map((r) => r.id), contains('m'));

    // The ALTERED table: the conversation kept its identity AND its values.
    // Checking only that the row exists would pass even if ADD COLUMN had
    // rewritten the table and lost the timestamps the thread list sorts on.
    final thread = await (db.select(db.chatThreads)
          ..where((t) => t.id.equals('t')))
        .getSingle();
    expect(thread.title, 'Knee injury');
    expect(thread.createdAt, 11);
    expect(thread.updatedAt, 22);
    // New columns take their declared defaults on a pre-existing row: no
    // summary yet, and nothing summarised so far.
    expect(thread.summary, isNull);
    expect(thread.summarizedUpTo, 0);

    // The new table exists and is usable (born empty).
    expect(await db.select(db.memoryFacts).get(), isEmpty);
    await db.close();
  });

  test('v8 -> v9 adds workouts AND preserves all user data', () async {
    final schema = await verifier.schemaAt(8);
    final v8Db = v8.DatabaseAtV8(schema.newConnection());
    await v8Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, energy_kcal, protein_g, "
      "carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-08-27','lunch','dal',180,9,22,6,'quick_add',1,1)");
    await v8Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-08-27',84.0,1,1)");
    await v8Db.customStatement(
      "INSERT INTO chat_threads (id, title, created_at, updated_at, "
      "summarized_up_to) VALUES ('t','Knee injury',11,22,3)");
    await v8Db.customStatement(
      "INSERT INTO memory_facts (id, kind, content, confidence, created_at, "
      "updated_at) VALUES ('mf','constraint','Lactose intolerant',0.9,1,1)");
    await v8Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 9);

    expect((await db.select(db.foodLogs).get()).map((r) => r.id), contains('fl'));
    expect((await db.select(db.weightLogs).get()).map((r) => r.id), contains('wt'));
    // The v8 additions specifically — a migration that drops the thing the
    // PREVIOUS migration added is the easiest one to write by accident.
    final fact = await db.select(db.memoryFacts).getSingle();
    expect(fact.content, 'Lactose intolerant');
    final thread = await db.select(db.chatThreads).getSingle();
    expect(thread.summarizedUpTo, 3);

    expect(await db.select(db.workouts).get(), isEmpty);
    await db.close();
  });

  test('v9 -> v10 adds serving columns AND preserves all user data', () async {
    final schema = await verifier.schemaAt(9);
    final v9Db = v9.DatabaseAtV9(schema.newConnection());
    await v9Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, grams, energy_kcal, "
      "protein_g, carb_g, fat_g, logged_via, created_at, updated_at) "
      "VALUES ('fl','2026-08-28','lunch','dal',150,180,9,22,6,'search',1,1)");
    await v9Db.customStatement(
      "INSERT INTO workouts (id, date, name, kind, sets, logged_via, "
      "created_at, updated_at) "
      "VALUES ('w','2026-08-28','bench','strength','[]','vita',1,1)");
    await v9Db.customStatement(
      "INSERT INTO weight_logs (id, date, weight_kg, created_at, updated_at) "
      "VALUES ('wt','2026-08-28',84.0,1,1)");
    await v9Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 10);

    // The pre-existing row survives WITH ITS VALUES, and its new columns are
    // null rather than defaulted — an old entry has no stated portion, and a
    // fabricated one would claim the user said something they did not.
    final log = await db.select(db.foodLogs).getSingle();
    expect(log.id, 'fl');
    expect(log.grams, 150);
    expect(log.energyKcal, 180);
    expect(log.servingLabel, isNull);
    expect(log.servingQty, isNull);

    // v9's own addition specifically — a migration that drops what the
    // previous one added is the easiest to write by accident.
    expect((await db.select(db.workouts).getSingle()).name, 'bench');
    expect((await db.select(db.weightLogs).getSingle()).weightKg, 84.0);
    await db.close();
  });

  test('v10 -> v11 adds meals AND preserves all user data', () async {
    final schema = await verifier.schemaAt(10);
    final v10Db = v10.DatabaseAtV10(schema.newConnection());
    await v10Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, grams, serving_label, "
      "serving_qty, energy_kcal, protein_g, carb_g, fat_g, logged_via, "
      "created_at, updated_at) VALUES ('fl','2026-08-30','lunch','dal',225,"
      "'katori',1.5,180,9,22,6,'search',1,1)");
    await v10Db.customStatement(
      "INSERT INTO user_foods (id, name, kind, use_count, created_at, "
      "updated_at) VALUES ('uf','mum rajma','custom',3,1,1)");
    await v10Db.customStatement(
      "INSERT INTO workouts (id, date, name, kind, sets, logged_via, "
      "created_at, updated_at) "
      "VALUES ('w','2026-08-30','bench','strength','[]','vita',1,1)");
    await v10Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 11);

    // v10's own addition specifically — the serving pair must survive the
    // migration that follows it.
    final log = await db.select(db.foodLogs).getSingle();
    expect(log.servingLabel, 'katori');
    expect(log.servingQty, 1.5);
    expect(log.grams, 225);

    // The table meals will point AT must survive, or every meal breaks.
    expect((await db.select(db.userFoods).getSingle()).name, 'mum rajma');
    expect((await db.select(db.workouts).getSingle()).name, 'bench');

    expect(await db.select(db.meals).get(), isEmpty);
    await db.close();
  });

  test('v11 -> v12 adds target_history AND preserves all user data', () async {
    final schema = await verifier.schemaAt(11);
    final v11Db = v11.DatabaseAtV11(schema.newConnection());
    await v11Db.customStatement(
      "INSERT INTO food_logs (id, date, meal, name, grams, serving_label, "
      "serving_qty, energy_kcal, protein_g, carb_g, fat_g, logged_via, "
      "created_at, updated_at) VALUES ('fl','2026-08-31','lunch','dal',225,"
      "'katori',1.5,180,9,22,6,'search',1,1)");
    await v11Db.customStatement(
      "INSERT INTO meals (id, name, items, use_count, created_at, updated_at) "
      "VALUES ('m','usual breakfast','[]',4,1,1)");
    await v11Db.customStatement(
      "INSERT INTO user_foods (id, name, kind, use_count, created_at, "
      "updated_at) VALUES ('uf','mum rajma','custom',3,1,1)");
    await v11Db.customStatement(
      "INSERT INTO workouts (id, date, name, kind, sets, logged_via, "
      "created_at, updated_at) "
      "VALUES ('w','2026-08-31','bench','strength','[]','vita',1,1)");
    await v11Db.close();

    final db = SakamaDatabase.withExecutor(schema.newConnection());
    await verifier.migrateAndValidate(db, 12);

    // The rows this table exists to SCORE must survive the migration that
    // adds it — a lost log is worse than a mis-scored one.
    final log = await db.select(db.foodLogs).getSingle();
    expect(log.servingLabel, 'katori');
    expect(log.servingQty, 1.5);
    expect(log.grams, 225);

    // v11's own addition specifically, plus the tables around it.
    expect((await db.select(db.meals).getSingle()).name, 'usual breakfast');
    expect((await db.select(db.userFoods).getSingle()).name, 'mum rajma');
    expect((await db.select(db.workouts).getSingle()).name, 'bench');

    // Empty, not absent: an upgrading device has no recorded history until the
    // seed row lands, and the diary falls back rather than showing zeros.
    expect(await db.select(db.targetHistory).get(), isEmpty);
    await db.close();
  });

  test('database schema matches the committed v12 snapshot', () async {
    // Creates a fresh db from SakamaDatabase's Dart definitions and diffs it
    // against drift_schemas/drift_schema_v12.json. Fails if the code drifts
    // from the committed snapshot without a new schema version + migration.
    final connection = await verifier.startAt(12);
    final db = SakamaDatabase.withExecutor(connection);
    await verifier.migrateAndValidate(db, 12);
    await db.close();
  });

  // v2 onward: use verifier.startAt(N-1), insert representative rows, migrate,
  // and assert the data survived. See drift's step-by-step migration docs.
}
