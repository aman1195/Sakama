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
]);
