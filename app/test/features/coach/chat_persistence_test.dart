import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/coach/data/chat_repository.dart';
import 'package:sakama/features/coach/data/vita_service.dart';
import 'package:sakama/features/coach/domain/coach_message.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';

import '../../helpers/fake_byok.dart';

class _FakeVita implements VitaService {
  _FakeVita(this._reply);
  final Object _reply; // a String to return, or a VitaException to throw
  List<CoachMessage>? lastHistory;
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    lastHistory = history;
    if (_reply is VitaException) throw _reply;
    return VitaReply(text: _reply as String);
  }
}

ProviderContainer _container(SakamaDatabase db, VitaService vita,
        {String? uid}) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      vitaServiceProvider.overrideWithValue(vita),
      currentUserIdProvider.overrideWithValue(uid),
    ]);

/// Pump microtasks/timers until [check] passes or we give up.
Future<void> _until(bool Function() check, {int tries = 60}) async {
  for (var i = 0; i < tries && !check(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late SakamaDatabase db;

  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a sent turn and its reply are persisted', () async {
    final c = _container(db, _FakeVita('eat more protein'), uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).send('what should I eat?');

    final rows = await ChatRepository(db).watchThreads('u1').first;
    expect(rows.length, 1, reason: 'the first message creates a thread');
    expect(rows.single.title, 'what should I eat?',
        reason: 'title is derived free from the first user message');

    final msgs = await ChatRepository(db).messagesOf(rows.single.id);
    expect(msgs.map((m) => m.content),
        ['what should I eat?', 'eat more protein']);
  });

  test('THE REGRESSION: the transcript survives a fresh controller', () async {
    final c1 = _container(db, _FakeVita('hello'), uid: 'u1');
    c1.listen(coachControllerProvider, (_, _) {});
    await c1.read(coachControllerProvider.notifier).send('hi');
    c1.dispose();

    // A new container == a fresh app launch. Before persistence this was empty.
    final c2 = _container(db, _FakeVita('unused'), uid: 'u1');
    addTearDown(c2.dispose);
    c2.listen(coachControllerProvider, (_, _) {});
    await _until(() => c2.read(coachControllerProvider).messages.isNotEmpty);

    final restored = c2.read(coachControllerProvider);
    expect(restored.messages.map((m) => m.content), ['hi', 'hello']);
    expect(restored.threadId, isNotNull);
  });

  test('a failed reply still keeps the user turn (nothing typed is lost)',
      () async {
    final c = _container(
        db, _FakeVita(VitaException('nope', budgetExhausted: true)),
        uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).send('remember this');

    final threads = await ChatRepository(db).watchThreads('u1').first;
    final msgs = await ChatRepository(db).messagesOf(threads.single.id);
    expect(msgs.first.content, 'remember this');
    expect(msgs.first.synthetic, isFalse);
    // The budget notice is stored but flagged, so it is never replayed upstream.
    expect(msgs.last.synthetic, isTrue);
  });

  test('newThread starts an empty chat and keeps the old one saved', () async {
    final c = _container(db, _FakeVita('ok'), uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).send('first chat');
    c.read(coachControllerProvider.notifier).newThread();
    expect(c.read(coachControllerProvider).messages, isEmpty);
    expect(c.read(coachControllerProvider).threadId, isNull);

    await c.read(coachControllerProvider.notifier).send('second chat');
    final threads = await ChatRepository(db).watchThreads('u1').first;
    expect(threads.length, 2, reason: 'the first conversation is still saved');
    expect(threads.first.title, 'second chat', reason: 'most recent first');
  });

  test('openThread switches the visible transcript', () async {
    final repo = ChatRepository(db);
    final old = await repo.createThread(title: 'Old', userId: 'u1');
    await repo.appendMessage(
        threadId: old, role: 'user', content: 'older question');

    final c = _container(db, _FakeVita('ok'), uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).openThread(old);

    expect(c.read(coachControllerProvider).messages.map((m) => m.content),
        ['older question']);
  });

  test('only the last historyWindow real turns are replayed upstream',
      () async {
    final repo = ChatRepository(db);
    final t = await repo.createThread(title: 'Long', userId: 'u1');
    // 30 prior real turns — more than the window.
    for (var i = 0; i < 30; i++) {
      await repo.appendMessage(
          threadId: t, role: i.isEven ? 'user' : 'vita', content: 'm$i');
    }
    final vita = _FakeVita('ok');
    final c = _container(db, vita, uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).openThread(t);
    await c.read(coachControllerProvider.notifier).send('newest');

    expect(vita.lastHistory!.length, CoachController.historyWindow,
        reason: 'an unbounded transcript would grow cost every turn (rule 9)');
    expect(vita.lastHistory!.last.content, 'newest');
  });

  test('deleting the open thread falls back to the next saved one', () async {
    final c = _container(db, _FakeVita('ok'), uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('first');
    c.read(coachControllerProvider.notifier).newThread();
    await c.read(coachControllerProvider.notifier).send('second');

    final open = c.read(coachControllerProvider).threadId!;
    await c.read(coachControllerProvider.notifier).deleteThread(open);
    await _until(() => c.read(coachControllerProvider).messages.isNotEmpty);

    expect(c.read(coachControllerProvider).messages.first.content, 'first',
        reason: 'deleting the visible chat should not leave a dead screen');
  });

  test('pre-auth threads are adopted once a session resolves (review #83)',
      () async {
    // A conversation born before sign-in: null user_id.
    final repo = ChatRepository(db);
    final t = await repo.createThread(title: 'anon chat', userId: null);
    await repo.appendMessage(threadId: t, role: 'user', content: 'pre-auth');

    // The controller now builds WITH a session — restore must adopt it.
    final c = _container(db, _FakeVita('ok'), uid: 'u1');
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await _until(() => c.read(coachControllerProvider).messages.isNotEmpty);

    expect(c.read(coachControllerProvider).messages.first.content, 'pre-auth',
        reason: 'a pre-auth conversation must not strand invisible');
    expect((await repo.watchThreads('u1').first).length, 1);
  });
}
