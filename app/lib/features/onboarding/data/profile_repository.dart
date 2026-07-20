import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';
import '../domain/enums.dart';
import '../domain/profile_record.dart';

/// Persists the single onboarding profile. Reads/writes local Drift only
/// (offline-first); sync carries it to other devices. Keeps exactly one row.
class ProfileRepository {
  ProfileRepository(this._db);
  final SakamaDatabase _db;

  Stream<ProfileRecord?> watch() =>
      _db.select(_db.profiles).watchSingleOrNull().map(_toRecord);

  Future<ProfileRecord?> get() async =>
      _toRecord(await _db.select(_db.profiles).getSingleOrNull());

  /// Upsert the one profile row. Reuses the existing id (and created_at) so
  /// this stays a single, stable, syncable row rather than accumulating.
  Future<void> save(ProfileRecord r, {String? userId}) async {
    final existing = await _db.select(_db.profiles).getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = ProfilesCompanion(
      id: Value(existing?.id ?? uuid.v4()),
      userId: Value(userId),
      dob: Value(_ymd(r.dob)),
      weightKg: Value(r.weightKg),
      heightCm: Value(r.heightCm),
      sex: Value(r.sex.name),
      activity: Value(r.activity.name),
      goal: Value(r.goal.name),
      diet: Value(r.diet.name),
      cuisine: Value(r.cuisine.name),
      conditions: Value(r.conditions.map((c) => c.name).join(',')),
      onboardingComplete: Value(r.onboardingComplete),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    );
    await _db.into(_db.profiles).insertOnConflictUpdate(row);
  }

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static ProfileRecord? _toRecord(ProfileRow? row) {
    if (row == null) return null;
    final parts = row.dob.split('-').map(int.parse).toList();
    return ProfileRecord(
      dob: DateTime(parts[0], parts[1], parts[2]),
      weightKg: row.weightKg,
      heightCm: row.heightCm,
      sex: Sex.values.byName(row.sex),
      activity: ActivityLevel.values.byName(row.activity),
      goal: Goal.values.byName(row.goal),
      diet: DietPreference.values.byName(row.diet),
      cuisine: CuisinePreference.values.byName(row.cuisine),
      conditions: row.conditions.isEmpty
          ? const []
          : row.conditions.split(',').map(HealthCondition.values.byName).toList(),
      onboardingComplete: row.onboardingComplete,
    );
  }
}
