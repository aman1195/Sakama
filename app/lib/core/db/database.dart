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

/// Water intake events (one row per drink). Summed per day against the water
/// target. Same three-file sync contract as the other synced tables.
class WaterLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get amountMl => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // LWW

  @override
  Set<Column> get primaryKey => {id};
}

/// Weight measurements over time (the profile weight is the onboarding value;
/// these are the tracked trend that powers the weight chart).
class WeightLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get date => text()(); // yyyy-MM-dd
  RealColumn get weightKg => real()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // LWW

  @override
  Set<Column> get primaryKey => {id};
}

/// A user's saved plans (M4, ADR 0007). Plans are DATA: [config] holds the whole
/// Plan JSON, interpreted by the plan engine. A user may keep several plans but
/// exactly one is [active] (the repository enforces single-active); the rest are
/// history they can switch back to. Synced per-user like the other tables.
@DataClassName('UserPlanRow')
class UserPlans extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()(); // offline-birth rule (as FoodLogs)
  TextColumn get name => text()();
  TextColumn get config => text()(); // the Plan JSON (jsonEncode of the config)
  TextColumn get source =>
      text().withDefault(const Constant('user_imported'))(); // ai_generated|user_imported|template
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  TextColumn get startDate => text().nullable()(); // yyyy-MM-dd (cyclic/duration)
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // LWW

  @override
  Set<Column> get primaryKey => {id};
}

/// Foods the user CHOSE to keep: favourites and their own creations
/// (docs/architecture/08-user-foods.md). Synced, unlike conversations — this is
/// per-user data worth surviving a lost phone.
///
/// Deliberately NOT `foods`: `ensureSeeded` runs DELETE FROM foods on every
/// seedVersion bump, which would silently destroy user-authored rows (#35).
///
/// LICENCE (CLAUDE.md rule 5): a [kind] of 'pointer' stores NO nutrition — only
/// where to read it from, plus the user's portion. That keeps ODbL values from
/// Open Food Facts out of this synced table entirely. Only 'custom' rows carry
/// nutrition, and those values are the user's own.
@DataClassName('UserFoodRow')
class UserFoods extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()(); // what the USER calls it
  TextColumn get kind => text()(); // pointer | custom

  /// Pointer only: where the nutrition actually lives.
  TextColumn get sourceTable => text().nullable()(); // foods | off_foods
  TextColumn get sourceId => text().nullable()();

  /// Custom only, per 100 g (the canonical unit, as everywhere else).
  RealColumn get energyKcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get fiberG => real().nullable()();

  /// The user's usual portion — the thing no corpus can know.
  TextColumn get servingLabel => text().nullable()();
  RealColumn get servingGrams => real().nullable()();

  /// Drives most-used ordering, so the common path gets shorter with use.
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // LWW

  @override
  Set<Column> get primaryKey => {id};
}

/// One Vita conversation (ADR 0016 phase 1). LOCAL-ONLY and deliberately so:
/// health conversations never leave the phone at rest, so there is no Supabase
/// mirror, no RLS policy and no sync-streams entry (docs/architecture/06).
///
/// [userId] scopes threads to the signed-in user on a shared device. Because a
/// local-only row NEVER uploads, Postgres never backfills it — so the
/// repository scopes strictly to the current uid and backfills nulls locally.
@DataClassName('ChatThreadRow')
class ChatThreads extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get title => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()(); // last activity; thread list sorts on this

  @override
  Set<Column> get primaryKey => {id};
}

/// One turn in a conversation. LOCAL-ONLY (see [ChatThreads]).
///
/// [synthetic] marks app chrome (budget/error notices) — kept in the visible
/// transcript but never replayed upstream, so the model can't mistake our copy
/// for its own prior reply (review #58).
@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();
  TextColumn get role => text()(); // 'user' | 'vita'
  TextColumn get content => text()();
  BoolColumn get synthetic => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The food reference table — the searchable corpus users log against
