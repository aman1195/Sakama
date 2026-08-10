import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/coach/data/memory_repository.dart';

void main() {
  late SakamaDatabase db;
  late MemoryRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = MemoryRepository(db);
  });
  tearDown(() => db.close());

  test('a fact is stored with its kind, confidence and provenance', () async {
    final id = await repo.remember(
      kind: 'constraint',
      content: 'Lactose intolerant',
      confidence: 0.9,
      sourceThreadId: 't1',
    );
    final row = await (db.select(db.memoryFacts)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.kind, 'constraint');
    expect(row.content, 'Lactose intolerant');
    expect(row.confidence, 0.9);
    expect(row.sourceThreadId, 't1',
        reason: 'a wrong fact is only correctable if you can find where it '
            'came from');
  });

  group('ranking puts the most useful fact first', () {
    test('a constraint outranks a higher-confidence observation', () async {
      await repo.remember(
          kind: 'observation', content: 'Ate late on Tuesday', confidence: 1.0);
      await repo.remember(
          kind: 'constraint', content: 'Lactose intolerant', confidence: 0.3);

      final rows = await repo.all(null);
      expect(rows.first.kind, 'constraint',
          reason: 'a dietary constraint crowded out by trivia is a safety '
              'problem, not just a ranking one');
    });

    test('within a kind, confidence then recency decides', () async {
      await repo.remember(
          kind: 'preference', content: 'Likes paneer', confidence: 0.4);
      await repo.remember(
          kind: 'preference', content: 'Likes rajma', confidence: 0.9);
      final rows = await repo.all(null);
      expect(rows.first.content, 'Likes rajma');
    });

    test('an unknown kind sorts LAST, not first', () async {
      // indexOf returns -1 for an unknown kind, which would otherwise beat
      // every valid one and put junk at the top of the user's memory list.
      await repo.remember(kind: 'preference', content: 'Likes paneer');
      await db.into(db.memoryFacts).insert(MemoryFactsCompanion.insert(
            id: 'weird', kind: 'gibberish', content: 'x',
            createdAt: 1, updatedAt: 1,
          ));
      final rows = await repo.all(null);
      expect(rows.last.id, 'weird');
    });
  });

  group('re-learning does not duplicate', () {
    test('the same fact heard twice updates instead of inserting', () async {
      final a = await repo.remember(
          kind: 'preference', content: 'Prefers home-cooked food',
          confidence: 0.5);
      final b = await repo.remember(
          kind: 'preference', content: '  prefers home-cooked FOOD! ',
          confidence: 0.8, sourceThreadId: 't2');

      expect(b, a, reason: 'same fact, same row');
      final rows = await repo.all(null);
      expect(rows, hasLength(1),
          reason: 'a memory list that repeats itself feels broken, not smart');
      expect(rows.single.confidence, 0.8,
          reason: 'hearing it again is evidence FOR it');
      expect(rows.single.sourceThreadId, 't2');
    });

    test('confidence never drops on a re-hear', () async {
      await repo.remember(
          kind: 'goal', content: 'Wants to lose 5kg', confidence: 0.9);
      await repo.remember(
          kind: 'goal', content: 'Wants to lose 5kg', confidence: 0.2);
      expect((await repo.all(null)).single.confidence, 0.9);
    });

    test('the same words under a DIFFERENT kind are separate facts', () async {
      await repo.remember(kind: 'goal', content: 'No sugar');
      await repo.remember(kind: 'constraint', content: 'No sugar');
      expect(await repo.all(null), hasLength(2));
    });
  });

  group('the user stays in control', () {
    test('forget removes exactly one fact', () async {
      final a = await repo.remember(kind: 'preference', content: 'A');
      await repo.remember(kind: 'preference', content: 'B');
      await repo.forget(a);
      final rows = await repo.all(null);
      expect(rows.single.content, 'B');
    });

    test('reset reports HOW MANY it forgot', () async {
      await repo.remember(kind: 'preference', content: 'A', userId: 'u1');
      await repo.remember(kind: 'goal', content: 'B', userId: 'u1');
      // A silent no-op is indistinguishable from a failure, so the count is
      // what lets the UI confirm concretely.
      expect(await repo.forgetAll('u1'), 2);
      expect(await repo.all('u1'), isEmpty);
    });

    test('reset does not touch another user', () async {
      await repo.remember(kind: 'preference', content: 'mine', userId: 'a');
      await repo.remember(kind: 'preference', content: 'theirs', userId: 'b');
      await repo.forgetAll('a');
      expect((await repo.all('b')).single.content, 'theirs');
    });
  });

  group('ownership scoping matches the chat tables', () {
    test('a null owner matches only pre-auth rows, never everybody', () async {
      await repo.remember(kind: 'preference', content: 'mine', userId: 'u1');
      expect(await repo.all(null), isEmpty);
      expect(await repo.all('u2'), isEmpty);
    });

    test('pre-auth facts are adopted once a session resolves', () async {
      await repo.remember(kind: 'preference', content: 'learned offline');
      expect(await repo.adoptOrphans('u1'), 1);
      expect((await repo.all('u1')).single.content, 'learned offline');
    });
  });

  group('rejects what it cannot store honestly', () {
    test('an unknown kind is refused', () {
      expect(() => repo.remember(kind: 'vibes', content: 'x'),
          throwsArgumentError);
    });

    test('empty content is refused', () {
      expect(() => repo.remember(kind: 'goal', content: '   '),
          throwsArgumentError);
    });
  });

  test('topFor caps what reaches the prompt', () async {
    for (var i = 0; i < 20; i++) {
      await repo.remember(kind: 'observation', content: 'fact $i');
    }
    // The prompt budget is shared with logs, plan and transcript; an unbounded
    // memory list would crowd out data the user can actually see.
    expect(await repo.topFor(null, limit: 5), hasLength(5));
  });
}
