import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// Persistence for Vita conversations (ADR 0016 phase 1). Device-local: these
/// tables are `Table.localOnly`, so nothing here syncs, has an RLS policy, or
/// reaches a server.
///
/// ISOLATION (docs/architecture/06 §2): a local-only row never uploads, so
/// Postgres never backfills a null `user_id` the way it does for synced tables.
/// Scoping is therefore explicit and strict:
///  - reads match the CURRENT uid only; a null `user_id` is visible to no one
///    once a session exists — never treated as "matches everybody";
///  - [adoptOrphanThreads] backfills nulls locally once a session resolves, so
///    a genuinely pre-auth conversation is adopted rather than stranded.
class ChatRepository {
  ChatRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;
  final SakamaDatabase _db;

  /// Injectable so ordering is deterministic in tests — two rows created in the
  /// same millisecond would otherwise tie on [updatedAt] and fall back to a
  /// random uuid tiebreak.
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  /// Threads for [userId], most recent activity first.
  Stream<List<ChatThreadRow>> watchThreads(String? userId) =>
      (_db.select(_db.chatThreads)
            ..where((t) => _ownedBy(t, userId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.id), // deterministic tiebreak
            ]))
          .watch();

  /// The transcript of [threadId], oldest first.
  Stream<List<ChatMessageRow>> watchMessages(String threadId) =>
      (_db.select(_db.chatMessages)
            ..where((m) => m.threadId.equals(threadId))
            ..orderBy([
              (m) => OrderingTerm.asc(m.createdAt),
              (m) => OrderingTerm.asc(m.id),
            ]))
          .watch();

  Future<List<ChatMessageRow>> messagesOf(String threadId) =>
      (_db.select(_db.chatMessages)
            ..where((m) => m.threadId.equals(threadId))
            ..orderBy([
              (m) => OrderingTerm.asc(m.createdAt),
              (m) => OrderingTerm.asc(m.id),
            ]))
          .get();

  Future<ChatThreadRow?> latestThread(String? userId) =>
      (_db.select(_db.chatThreads)
            ..where((t) => _ownedBy(t, userId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<String> createThread({required String title, String? userId}) async {
    final id = uuid.v4();
    final now = _now;
    await _db.into(_db.chatThreads).insert(ChatThreadsCompanion.insert(
          id: id,
          userId: Value(userId),
          title: _clampTitle(title),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> renameThread(String id, String title) async {
    await (_db.update(_db.chatThreads)..where((t) => t.id.equals(id)))
        .write(ChatThreadsCompanion(title: Value(_clampTitle(title))));
  }

  /// Append a turn and bump the thread's activity, atomically.
  Future<String> appendMessage({
    required String threadId,
    required String role, // 'user' | 'vita'
    required String content,
    bool synthetic = false,
  }) async {
    final id = uuid.v4();
    final now = _now;
    await _db.transaction(() async {
      await _db.into(_db.chatMessages).insert(ChatMessagesCompanion.insert(
            id: id,
            threadId: threadId,
            role: role,
            content: content,
            synthetic: Value(synthetic),
            createdAt: now,
          ));
      await (_db.update(_db.chatThreads)..where((t) => t.id.equals(threadId)))
          .write(ChatThreadsCompanion(updatedAt: Value(now)));
    });
    return id;
  }

  /// Delete a thread and its messages together — no orphaned transcript.
  Future<void> deleteThread(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.chatMessages)..where((m) => m.threadId.equals(id)))
          .go();
      await (_db.delete(_db.chatThreads)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Clear every conversation for this device. Used on a CONFIRMED identity
  /// change (docs/architecture/06 §2a) — never before one, because local-only
  /// data has no server copy to recover from.
  Future<void> deleteAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.chatMessages).go();
      await _db.delete(_db.chatThreads).go();
    });
  }

  /// Adopt pre-auth (null `user_id`) threads once a session resolves, so a
  /// conversation started before sign-in is not stranded invisible forever.
  Future<void> adoptOrphanThreads(String userId) async {
    await (_db.update(_db.chatThreads)..where((t) => t.userId.isNull()))
        .write(ChatThreadsCompanion(userId: Value(userId)));
  }

  /// Strict ownership: current uid only. Null `user_id` matches nobody once a
  /// session exists; with no session, only the pre-auth (null) rows are visible.
  Expression<bool> _ownedBy($ChatThreadsTable t, String? userId) =>
      userId == null ? t.userId.isNull() : t.userId.equals(userId);

  /// Titles are derived from a user's first message — keep them short enough to
  /// render in a list row without truncation surprises.
  static String _clampTitle(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'New chat';
    return t.length <= 40 ? t : '${t.substring(0, 39)}…';
  }
}
