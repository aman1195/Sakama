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
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';
import 'package:sakama/features/home/domain/day_totals.dart' show Meal;

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

  group('the model judges whether a save is wanted', () {
    // A photo alone is NOT an intent to log; a clear "I ate this" should not
    // need repeating. Both are the model's call, surfaced as logIntent.
    VisionConversation withIntent({required bool intent, String? meal}) =>
        VisionConversation(
          answer: 'Looks good.',
          description: 'poha, dal, two rotis',
          logIntent: intent,
          meal: meal,
          items: [
            SnappedItem(
                name: 'poha',
                portionLabel: '1 bowl',
                grams: 180,
                energyKcal: 260,
                proteinG: 5,
                carbG: 45,
                fatG: 6,
                confidence: 0.7),
            SnappedItem(
                name: 'dal tadka',
                portionLabel: '1 katori',
                grams: 150,
                energyKcal: 150,
                proteinG: 9,
                carbG: 18,
                fatG: 5,
                confidence: 0.7),
          ],
        );

    test('asking about a photo proposes NOTHING', () async {
      final c = _c(db, vision: _FakeVision(result: withIntent(intent: false)));
      addTearDown(c.dispose);
      c.listen(coachControllerProvider, (_, _) {});

      await c
          .read(coachControllerProvider.notifier)
          .sendPhoto(imageBase64: 'AAAA', caption: 'should I eat this?');

      expect(c.read(coachControllerProvider).pendingDrafts, isEmpty,
          reason: 'a question is not a request to save');
    });

    test('saying you ate it proposes EVERY item, in one card', () async {
      final c = _c(
          db,
          vision: _FakeVision(result: withIntent(intent: true, meal: 'lunch')));
      addTearDown(c.dispose);
      c.listen(coachControllerProvider, (_, _) {});

      await c
          .read(coachControllerProvider.notifier)
          .sendPhoto(imageBase64: 'AAAA', caption: 'I had this for lunch');

      final drafts = c.read(coachControllerProvider).pendingDrafts;
      expect(drafts.length, 2, reason: 'a thali is several foods, not one');
      expect((drafts.first as LogFoodDraft).meal, Meal.lunch);
      // Still nothing written until the tap — the contract is unchanged.
      expect(await db.select(db.foodLogs).get(), isEmpty);
    });

    test('confirming logs all of them', () async {
      final c = _c(
          db,
          vision: _FakeVision(result: withIntent(intent: true, meal: 'dinner')));
      addTearDown(c.dispose);
      c.listen(coachControllerProvider, (_, _) {});

      await c
          .read(coachControllerProvider.notifier)
          .sendPhoto(imageBase64: 'AAAA', caption: 'just finished this');
      await c.read(coachControllerProvider.notifier).confirmDraft();

      final rows = await db.select(db.foodLogs).get();
      expect(rows.length, 2);
      expect(rows.every((r) => r.meal == 'dinner'), isTrue);
      expect(rows.every((r) => r.loggedVia == 'vita'), isTrue);
    });

    test('intent WITHOUT loggable items (a menu photo) proposes nothing',
        () async {
      final c = _c(
          db,
          vision: _FakeVision(
              result: const VisionConversation(
                  answer: 'That menu has little for you.',
                  description: 'a restaurant menu',
                  logIntent: true))); // nothing plated to save
      addTearDown(c.dispose);
      c.listen(coachControllerProvider, (_, _) {});

      await c
          .read(coachControllerProvider.notifier)
          .sendPhoto(imageBase64: 'AAAA', caption: 'log this');

      expect(c.read(coachControllerProvider).pendingDrafts, isEmpty);
    });
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
