import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/domain/snapped_item.dart';
import 'package:sakama/features/coach/data/vita_service.dart';
import 'package:sakama/features/coach/domain/coach_message.dart';
import 'package:sakama/features/coach/domain/tool_draft.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';

import '../../helpers/fake_byok.dart';

/// Replays the reported device sequence: PhotoSnap finds 4 items -> "Ask Vita"
/// -> "i have just ate this". Before the fix, the handoff sent only
/// "name (~kcal)", so ONE dish was proposed with ZERO macros.
class _ScriptedVita implements VitaService {
  _ScriptedVita(this._replies);
  final List<VitaReply> _replies;
  int calls = 0;
  final sent = <String>[];
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    sent.add(history.last.content);
    return _replies[calls++ % _replies.length];
  }
}

SnappedItem _i(String name, double kcal, double p, double c, double f, double g) =>
    SnappedItem(
        name: name, portionLabel: '1 serving', grams: g, energyKcal: kcal,
        proteinG: p, carbG: c, fatG: f, confidence: 0.7);

final _meal = [
  _i('Steamed Rice', 325, 7, 72, 1, 250),
  _i('Chole/Chana Masala', 250, 9, 35, 9, 180),
  _i('Cabbage Subzi', 100, 3, 15, 4, 150),
  _i('Palak/Spinach Subzi', 70, 3, 8, 3, 100),
];

const _logToolCall = '{"tool":"log_food","arguments":{"meal":"dinner",'
    '"name":"Chana Masala","energy_kcal":200}}';

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer c(VitaService v) => ProviderContainer(overrides: [
        databaseProvider.overrideWith((ref) async => db),
        byokStoreProvider.overrideWithValue(FakeByokStore()),
        currentUserIdProvider.overrideWithValue('u1'),
        vitaServiceProvider.overrideWithValue(v),
      ]);

  test('the handoff carries macros into the question', () async {
    final vita = _ScriptedVita([const VitaReply(text: 'Looks good.')]);
    final ct = c(vita);
    addTearDown(ct.dispose);
    ct.listen(coachControllerProvider, (_, _) {});

    await ct.read(coachControllerProvider.notifier).handoffFromPhotoSnap(_meal);

    expect(vita.sent.single, contains('P7/C72/F1'),
        reason: 'macros must reach Vita, not just calories');
  });

  test('"I just ate this" proposes the WHOLE meal with real macros', () async {
    final vita = _ScriptedVita([
      const VitaReply(text: 'Looks good.'),
      const VitaReply(text: '', toolJson: _logToolCall),
    ]);
    final ct = c(vita);
    addTearDown(ct.dispose);
    ct.listen(coachControllerProvider, (_, _) {});

    await ct.read(coachControllerProvider.notifier).handoffFromPhotoSnap(_meal);
    await ct.read(coachControllerProvider.notifier).send('i have just ate this');

    final drafts = ct.read(coachControllerProvider).pendingDrafts;
    expect(drafts.length, 4,
        reason: 'the reported bug proposed only 1 of 4 dishes');
    final rice = drafts
        .cast<LogFoodDraft>()
        .firstWhere((d) => d.name == 'Steamed Rice');
    expect(rice.carbG, 72, reason: 'macros were dropped before the fix');
    expect(rice.grams, 250);
  });

  test('confirming writes all four rows with their macros', () async {
    final vita = _ScriptedVita([
      const VitaReply(text: 'Looks good.'),
      const VitaReply(text: '', toolJson: _logToolCall),
    ]);
    final ct = c(vita);
    addTearDown(ct.dispose);
    ct.listen(coachControllerProvider, (_, _) {});

    await ct.read(coachControllerProvider.notifier).handoffFromPhotoSnap(_meal);
    await ct.read(coachControllerProvider.notifier).send('i have just ate this');
    await ct.read(coachControllerProvider.notifier).confirmDraft();

    final rows = await db.select(db.foodLogs).get();
    expect(rows.length, 4);
    expect(rows.map((r) => r.energyKcal).reduce((a, b) => a + b), 745,
        reason: 'the whole 745 kcal meal, matching what PhotoSnap showed');
    expect(rows.every((r) => r.proteinG > 0), isTrue,
        reason: 'no more zero-macro rows');
  });

  test('carried items are consumed once, not re-proposed later', () async {
    final vita = _ScriptedVita([
      const VitaReply(text: 'Looks good.'),
      const VitaReply(text: '', toolJson: _logToolCall),
      const VitaReply(text: '', toolJson: _logToolCall),
    ]);
    final ct = c(vita);
    addTearDown(ct.dispose);
    ct.listen(coachControllerProvider, (_, _) {});

    await ct.read(coachControllerProvider.notifier).handoffFromPhotoSnap(_meal);
    await ct.read(coachControllerProvider.notifier).send('i have just ate this');
    await ct.read(coachControllerProvider.notifier).confirmDraft();
    // A later, unrelated log must be just that one item.
    await ct.read(coachControllerProvider.notifier).send('also had a banana');

    expect(ct.read(coachControllerProvider).pendingDrafts.length, 1,
        reason: 'the meal was already logged; do not re-propose it');
  });
}
