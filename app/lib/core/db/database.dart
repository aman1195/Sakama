import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Nutrition is stored canonically per the logged portion here; the foods
/// reference table (per-100g) arrives in M2. `updatedAt` drives last-write-wins
/// sync when PowerSync is wired (ADR 0003).
class FoodLogs extends Table {
  TextColumn get id => text()();

  /// Owner. Nullable on-device: rows can be born before first sign-in
  /// (offline-first). Server-side the column is NOT NULL with a default of
  /// auth.uid(), and PowerSync omits null columns from uploads, so the
  /// default fills it. TODO(M1): set from the session at insert once auth
  /// exists, and backfill pre-auth rows on first sign-in.
  TextColumn get userId => text().nullable()();
  TextColumn get date => text()(); // yyyy-MM-dd (user's local day)
  TextColumn get meal => text()(); // breakfast | lunch | dinner | snack
  TextColumn get name => text()();
  RealColumn get grams => real().nullable()();
  RealColumn get energyKcal => real()();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get carbG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();
  TextColumn get loggedVia => text().withDefault(const Constant('search'))();
  IntColumn get createdAt => integer()(); // epoch ms
  IntColumn get updatedAt => integer()(); // epoch ms — LWW conflict key

  @override
  Set<Column> get primaryKey => {id};
}

/// The user's onboarding profile — one row per user. Enums are stored by name
/// (their `.name` string), conditions as a comma-joined list, dob as yyyy-MM-dd
/// (age is DERIVED at read time — storing age would silently go stale). Mirrors
/// supabase/migrations and powersync_schema.dart (the three-file sync contract).
@DataClassName('ProfileRow') // avoid colliding with the domain Profile
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()(); // same offline-birth rule as FoodLogs
  TextColumn get dob => text()(); // yyyy-MM-dd
  RealColumn get weightKg => real()();
  RealColumn get heightCm => real()();
  TextColumn get sex => text()();
  TextColumn get activity => text()();
  TextColumn get goal => text()();
  TextColumn get diet => text()();
  TextColumn get cuisine => text()();
  TextColumn get conditions => text().withDefault(const Constant(''))();
  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // LWW

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FoodLogs, Profiles])
class SakamaDatabase extends _$SakamaDatabase {
  SakamaDatabase()
      : managedExternally = false,
        super(driftDatabase(name: 'sakama'));

  /// Test seam AND the production path over PowerSync.
  ///
  /// [managedExternally]: PowerSync owns the physical schema (its tables are
  /// views over synced data), so Drift must not CREATE TABLE or migrate —
  /// schema evolution for synced tables happens in powersync_schema.dart +
  /// the Supabase migration, not here. Plain-Drift mode (tests, local-only)
  /// keeps the normal create/migrate path.
  SakamaDatabase.withExecutor(super.executor, {this.managedExternally = false});

  final bool managedExternally;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => managedExternally
      ? MigrationStrategy(onCreate: (m) async {}, onUpgrade: (m, from, to) async {})
      : MigrationStrategy(
          onCreate: (m) async => m.createAll(),
          // MOBILE.md rule: every schema change ships a tested, forward-only
          // migration. A bad migration destroys user data irrecoverably.
          // v2: add the profiles table. Additive — no existing data touched.
          onUpgrade: (m, from, to) async {
            if (from < 2) {
              await m.createTable(profiles);
            }
          },
        );

  Stream<List<FoodLog>> watchDay(String date) =>
      (select(foodLogs)..where((t) => t.date.equals(date))).watch();
}
