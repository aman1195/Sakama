import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// Reads the receipts the upload path leaves when the server refuses a write.
///
/// The point of the table is that a discarded op stops being invisible. This
/// is the read side: a count the UI can show, the rows behind it, and a way to
/// clear them once the user has seen them.
class SyncFailureRepository {
  SyncFailureRepository(this._db);
  final SakamaDatabase _db;

  /// Newest first — the most recent loss is the one the user is asking about.
  Stream<List<SyncFailureRow>> watchAll() =>
      (_db.select(_db.syncFailures)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<List<SyncFailureRow>> all() =>
      (_db.select(_db.syncFailures)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<int> watchCount() => watchAll().map((rows) => rows.length);

  Future<void> clear() => _db.delete(_db.syncFailures).go();

  Future<void> dismiss(String id) =>
      (_db.delete(_db.syncFailures)..where((t) => t.id.equals(id))).go();

  /// What the row was, in the user's words rather than the table's.
  ///
  /// A receipt that says `food_logs` and `23514` tells the user nothing about
  /// what they lost. The payload holds the row as it was sent, so the entry can
  /// be named — "Butter Chicken" — which is the only part they recognise.
  static String describe(SyncFailureRow row) {
    final label = switch (row.targetTable) {
      'food_logs' => 'A food entry',
      'workouts' => 'A workout',
      'water_logs' => 'A water entry',
      'weight_logs' => 'A weight entry',
      'meals' => 'A saved meal',
      'user_foods' => 'A saved food',
      'user_plans' => 'A plan',
      'target_history' => 'A target change',
      'profiles' => 'Your profile',
      _ => 'An entry',
    };
    final name = _nameFrom(row.payload);
    return name == null ? label : '$label · $name';
  }

  static String? _nameFrom(String? payload) {
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      for (final key in ['name', 'date']) {
        final v = decoded[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {
      // A malformed payload is not worth failing a list render over.
    }
    return null;
  }
}
