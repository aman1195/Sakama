import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/core/db/database.dart';
import 'package:sakama/core/providers/app_providers.dart';
import 'package:sakama/features/coach/data/memory_extractor.dart';
import 'package:sakama/features/coach/data/memory_repository.dart';
import 'package:sakama/features/coach/presentation/memory_page.dart';

Future<void> _pump(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Unmount AND let Drift's stream teardown timer fire. Without the trailing
/// pump the test ends with a pending timer and fails on unmount rather than on
/// anything it was actually asserting.
Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('extraction output is UNTRUSTED and validated hard', () {
    // A junk memory is worse than a missing one: the user sees it, cannot edit
    // it (decision 10), and it silently steers every later reply.
    test('an invalid kind is dropped, not coerced', () {
      final e = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[{"kind":"vibes","content":"likes mangoes"},'
          '{"kind":"preference","content":"likes mangoes"}]}');
      expect(e.facts, hasLength(1));
      expect(e.facts.single.kind, 'preference');
    });

    test('NaN confidence cannot slip through', () {
      // Every comparison against NaN is false, so a bounds check alone would
      // pass it straight into the ranking. Same trap as the tool-call parser.
      final e = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[{"kind":"goal","content":"lose 5kg","confidence":"NaN"}]}');
      expect(e.facts.single.confidence, 0.5);
      expect(e.facts.single.confidence.isFinite, isTrue);
    });

    test('out-of-range confidence is clamped', () {
      final e = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[{"kind":"goal","content":"lose 5kg","confidence":9}]}');
      expect(e.facts.single.confidence, 1.0);
    });

    test('a one-word fragment and an essay are both rejected', () {
      final long = 'x' * 300;
      final e = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[{"kind":"goal","content":"ok"},'
          '{"kind":"goal","content":"$long"}]}');
      expect(e.facts, isEmpty,
          reason: 'a fragment is meaningless without its thread; an essay is '
              'a summary wearing a fact\'s clothes');
    });

    test('a markdown-fenced reply is still parsed', () {
      // Measured 2026-08-11: qwen3-32b and glm-4.7-flash both fence their
      // output despite response_format: json_object. Without de-fencing,
      // jsonDecode throws, parse returns empty, and memory silently never
      // populates — a feature that looks healthy while learning nothing.
      const fenced = '```json\n'
          '{"facts":[{"kind":"constraint","content":"Lactose intolerant",'
          '"confidence":0.9}],"summary":"Talked about dairy."}\n```';
      final e = EdgeFunctionMemoryExtractor.parse(fenced);
      expect(e.facts.single.content, 'Lactose intolerant');
      expect(e.facts.single.kind, 'constraint');
      expect(e.summary, 'Talked about dairy.');
    });

    test('a bare ``` fence with no language tag also parses', () {
      final e = EdgeFunctionMemoryExtractor.parse(
          '```\n{"facts":[],"summary":"ok"}\n```');
      expect(e.summary, 'ok');
    });

    test('malformed JSON yields nothing rather than throwing', () {
      // Extraction is background work; a provider hiccup must never surface.
      expect(EdgeFunctionMemoryExtractor.parse('not json').isEmpty, isTrue);
      expect(EdgeFunctionMemoryExtractor.parse('[]').isEmpty, isTrue);
      expect(EdgeFunctionMemoryExtractor.parse('{}').isEmpty, isTrue);
    });

    test('a runaway list is capped', () {
      final many = List.generate(
          40, (i) => '{"kind":"observation","content":"fact number $i"}').join(',');
      expect(EdgeFunctionMemoryExtractor.parse('{"facts":[$many]}').facts,
          hasLength(10));
    });

    test('the summary comes through and is bounded', () {
      final e = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[],"summary":"Talked about protein targets."}');
      expect(e.summary, 'Talked about protein targets.');
      final huge = EdgeFunctionMemoryExtractor.parse(
          '{"facts":[],"summary":"${'y' * 900}"}');
      expect(huge.summary!.length, 600);
    });
  });

  group('the memory screen', () {
    late SakamaDatabase db;
    late MemoryRepository repo;

    setUp(() {
      db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      repo = MemoryRepository(db);
    });
    tearDown(() => db.close());

    Future<void> mount(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: const MaterialApp(home: MemoryPage()),
      ));
      await _pump(t);
    }

    testWidgets('shows facts in plain words, not jargon', (t) async {
      await t.runAsync(() => repo.remember(
          kind: 'constraint', content: 'Allergic to peanuts'));
      await mount(t);

      expect(find.text('Allergic to peanuts'), findsOneWidget);
      expect(find.text('Something you avoid'), findsOneWidget,
          reason: '"constraint" is our vocabulary, not the user\'s');
      expect(find.text('constraint'), findsNothing);
      await _dispose(t);
    });

    testWidgets('forgetting one fact removes it', (t) async {
      final id = await t.runAsync(() =>
          repo.remember(kind: 'preference', content: 'Likes paneer'));
      await t.runAsync(() => repo.remember(kind: 'goal', content: 'Lose 5kg'));
      await mount(t);

      await t.tap(find.bySemanticsIdentifier('memory-forget-$id'));
      await _pump(t);

      final left = await t.runAsync(() => repo.all(null));
      expect(left!.single.content, 'Lose 5kg');
      await _dispose(t);
    });

    testWidgets('reset asks first, then reports HOW MANY it forgot', (t) async {
      await t.runAsync(() => repo.remember(kind: 'goal', content: 'Lose 5kg'));
      await t.runAsync(
          () => repo.remember(kind: 'preference', content: 'Likes paneer'));
      await mount(t);

      await t.tap(find.bySemanticsIdentifier('memory-reset'));
      await _pump(t, 6);
      expect(find.text('Forget everything?'), findsOneWidget);

      await t.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Forget all')));
      await _pump(t);

      expect(await t.runAsync(() => repo.all(null)), isEmpty);
      // Concrete, because a silent success looks identical to a failure.
      expect(find.textContaining('forgot 2 things'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('with nothing learned, it explains rather than showing a void',
        (t) async {
      await mount(t);
      expect(find.bySemanticsIdentifier('memory-empty'), findsOneWidget);
      expect(find.textContaining('Nothing learned yet'), findsOneWidget);
      // Nothing to reset means no destructive action offered.
      expect(find.bySemanticsIdentifier('memory-reset'), findsNothing);
      await _dispose(t);
    });
  });

  group('identity change', () {
    test('deleteAll drops EVERY fact, whoever owned it', () async {
      // The safety-critical wiring (review of #106): user B must never inherit
      // user A's distilled health facts. Blanket, because at identity-change
      // time the departing uid is exactly what has gone away.
      final db = SakamaDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = MemoryRepository(db);
      await repo.remember(kind: 'constraint', content: 'Allergic to peanuts',
          userId: 'userA');
      await repo.remember(kind: 'goal', content: 'Lose 5kg', userId: 'userB');
      await repo.remember(kind: 'preference', content: 'pre-auth');

      expect(await repo.deleteAll(), 3);
      expect(await db.select(db.memoryFacts).get(), isEmpty,
          reason: 'a user-scoped delete would strand rows in exactly the case '
              'this exists to handle');
    });
  });
}
