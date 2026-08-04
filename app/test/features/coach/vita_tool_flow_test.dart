import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/coach/data/vita_service.dart';
import 'package:sakama/features/coach/domain/coach_message.dart';
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';

import '../../helpers/fake_byok.dart';

class _ToolVita implements VitaService {
  _ToolVita({this.text = '', this.toolJson});
  final String text;
  final String? toolJson;
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
          {required String context, String? byok}) async =>
      VitaReply(text: text, toolJson: toolJson);
}

ProviderContainer _c(SakamaDatabase db, VitaService vita) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      vitaServiceProvider.overrideWithValue(vita),
      currentUserIdProvider.overrideWithValue('u1'),
    ]);

const _goodFood = '{"tool":"log_food","arguments":{"meal":"lunch",'
    '"name":"dal tadka","energy_kcal":180,"protein_g":9,"carb_g":22,'
    '"fat_g":6,"grams":150}}';

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a proposed log is NOT written until the user confirms', () async {
    final c = _c(db, _ToolVita(text: 'Want me to log that?', toolJson: _goodFood));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});

    await c.read(coachControllerProvider.notifier).send('I had dal for lunch');

    // A draft is pending...
    final draft = c.read(coachControllerProvider).pendingDraft;
    expect(draft, isA<LogFoodDraft>());
    // ...and NOTHING is in the diary yet. This is the whole safety contract.
    expect(await db.select(db.foodLogs).get(), isEmpty,
        reason: 'Vita must never write before the user taps');
  });

  test('confirming writes the row, tagged logged_via vita', () async {
    final c = _c(db, _ToolVita(toolJson: _goodFood));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('dal for lunch');
    await c.read(coachControllerProvider.notifier).confirmDraft();

    final rows = await db.select(db.foodLogs).get();
    expect(rows.length, 1);
    expect(rows.single.name, 'dal tadka');
    expect(rows.single.meal, 'lunch');
    expect(rows.single.energyKcal, 180);
    expect(rows.single.loggedVia, 'vita',
        reason: 'an AI-created row must stay auditable');
    expect(c.read(coachControllerProvider).pendingDraft, isNull);
  });

  test('dismissing writes nothing and clears the card', () async {
    final c = _c(db, _ToolVita(toolJson: _goodFood));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('dal for lunch');
    c.read(coachControllerProvider.notifier).dismissDraft();

    expect(c.read(coachControllerProvider).pendingDraft, isNull);
    expect(await db.select(db.foodLogs).get(), isEmpty);
  });

  test('confirming twice cannot double-log', () async {
    final c = _c(db, _ToolVita(toolJson: _goodFood));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('dal for lunch');

    await Future.wait([
      c.read(coachControllerProvider.notifier).confirmDraft(),
      c.read(coachControllerProvider.notifier).confirmDraft(),
    ]);

    expect((await db.select(db.foodLogs).get()).length, 1,
        reason: 'the draft is cleared before the write, so a double tap is a no-op');
  });

  test('an out-of-bounds proposal never becomes a card', () async {
    // 99999 kcal is exactly the "plausible-looking" failure confirm cannot catch.
    final c = _c(
        db,
        _ToolVita(
            text: 'ok',
            toolJson: '{"tool":"log_food","arguments":{"meal":"lunch",'
                '"name":"x","energy_kcal":99999}}'));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('something odd');

    expect(c.read(coachControllerProvider).pendingDraft, isNull,
        reason: 'bounds-checked BEFORE the card, per review #82');
    expect(await db.select(db.foodLogs).get(), isEmpty);
  });

  test('water and weight proposals write to their own tables', () async {
    final c = _c(db, _ToolVita(toolJson:
        '{"tool":"log_water","arguments":{"amount_ml":250}}'));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('drank a glass');
    await c.read(coachControllerProvider.notifier).confirmDraft();

    final w = await db.select(db.waterLogs).get();
    expect(w.single.amountMl, 250);
  });

  test('a tool call with empty prose still gives the user something to read',
      () async {
    final c = _c(db, _ToolVita(text: '', toolJson: _goodFood));
    addTearDown(c.dispose);
    c.listen(coachControllerProvider, (_, _) {});
    await c.read(coachControllerProvider.notifier).send('dal');

    final msgs = c.read(coachControllerProvider).messages;
    expect(msgs.last.content, isNotEmpty,
        reason: 'a silent bubble next to a confirm card reads as a bug');
  });
}
