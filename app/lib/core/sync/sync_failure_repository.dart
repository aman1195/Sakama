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
      (_db.select(_db.syncFailures)..orderBy(_newestFirst)).watch();

  Future<List<SyncFailureRow>> all() =>
      (_db.select(_db.syncFailures)..orderBy(_newestFirst)).get();

  /// A COUNT, not a list mapped to its length: the count drives a badge that
  /// re-reads on every write, and every row carries a payload.
  Stream<int> watchCount() {
    final c = _db.syncFailures.id.count();
    return (_db.selectOnly(_db.syncFailures)..addColumns([c]))
        .map((r) => r.read(c) ?? 0)
        .watchSingle();
  }

  /// Receipts for one poison batch land in the same millisecond, so `id`
  /// breaks the tie and the list does not reshuffle between reads.
  static final _newestFirst = [
    (dynamic t) => OrderingTerm.desc(t.createdAt as GeneratedColumn<int>),
    (dynamic t) => OrderingTerm.desc(t.id as GeneratedColumn<String>),
  ];

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

/// The receipt INSERT, built as data.
///
/// Separate from the connector for two reasons, both learned the hard way.
///
/// It is TESTABLE. The connector holds a PowerSyncDatabase, and the first
/// version called SQL `uuid()`, which only PowerSync's extension provides — so
/// the one statement in the system whose failure is swallowed by a catch could
/// not be exercised against a plain database at all. A wrong column name or a
/// miscounted placeholder would have been invisible in exactly the way this
/// feature exists to prevent.
///
/// It is IDEMPOTENT. The id is PowerSync's own `clientId` for the op, not a
/// fresh uuid. A transaction holding a poison op AND then hitting a transient
/// failure never completes, so it retries every 30 seconds and re-records the
/// same loss forever — "121 entries didn't save" for one entry. Keyed by
/// clientId with INSERT OR REPLACE, a retry updates the receipt it already
/// wrote.
class SyncFailureStatement {
  const SyncFailureStatement(this.sql, this.params);
  final String sql;
  final List<Object?> params;

  static const _sql = 'INSERT OR REPLACE INTO sync_failures '
      '(id, target_table, op, row_id, code, message, payload, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)';

  static SyncFailureStatement build({
    required int clientId,
    required String table,
    required String op,
    required String rowId,
    String? code,
    String? message,
    Map<String, dynamic>? payload,
    required int at,
  }) =>
      SyncFailureStatement(_sql, [
        clientId.toString(),
        table,
        op,
        rowId,
        code,
        message,
        payload == null ? null : jsonEncode(payload),
        at,
      ]);
}
