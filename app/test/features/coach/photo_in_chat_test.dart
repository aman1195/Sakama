import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/data/photosnap_service.dart';
import 'package:sakama/features/capture/domain/snapped_item.dart';
import 'package:sakama/features/coach/data/chat_repository.dart';
import 'package:sakama/features/coach/data/vita_service.dart';
import 'package:sakama/features/coach/domain/coach_message.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';

import '../../helpers/fake_byok.dart';

class _FakeVision implements PhotoSnapService {
  _FakeVision({this.result, this.error});
  final VisionConversation? result;
  final Object? error;
  int converseCalls = 0;
  String? lastQuestion;

  @override
  Future<List<SnappedItem>> analyze(String i, {String? byok}) async =>
      throw UnimplementedError();

  @override
  Future<VisionConversation> converse(String image,
      {String? question, required String context, String? byok}) async {
    converseCalls++;
    lastQuestion = question;
    if (error != null) throw error!;
    return result!;
  }
}

class _FakeVita implements VitaService {
  _FakeVita(this._text);
  final String _text;
  List<CoachMessage>? lastHistory;
  int calls = 0;
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    calls++;
    lastHistory = history;
    return VitaReply(text: _text);
  }
}

ProviderContainer _c(SakamaDatabase db,
        {PhotoSnapService? vision, VitaService? vita}) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      currentUserIdProvider.overrideWithValue('u1'),
      if (vision != null) photoSnapServiceProvider.overrideWithValue(vision),
      vitaServiceProvider.overrideWithValue(vita ?? _FakeVita('ok')),
    ]);

const _vision = VisionConversation(
  answer: 'Looks balanced, though the sabzi looks oily.',
  description: 'two rotis, dal tadka, cucumber salad',
);

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the description replaces [photo] in the stored message', () async {
    final c = _c(db, vision: _FakeVision(result: _vision));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c
        .read(coachControllerProvider.notifier)
        .sendPhoto(imageBase64: 'AAAA', caption: 'is this too oily?');

    final threads = await ChatRepository(db).watchThreads('u1').first;
    final msgs = await ChatRepository(db).messagesOf(threads.single.id);
    expect(msgs.first.content,
        '[photo: two rotis, dal tadka, cucumber salad] is this too oily?',
        reason: 'the photo is never stored, so the description stands in for it');
    expect(msgs.last.content, contains('oily'));
  });

  test('the description is replayed upstream on the NEXT turn', () async {
    final vita = _FakeVita('sure');
    final c = _c(db, vision: _FakeVision(result: _vision), vita: vita);
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).sendPhoto(imageBase64: 'AAAA');
    await c.read(coachControllerProvider.notifier).send('what about the rice?');

    final wire = vita.lastHistory!.map((m) => m.content).join(' | ');
    expect(wire, contains('two rotis, dal tadka'),
        reason: 'follow-ups stay grounded without re-sending the image');
  });

  test('no caption still asks a sensible default question', () async {
    final vision = _FakeVision(result: _vision);
    final c = _c(db, vision: vision);
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).sendPhoto(imageBase64: 'AAAA');
    expect(vision.lastQuestion, isNull,
        reason: 'the function supplies the default so the prompt owns it');
  });

  test('out of PHOTOS says you can still chat (review #94)', () async {
    final c = _c(
        db,
        vision: _FakeVision(
            error: PhotoSnapException('cap',
                budgetExhausted: true, budgetKind: 'photo')));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).sendPhoto(imageBase64: 'AAAA');

    final last = c.read(coachControllerProvider).messages.last;
    expect(last.content, contains('still chat'),
        reason: 'the scarce-first order preserved the vita budget — say so');
    expect(last.synthetic, isTrue);
  });

  test('out of EXCHANGES words it differently', () async {
    final c = _c(
        db,
        vision: _FakeVision(
            error: PhotoSnapException('cap',
                budgetExhausted: true, budgetKind: 'exchange')));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).sendPhoto(imageBase64: 'AAAA');
    expect(c.read(coachControllerProvider).messages.last.content,
        contains('reset tomorrow'));
  });

  test('a non-plated image still yields an answer (items empty)', () async {
    final c = _c(
        db,
        vision: _FakeVision(
            result: const VisionConversation(
                answer: 'That packet is mostly refined flour — I would skip it.',
                description: 'a packet of fried namkeen')));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c
        .read(coachControllerProvider.notifier)
        .sendPhoto(imageBase64: 'AAAA', caption: 'can I eat this?');

    expect(c.read(coachControllerProvider).messages.last.content,
        contains('skip it'));
    // Nothing is logged: photo conversations never auto-log (design §6).
    expect(await db.select(db.foodLogs).get(), isEmpty);
  });

  test('a photo conversation NEVER auto-logs', () async {
    final c = _c(
        db,
        vision: _FakeVision(
            result: VisionConversation(
                answer: 'Nice plate.',
                description: 'dal and rice',
                items: [
                  SnappedItem(
                      name: 'dal tadka',
                      portionLabel: '1 katori',
                      grams: 150,
                      energyKcal: 180,
                      proteinG: 9,
                      carbG: 22,
                      fatG: 6,
                      confidence: 0.7),
                ])));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).sendPhoto(imageBase64: 'AAAA');

    expect(await db.select(db.foodLogs).get(), isEmpty,
        reason: '"should I eat this?" precedes the meal — logging is explicit');
    expect(c.read(coachControllerProvider).pendingDraft, isNull);
  });
}
