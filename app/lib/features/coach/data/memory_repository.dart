import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../../../core/db/database.dart';

/// What Vita has learned about you (ADR 0016 phase 4).
///
/// Device-local, like the conversations it derives from: `memory_facts` is
/// `Table.localOnly`, so nothing here syncs, has an RLS policy, or reaches a
/// server. That is what lets the app say plainly that what Vita remembers
/// never leaves the phone at rest.
///
/// SCOPING follows [ChatRepository] exactly, and for the same reason: a
/// local-only row never uploads, so Postgres never backfills a null `user_id`
/// the way it does for synced tables. A null owner therefore matches only
/// pre-auth rows and NEVER "everybody".
class MemoryRepository {
  MemoryRepository(this._db, {DateTime Function()? now})
      : _clock = now ?? DateTime.now;
  final SakamaDatabase _db;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  /// The closed vocabulary of decision 4, in PRIORITY order — a constraint
  /// ("lactose intolerant") must reach the model ahead of an observation
  /// ("ate late on Tuesday") when the prompt budget is tight. Ordering these
  /// by importance here, rather than at each call site, keeps that judgement
  /// in one place.
  static const kinds = <String>[
    'constraint',
    'goal',
    'routine',
    'preference',
    'observation',
  ];

  static bool isValidKind(String k) => kinds.contains(k);

  /// Facts for [userId], most useful first: kind priority, then confidence,
  /// then recency. Deterministic tiebreak on id so a tie cannot reorder
  /// between reads and make the UI jitter.
  Stream<List<MemoryFact>> watchAll(String? userId) =>
      (_db.select(_db.memoryFacts)..where((t) => _ownedBy(t, userId)))
          .watch()
          .map((rows) => rows.toList()..sort(_byUsefulness));

  Future<List<MemoryFact>> all(String? userId) =>
      watchAll(userId).first;

  /// The top [limit] facts to ground a reply. Kept small on purpose: the
  /// prompt budget is shared with the day's logs, the plan and the transcript,
  /// and a long memory list would crowd out the data the user can actually see.
  Future<List<MemoryFact>> topFor(String? userId, {int limit = 12}) async {
    final rows = await all(userId);
    return rows.take(limit).toList();
  }

  /// Store a newly extracted fact.
  ///
  /// DEDUPES on normalised content within the same kind, updating confidence
  /// and recency instead of inserting a near-duplicate. Without this, every
  /// extraction pass would re-learn "prefers home-cooked food" and the memory
  /// list would fill with the same sentence — the failure mode that makes a
  /// memory feature feel broken rather than smart.
  Future<String> remember({
    required String kind,
    required String content,
    double confidence = 0.5,
    String? sourceThreadId,
    String? userId,
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be empty');
    }
    if (!isValidKind(kind)) {
      throw ArgumentError.value(kind, 'kind', 'must be one of $kinds');
    }

    final existing = (await all(userId)).where(
        (f) => f.kind == kind && _normalise(f.content) == _normalise(text));
    if (existing.isNotEmpty) {
      final row = existing.first;
      await (_db.update(_db.memoryFacts)..where((t) => t.id.equals(row.id)))
          .write(MemoryFactsCompanion(
        // Keep the HIGHER confidence: hearing something a second time is
        // evidence for it, never against.
        confidence: Value(confidence > row.confidence ? confidence : row.confidence),
        sourceThreadId: Value(sourceThreadId ?? row.sourceThreadId),
        updatedAt: Value(_now),
      ));
      return row.id;
    }

    final id = uuid.v4();
    await _db.into(_db.memoryFacts).insert(MemoryFactsCompanion.insert(
          id: id,
          userId: Value(userId),
          kind: kind,
          content: text,
          confidence: Value(confidence.clamp(0.0, 1.0)),
          sourceThreadId: Value(sourceThreadId),
          createdAt: _now,
          updatedAt: _now,
        ));
    return id;
  }

  /// Forget one fact. This is the ONLY correction mechanism (decision 10):
  /// there is deliberately no edit, because a user-rewritten fact and an
  /// extracted one would be indistinguishable downstream, and the provenance
  /// in `source_thread_id` would become a lie.
  Future<void> forget(String id) =>
      (_db.delete(_db.memoryFacts)..where((t) => t.id.equals(id))).go();

  /// Forget everything for one user — the reset the user asked for by name.
  /// Returns how many facts were removed, so the UI can confirm concretely
  /// ("Forgot 23 things") rather than with a silent no-op the user cannot
  /// distinguish from a failure.
  Future<int> forgetAll(String? userId) =>
      (_db.delete(_db.memoryFacts)..where((t) => _ownedBy(t, userId))).go();

  /// Adopt pre-auth facts once a session resolves, mirroring
  /// [ChatRepository.adoptOrphanThreads]. Without this, everything Vita learned
  /// before the first sign-in would be stranded and invisible forever.
  Future<int> adoptOrphans(String userId) =>
      (_db.update(_db.memoryFacts)..where((t) => t.userId.isNull()))
          .write(MemoryFactsCompanion(userId: Value(userId)));

  /// Most useful first. Kind priority dominates, because a dietary constraint
  /// being crowded out by a high-confidence observation would be a safety
  /// problem, not merely a ranking one.
  static int _byUsefulness(MemoryFact a, MemoryFact b) {
    final ka = kinds.indexOf(a.kind);
    final kb = kinds.indexOf(b.kind);
    // An unknown kind sorts last rather than first: indexOf returns -1, which
    // would otherwise beat every valid kind.
    final pa = ka < 0 ? kinds.length : ka;
    final pb = kb < 0 ? kinds.length : kb;
    if (pa != pb) return pa.compareTo(pb);
    if (a.confidence != b.confidence) return b.confidence.compareTo(a.confidence);
    if (a.updatedAt != b.updatedAt) return b.updatedAt.compareTo(a.updatedAt);
    return a.id.compareTo(b.id);
  }

  static String _normalise(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9 ]'), '')
          .replaceAll(RegExp(r'\s+'), ' ');

  Expression<bool> _ownedBy($MemoryFactsTable t, String? userId) =>
      userId == null ? t.userId.isNull() : t.userId.equals(userId);
}
