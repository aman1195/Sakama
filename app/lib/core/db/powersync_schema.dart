import 'package:powersync/powersync.dart';

/// PowerSync's view of the synced schema. MUST stay column-compatible with:
///  - the Drift tables in database.dart (client source of truth), and
///  - supabase/migrations/*.sql (server source of truth).
/// A new synced table/column touches all three, plus sync-streams.yaml.
///
/// `id` is implicit in PowerSync tables (client-generated text UUID).
const powersyncSchema = Schema([
  Table('food_logs', [
    Column.text('user_id'),
    Column.text('date'),
    Column.text('meal'),
    Column.text('name'),
    Column.real('grams'),
    Column.real('energy_kcal'),
    Column.real('protein_g'),
    Column.real('carb_g'),
    Column.real('fat_g'),
    Column.text('logged_via'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table('profiles', [
    Column.text('user_id'),
    Column.text('dob'),
    Column.real('weight_kg'),
    Column.real('height_cm'),
    Column.text('sex'),
    Column.text('activity'),
    Column.text('goal'),
    Column.text('diet'),
    Column.text('cuisine'),
    Column.text('conditions'),
    Column.integer('onboarding_complete'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table('water_logs', [
    Column.text('user_id'),
    Column.text('date'),
    Column.integer('amount_ml'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table('weight_logs', [
    Column.text('user_id'),
    Column.text('date'),
    Column.real('weight_kg'),
    Column.text('note'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table('user_plans', [
    Column.text('user_id'),
    Column.text('name'),
    Column.text('config'), // Plan JSON
    Column.text('source'),
    Column.integer('active'), // bool as 0/1 (as onboarding_complete)
    Column.text('start_date'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table('user_foods', [
    Column.text('user_id'),
    Column.text('name'),
    Column.text('kind'), // pointer | custom
    Column.text('source_table'),
    Column.text('source_id'),
    Column.real('energy_kcal'), // custom only; a pointer leaves these null so
    Column.real('protein_g'),   // no ODbL value ever reaches this table
    Column.real('carb_g'),
    Column.real('fat_g'),
    Column.real('fiber_g'),
    Column.text('serving_label'),
    Column.real('serving_grams'),
    Column.integer('use_count'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  // Vita conversations — LOCAL-ONLY by DESIGN (ADR 0016 decision 1), not
  // because they are reference data: health conversations never leave the
  // phone at rest, so there is deliberately no Supabase mirror, no RLS policy
  // and no sync-streams entry. See docs/architecture/06-vita-conversations.md.
  Table.localOnly('chat_threads', [
    Column.text('user_id'),
    Column.text('title'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.text('summary'),
    Column.integer('summarized_up_to'),
  ]),
  // What Vita has learned (ADR 0016 phase 4). Local-only for the same reason
  // as the conversations it is derived from: the promise is that it never
  // leaves the phone at rest, and a synced table could not make that promise.
  Table.localOnly('memory_facts', [
    Column.text('user_id'),
    Column.text('kind'),
    Column.text('content'),
    Column.real('confidence'),
    Column.text('source_thread_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
  ]),
  Table.localOnly('chat_messages', [
    Column.text('thread_id'),
    Column.text('role'),
    Column.text('content'),
    Column.integer('synthetic'), // bool as 0/1
    Column.integer('created_at'),
  ]),
  // Reference tables — LOCAL-ONLY: real SQLite tables PowerSync creates but
  // never syncs and never routes through the upload queue. They hold shipped
  // reference data, not per-user data, so there is no Supabase mirror and no
  // sync-streams entry. Columns must still match database.dart (the alignment
  // test cross-checks the two Dart reps).
  Table.localOnly('foods', [
    Column.text('name'),
    Column.text('name_hi'),
    Column.text('type'),
    Column.text('cuisine_region'),
    Column.text('food_group'),
    Column.real('energy_kcal'),
    Column.real('protein_g'),
    Column.real('carb_g'),
    Column.real('fat_g'),
    Column.real('fiber_g'),
    Column.text('default_serving_label'),
    Column.real('default_serving_grams'),
    Column.text('source'),
    Column.text('licence'),
    Column.real('confidence'),
    Column.text('source_ref'),
  ]),
  // ODbL, physically separate from `foods` (CLAUDE.md rule 5).
  Table.localOnly('off_foods', [
    Column.text('name'),
    Column.text('barcode'),
    Column.text('type'),
    Column.text('cuisine_region'),
    Column.text('food_group'),
    Column.real('energy_kcal'),
    Column.real('protein_g'),
    Column.real('carb_g'),
    Column.real('fat_g'),
    Column.real('fiber_g'),
    Column.text('default_serving_label'),
    Column.real('default_serving_grams'),
    Column.text('source'),
    Column.text('licence'),
    Column.real('confidence'),
    Column.text('source_ref'),
  ]),
]);
