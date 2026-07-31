import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../domain/plan.dart';

/// Persistence for user plans (M4). Offline-first over the local `user_plans`
/// table, synced per-user by PowerSync.
///
/// Single-active invariant: a user may keep several plans but exactly one is
/// active. This is enforced HERE (not by a DB constraint) so an offline
/// active-switch is never rejected mid-sync under LWW: activating one plan
/// deactivates the rest in the same local transaction.
///
/// PowerSync note: the synced tables are SQLite VIEWS with INSTEAD OF triggers,
/// so we never UPSERT (no ON CONFLICT against a view). Inserts and updates are
/// separate, explicit statements.
class PlanRepository {
  PlanRepository(this._db);
  final SakamaDatabase _db;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// The active plan row, decoded to a [Plan], or null when there is none or
  /// its stored config is unparseable (defensive — the row still exists and can
  /// be inspected/deleted via [watchAll]).
  Stream<Plan?> watchActivePlan() =>
      (_db.select(_db.userPlans)..where((t) => t.active.equals(true)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : Plan.tryParse(row.config));

  /// The active row itself (config string intact), for editing/inspection.
  Stream<UserPlanRow?> watchActiveRow() =>
      (_db.select(_db.userPlans)..where((t) => t.active.equals(true)))
          .watchSingleOrNull();

  Future<UserPlanRow?> getActiveRow() =>
      (_db.select(_db.userPlans)..where((t) => t.active.equals(true)))
          .getSingleOrNull();

  /// All saved plans, newest first (the plan library / history).
  Stream<List<UserPlanRow>> watchAll() => (_db.select(_db.userPlans)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  /// Save a new plan from its JSON [config]. Returns the new row id.
  ///
  /// [config] must already be validated JSON (the import / AI-generation layer
  /// validates with [Plan.tryParse] first); we store the string verbatim so the
  /// engine reads exactly what was authored. When [activate] is true this
  /// becomes the sole active plan.
  Future<String> savePlan({
    required String name,
    required String config,
    String source = 'user_imported',
    String? startDate,
    bool activate = true,
    String? userId,
  }) async {
    final id = uuid.v4();
    await _db.transaction(() async {
      if (activate) await _deactivateAll();
      await _db.into(_db.userPlans).insert(UserPlansCompanion.insert(
            id: id,
            userId: Value(userId),
            name: name,
            config: config,
            source: Value(source),
            active: Value(activate),
            startDate: Value(startDate),
            createdAt: _now,
            updatedAt: _now,
          ));
    });
    return id;
  }

  /// Make [id] the sole active plan.
  Future<void> setActive(String id) async {
    await _db.transaction(() async {
      await _deactivateAll();
      await (_db.update(_db.userPlans)..where((t) => t.id.equals(id)))
          .write(UserPlansCompanion(active: const Value(true), updatedAt: Value(_now)));
    });
  }

  /// Turn off any active plan (revert to the computed maintenance default).
  Future<void> clearActive() => _deactivateAll();

  Future<void> deletePlan(String id) async {
    await (_db.delete(_db.userPlans)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _deactivateAll() async {
    await (_db.update(_db.userPlans)..where((t) => t.active.equals(true)))
        .write(UserPlansCompanion(active: const Value(false), updatedAt: Value(_now)));
  }
}
