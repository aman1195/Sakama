import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import '../../helpers/fake_byok.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/capture/data/photosnap_service.dart';
import 'package:sakama/features/capture/domain/snap_draft.dart';
import 'package:sakama/features/capture/domain/snap_flow.dart';
import 'package:sakama/features/capture/domain/snapped_item.dart';
import 'package:flutter/services.dart';
import 'package:sakama/features/capture/presentation/snap_controller.dart';

class _FakeSnap implements PhotoSnapService {
  _FakeSnap(this._result);
  final Object _result; // List<SnappedItem> or a PhotoSnapException to throw
  int calls = 0;
  @override
  Future<List<SnappedItem>> analyze(String imageBytesBase64, {String? byok}) async {
    calls++;
    if (_result is PhotoSnapException) throw _result;
    return _result as List<SnappedItem>;
  }

  // Converse mode is exercised by vision_converse_test / the chat flow, not by
  // this snap-to-log path.
  @override
  Future<VisionConversation> converse(String imageBytesBase64,
          {String? question, required String context, String? byok}) async =>
      throw UnimplementedError();
}

SnappedItem _item(String name,
        {double kcal = 180, double? grams = 150, double p = 9, double c = 22,
        double f = 6}) =>
    SnappedItem(
        name: name, portionLabel: '1 katori', grams: grams, energyKcal: kcal,
        proteinG: p, carbG: c, fatG: f, confidence: 0.45);

ProviderContainer _container(PhotoSnapService svc, SakamaDatabase db) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      byokStoreProvider.overrideWithValue(FakeByokStore()),
      photoSnapServiceProvider.overrideWithValue(svc),
    ]);

void main() {
  late SakamaDatabase db;
  setUp(() => db = SakamaDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('snap: detected items become editable drafts (SnapReady)', () async {
    final c = _container(_FakeSnap([_item('Dal'), _item('Rice')]), db);
    addTearDown(c.dispose);
    await c.read(snapControllerProvider.notifier)
        .snap(imageBase64: 'zzz');
    final s = c.read(snapControllerProvider);
    expect(s, isA<SnapReady>());
    expect((s as SnapReady).drafts.map((d) => d.item.name), ['Dal', 'Rice']);
    expect(s.drafts.every((d) => d.keep), isTrue);
  });

  test('adjusting grams scales the macros proportionally', () {
    final d = SnapDraft(_item('Dal', kcal: 180, grams: 150));
    expect(d.energyKcal, 180);
    d.grams = 300; // doubled
    expect(d.energyKcal, closeTo(360, 0.01));
    expect(d.proteinG, closeTo(18, 0.01));
  });

  test('null grams seeds a sane default, not 0', () {
    final d = SnapDraft(_item('Curry', kcal: 200, grams: null));
    expect(d.grams, greaterThan(0));
    expect(d.energyKcal, 200); // factor 1 at the seeded grams
  });

  test('logKept writes only kept items, tagged photo, scaled to edited grams',
      () async {
    final c = _container(_FakeSnap([_item('Dal', grams: 150), _item('Rice')]), db);
    addTearDown(c.dispose);
    final ctl = c.read(snapControllerProvider.notifier);
    await ctl.snap(imageBase64: 'zzz');
    final ready = c.read(snapControllerProvider) as SnapReady;
    ready.drafts[0].grams = 300;   // doubled -> 360 kcal
    ready.drafts[1].keep = false;  // dropped

    final n = await ctl.logKept('2026-07-30');
    expect(n, 1);
    final rows = await db.select(db.foodLogs).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Dal');
    expect(rows.single.loggedVia, 'photo');
    expect(rows.single.grams, 300);
    expect(rows.single.energyKcal, closeTo(360, 0.5));
  });

  test('no_food / budget / error map to distinct states', () async {
    for (final (exc, matcher) in [
      (PhotoSnapException('x', noFood: true), isA<SnapNoFood>()),
      (PhotoSnapException('x', budgetExhausted: true), isA<SnapBudgetExhausted>()),
      // A provider failure is NOT a connectivity failure. Conflating them told
      // the user to check their connection while the real cause was an
      // exhausted OpenRouter balance (2026-08-07).
      (PhotoSnapException('x', providerDown: true), isA<SnapProviderDown>()),
      (PhotoSnapException('x', signInFailed: true), isA<SnapSignInFailed>()),
      (PhotoSnapException('x'), isA<SnapError>()),
    ]) {
      final c = _container(_FakeSnap(exc), db);
      addTearDown(c.dispose);
      await c.read(snapControllerProvider.notifier).snap(imageBase64: 'z');
      expect(c.read(snapControllerProvider), matcher);
    }
  });

  test('camera permission denied -> SnapPermissionDenied, not a hung spinner '
      '(#57 blocking)', () async {
    final c = _container(_FakeSnap(const []), db);
    addTearDown(c.dispose);
    await c.read(snapControllerProvider.notifier).snap(
        capture: () async =>
            throw PlatformException(code: 'camera_access_denied'));
    final s = c.read(snapControllerProvider);
    expect(s, isA<SnapPermissionDenied>());
    expect(s, isNot(isA<SnapIdle>()));
    expect(s, isNot(isA<SnapAnalyzing>()));
  });

  test('other camera failure -> SnapError (still not a hung spinner)',
      () async {
    final c = _container(_FakeSnap(const []), db);
    addTearDown(c.dispose);
    await c.read(snapControllerProvider.notifier).snap(
        capture: () async => throw StateError('no camera'));
    expect(c.read(snapControllerProvider), isA<SnapError>());
  });

  test('cancelled camera (null image) leaves state Idle', () async {
    final c = _container(_FakeSnap(const []), db);
    addTearDown(c.dispose);
    await c.read(snapControllerProvider.notifier)
        .snap(capture: () async => null);
    expect(c.read(snapControllerProvider), isA<SnapIdle>());
  });
}
