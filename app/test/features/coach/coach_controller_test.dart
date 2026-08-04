import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import '../../helpers/fake_byok.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/coach/data/vita_service.dart';
import 'package:sakama/features/coach/domain/coach_message.dart';
import 'package:sakama/features/coach/presentation/coach_controller.dart';

class _FakeVita implements VitaService {
  _FakeVita(this._reply);
  final Object _reply; // String reply or VitaException to throw
  String? lastContext;
  List<CoachMessage>? lastHistory;
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    lastContext = context;
    lastHistory = history;
    if (_reply is VitaException) throw _reply;
    return VitaReply(text: _reply as String);
  }
}

/// Throws on the first call, returns [_ok] after.
class _SwapVita implements VitaService {
  _SwapVita(this._first, this._ok);
  final VitaException _first;
  final String _ok;
  int _n = 0;
  List<CoachMessage>? lastHistory;
  @override
  Future<VitaReply> reply(List<CoachMessage> history,
      {required String context, String? byok}) async {
    lastHistory = history;
    if (_n++ == 0) throw _first;
    return VitaReply(text: _ok);
  }
}

ProviderContainer _c(VitaService vita, SakamaDatabase db) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      vitaServiceProvider.overrideWithValue(vita),
    ]);

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('send appends user turn then the grounded reply', () async {
    final vita = _FakeVita('A katori of dal would help.');
    final c = _c(vita, db);
    addTearDown(c.dispose);
    await c.read(coachControllerProvider.notifier).send('how is my protein?');
    final msgs = c.read(coachControllerProvider).messages;
    expect(msgs.map((m) => m.role), [CoachRole.user, CoachRole.vita]);
    expect(msgs.last.content, 'A katori of dal would help.');
    expect(c.read(coachControllerProvider).sending, isFalse);
    // The service received a grounding snapshot (no profile/logs here -> the
    // "nothing logged" shape), proving context is assembled + passed.
    expect(vita.lastContext, contains('Nothing logged yet today'));
    expect(vita.lastHistory!.last.content, 'how is my protein?');
  });

  test('empty / whitespace input is ignored', () async {
    final vita = _FakeVita('x');
    final c = _c(vita, db);
    addTearDown(c.dispose);
    await c.read(coachControllerProvider.notifier).send('   ');
    expect(c.read(coachControllerProvider).messages, isEmpty);
  });

  test('budget-exhausted surfaces as a friendly assistant message, thread '
      'stays readable', () async {
    final vita = _FakeVita(VitaException('x', budgetExhausted: true));
    final c = _c(vita, db);
    addTearDown(c.dispose);
    await c.read(coachControllerProvider.notifier).send('hi');
    final msgs = c.read(coachControllerProvider).messages;
    expect(msgs.map((m) => m.role), [CoachRole.user, CoachRole.vita]);
    expect(msgs.last.content, contains('reset tomorrow'));
    expect(c.read(coachControllerProvider).sending, isFalse);
  });

  test('synthetic error/budget messages are NOT replayed to the model (#58)',
      () async {
    final failThenOk = _SwapVita(
        VitaException('boom'), 'Here to help.');
    final c = _c(failThenOk, db);
    addTearDown(c.dispose);
    final ctl = c.read(coachControllerProvider.notifier);
    await ctl.send('hi');            // -> user 'hi' + synthetic error
    await ctl.send('you there?');    // -> should NOT send the synthetic turn
    final wire = failThenOk.lastHistory!;
    expect(wire.any((m) => m.content.contains("couldn't reach")), isFalse,
        reason: 'app chrome must not be replayed as a model turn');
    expect(wire.map((m) => m.content), ['hi', 'you there?']);
  });

  test('network error surfaces as a message, not a stuck sending state',
      () async {
    final vita = _FakeVita(VitaException('boom'));
    final c = _c(vita, db);
    addTearDown(c.dispose);
    await c.read(coachControllerProvider.notifier).send('hi');
    expect(c.read(coachControllerProvider).sending, isFalse);
    expect(c.read(coachControllerProvider).messages.last.role, CoachRole.vita);
  });
}
