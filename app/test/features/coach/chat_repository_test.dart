import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/features/coach/data/chat_repository.dart';

void main() {
  late SakamaDatabase db;
  late ChatRepository repo;

  setUp(() {
    db = SakamaDatabase.withExecutor(NativeDatabase.memory());
    repo = ChatRepository(db);
  });
  tearDown(() => db.close());

  test('a thread persists with its transcript in order', () async {
    final t = await repo.createThread(title: 'Knee injury', userId: 'u1');
    await repo.appendMessage(threadId: t, role: 'user', content: 'first');
    await repo.appendMessage(threadId: t, role: 'vita', content: 'second');

    final msgs = await repo.messagesOf(t);
    expect(msgs.map((m) => m.content), ['first', 'second']);
    expect(msgs.map((m) => m.role), ['user', 'vita']);
  });

  test('appending bumps the thread so the list sorts by recent activity',
      () async {
    // Explicit advancing clock: real wall-clock can put all three writes in the
    // same millisecond, where "most recent" is genuinely undefined.
    var t0 = DateTime(2026, 8, 4, 9);
    repo = ChatRepository(db, now: () => t0 = t0.add(const Duration(minutes: 1)));
    final a = await repo.createThread(title: 'A', userId: 'u1');
    final b = await repo.createThread(title: 'B', userId: 'u1');
    // Touch A last; it must lead the list even though B was created later.
    await repo.appendMessage(threadId: a, role: 'user', content: 'hi');

    final threads = await repo.watchThreads('u1').first;
    expect(threads.first.id, a);
    expect(threads.map((t) => t.id), containsAll([a, b]));
  });

  test('deleting a thread removes its messages — no orphans', () async {
    final t = await repo.createThread(title: 'Temp', userId: 'u1');
    await repo.appendMessage(threadId: t, role: 'user', content: 'x');
    await repo.deleteThread(t);

    expect(await repo.watchThreads('u1').first, isEmpty);
    expect(await db.select(db.chatMessages).get(), isEmpty,
        reason: 'messages must not outlive their thread');
  });

  group('isolation (docs/architecture/06 §2)', () {
    test('user B never sees user A\'s threads', () async {
      await repo.createThread(title: 'A private', userId: 'userA');
      final forB = await repo.watchThreads('userB').first;
      expect(forB, isEmpty);
    });

    test('a null-user_id thread is invisible to a signed-in user', () async {
      await repo.createThread(title: 'pre-auth', userId: null);
      expect(await repo.watchThreads('userA').first, isEmpty,
          reason: 'null must match NOBODY, never "everybody"');
      // ...but is visible pre-session, so it is not lost.
      expect((await repo.watchThreads(null).first).length, 1);
    });

    test('adoptOrphanThreads hands pre-auth threads to the resolved session',
        () async {
      await repo.createThread(title: 'pre-auth', userId: null);
      await repo.adoptOrphanThreads('userA');

      expect((await repo.watchThreads('userA').first).length, 1,
          reason: 'a pre-auth conversation is adopted, not stranded');
      expect(await repo.watchThreads(null).first, isEmpty);
    });

    test('deleteAll clears every conversation (confirmed identity change)',
        () async {
      final t = await repo.createThread(title: 'A', userId: 'userA');
      await repo.appendMessage(threadId: t, role: 'user', content: 'secret');
      await repo.deleteAll();

      expect(await db.select(db.chatThreads).get(), isEmpty);
      expect(await db.select(db.chatMessages).get(), isEmpty);
    });
  });

  group('titles', () {
    test('derived title is trimmed, collapsed and clamped', () async {
      final long = 'a' * 60;
      final t = await repo.createThread(title: '  what   should  I eat  ');
      final l = await repo.createThread(title: long);
      final rows = await repo.watchThreads(null).first;
      final byId = {for (final r in rows) r.id: r.title};

      expect(byId[t], 'what should I eat');
      expect(byId[l]!.length, 40);
      expect(byId[l], endsWith('…'));
    });

    test('an empty first message still yields a usable title', () async {
      final t = await repo.createThread(title: '   ');
      final rows = await repo.watchThreads(null).first;
      expect(rows.firstWhere((r) => r.id == t).title, 'New chat');
    });
  });

  test('synthetic turns are stored but flagged (never replayed upstream)',
      () async {
    final t = await repo.createThread(title: 'T');
    await repo.appendMessage(threadId: t, role: 'user', content: 'q');
    await repo.appendMessage(
        threadId: t, role: 'vita', content: 'budget notice', synthetic: true);

    final msgs = await repo.messagesOf(t);
    expect(msgs.where((m) => m.synthetic).map((m) => m.content),
        ['budget notice']);
    expect(msgs.where((m) => !m.synthetic).length, 1);
  });
}