/// (USDA CC0 now; Indian dishes via AI estimation + a commercial licence later.
/// NOT INDB — unlicensed + IFCT-derived, see CLAUDE.md rule 6). READ-ONLY
/// REFERENCE DATA, not per-user: it is a PowerSync
/// `localOnly` table (see powersync_schema.dart), so it never syncs and never
/// enters the upload queue, and there is deliberately NO Supabase mirror.
///
/// Every row carries source / licence / confidence (CLAUDE.md rule 7) so we can
/// prove provenance and rank verified data above AI estimates. Nutrition is
/// canonical PER 100 g (CLAUDE.md); per-serving is derived at read time.
@DataClassName('FoodRow')
class Foods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameHi => text().nullable()();
  TextColumn get type => text()(); // dish | ingredient | branded
  TextColumn get cuisineRegion => text().nullable()();
  TextColumn get foodGroup => text().nullable()();
  RealColumn get energyKcal => real()(); // per 100 g
  RealColumn get proteinG => real()();
  RealColumn get carbG => real()();
  RealColumn get fatG => real()();
  RealColumn get fiberG => real().nullable()();
  TextColumn get defaultServingLabel => text().nullable()(); // "1 katori"
  RealColumn get defaultServingGrams => real().nullable()();
  TextColumn get source => text()(); // sample | usda_fdc | ai_estimate | <licensed>

  TextColumn get licence => text()(); // CC0 | CC-BY-4.0 | ODbL | computed
  RealColumn get confidence => real()(); // 0..1 — 1.0 measured, lower for AI
  TextColumn get sourceRef => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Open Food Facts foods — ODbL. PHYSICALLY SEPARATE from [Foods] by mandate
/// (CLAUDE.md rule 5: the single biggest legal risk in the stack). Its share-
/// alike licence must never contaminate the proprietary table, so the boundary
/// is structural, not a `source` filter on a shared table. Also `localOnly`.
/// Empty until the OFF snapshot + barcode work in M2.3; declared now so the
/// separation is a schema-level invariant, not a future migration.
@DataClassName('OffFoodRow')
class OffFoods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get type => text()();
  TextColumn get cuisineRegion => text().nullable()();
  TextColumn get foodGroup => text().nullable()();
  RealColumn get energyKcal => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbG => real()();
  RealColumn get fatG => real()();
  RealColumn get fiberG => real().nullable()();
  TextColumn get defaultServingLabel => text().nullable()();
  RealColumn get defaultServingGrams => real().nullable()();
  TextColumn get source => text()(); // always 'openfoodfacts'
  TextColumn get licence => text()(); // always 'ODbL'
  RealColumn get confidence => real()();
  TextColumn get sourceRef => text().nullable()(); // OFF:<barcode>

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
    tables: [FoodLogs, Profiles, WaterLogs, WeightLogs, UserPlans, UserFoods,
      ChatThreads, ChatMessages, Foods, OffFoods])
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => managedExternally
      ? MigrationStrategy(onCreate: (m) async {}, onUpgrade: (m, from, to) async {})
      : MigrationStrategy(
          onCreate: (m) async => m.createAll(),
          // MOBILE.md rule: every schema change ships a tested, forward-only
          // migration. A bad migration destroys user data irrecoverably.
          // Each step is ADDITIVE (new tables), so no existing data is touched.
          onUpgrade: (m, from, to) async {
            if (from < 2) {
              await m.createTable(profiles);
            }
            if (from < 3) {
              await m.createTable(waterLogs);
              await m.createTable(weightLogs);
            }
            if (from < 4) {
              // Local-only reference tables. In production PowerSync creates
              // these (localOnly schema); this Drift DDL path runs only in
              // plain-Drift mode (tests/local-only). Additive — no existing
              // user row is touched.
              await m.createTable(foods);
              await m.createTable(offFoods);
            }
            if (from < 5) {
              // M4: user_plans (synced). Additive — no existing row is touched.
              await m.createTable(userPlans);
            }
            if (from < 6) {
              // ADR 0016 phase 1: Vita conversations. LOCAL-ONLY tables — in
              // production PowerSync creates these; this Drift DDL path runs in
              // plain-Drift mode (tests/local-only). Additive — no existing row
              // is touched.
              await m.createTable(chatThreads);
              await m.createTable(chatMessages);
            }
            if (from < 7) {
              // Favourites + custom foods (#35). Additive — no existing row is
              // touched. Synced, so it also has a Supabase mirror + RLS.
              await m.createTable(userFoods);
            }
          },
        );

  Stream<List<FoodLog>> watchDay(String date) =>
      (select(foodLogs)..where((t) => t.date.equals(date))).watch();
}
