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

@DriftDatabase(tables: [FoodLogs])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => managedExternally
      ? MigrationStrategy(onCreate: (m) async {}, onUpgrade: (m, from, to) async {})
      : MigrationStrategy(
          onCreate: (m) async => m.createAll(),
          // MOBILE.md rule: every future schema change ships a tested, forward-only
          // migration here. A bad migration destroys user data irrecoverably.
          onUpgrade: (m, from, to) async {},
        );

  Stream<List<FoodLog>> watchDay(String date) =>
      (select(foodLogs)..where((t) => t.date.equals(date))).watch();
}
