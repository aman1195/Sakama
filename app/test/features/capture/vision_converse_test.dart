import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/capture/data/photosnap_service.dart';

/// Converse mode (docs/architecture/07-photo-in-chat.md §2). The response is
/// UNTRUSTED model output, so parsing is validated the same way the logging
/// path is — with one deliberate difference: zero items is legitimate here.
String _resp({
  String answer = 'Looks balanced — the dal gives you decent protein.',
  String description = 'two rotis, dal tadka, cucumber salad',
  String items = '''[{"name":"dal tadka","portion_label":"1 katori","grams":150,
     "energy_kcal":180,"protein_g":9,"carb_g":22,"fat_g":6,"confidence":0.7}]''',
}) =>
    '{"answer":"$answer","description":"$description","items":$items}';

void main() {
  group('gateway failures name the RIGHT cause', () {
    // 2026-08-07: OpenRouter returned 402 (out of credits) on every image
    // request. The function turned that into a 502, and the app told the user
    // to check their connection — so we debugged the network for half an hour
    // while the real fix was a billing page. Wrong cause is worse than vague.
    test('502 is a provider failure, NOT a connectivity failure', () {
      final e = EdgeFunctionPhotoSnap.fromStatus(502);
      expect(e.providerDown, isTrue);
      expect(e.signInFailed, isFalse);
      expect(e.budgetExhausted, isFalse,
          reason: 'a provider outage is not the user spending their quota');
    });

    test('401/403 is a sign-in failure', () {
      for (final s in [401, 403]) {
        final e = EdgeFunctionPhotoSnap.fromStatus(s);
        expect(e.signInFailed, isTrue, reason: 'status $s');
        expect(e.providerDown, isFalse, reason: 'status $s');
      }
    });

    test('an unknown status stays generic rather than guessing', () {
      final e = EdgeFunctionPhotoSnap.fromStatus(418);
      expect(e.providerDown, isFalse);
      expect(e.signInFailed, isFalse);
      expect(e.budgetExhausted, isFalse);
    });
  });

  group('accepts a well-formed conversation', () {
    test('answer, description and loggable items all come through', () {
      final c = EdgeFunctionPhotoSnap.parseConversation(_resp());
      expect(c.answer, contains('dal'));
      expect(c.description, 'two rotis, dal tadka, cucumber salad');
      expect(c.items.single.name, 'dal tadka');
      expect(c.hasLoggableItems, isTrue);
    });

    test('a NON-PLATED image is answered with zero items, not refused', () {
      // A menu, a packet, an ingredients label — the case log mode refuses and
      // converse mode must handle, because that is where a coach earns its keep.
      final c = EdgeFunctionPhotoSnap.parseConversation(_resp(
          answer: 'That packet is mostly refined flour and palm oil — '
              'given your plan I would skip it.',
          description: 'a packet of fried namkeen',
          items: '[]'));
      expect(c.answer, contains('skip it'));
      expect(c.items, isEmpty);
      expect(c.hasLoggableItems, isFalse,
          reason: 'nothing plated means nothing loggable — but still answerable');
    });

    test('a missing description degrades to empty, not a failure', () {
      final c = EdgeFunctionPhotoSnap.parseConversation(
          '{"answer":"Looks fine.","items":[]}');
      expect(c.description, isEmpty);
      expect(c.answer, 'Looks fine.');
    });
  });

  group('refuses unusable output', () {
    test('not JSON / not an object', () {
      expect(() => EdgeFunctionPhotoSnap.parseConversation('sorry!'),
          throwsA(isA<PhotoSnapException>()));
      expect(() => EdgeFunctionPhotoSnap.parseConversation('[1,2]'),
          throwsA(isA<PhotoSnapException>()));
    });

    test('an empty or missing answer is a failure', () {
      expect(() => EdgeFunctionPhotoSnap.parseConversation('{"items":[]}'),
          throwsA(isA<PhotoSnapException>()));
      expect(
          () => EdgeFunctionPhotoSnap.parseConversation(
              '{"answer":"   ","items":[]}'),
          throwsA(isA<PhotoSnapException>()));
    });

    test('a model that still refuses with no_food is tolerated as noFood', () {
      expect(
          () => EdgeFunctionPhotoSnap.parseConversation('{"error":"no_food"}'),
          throwsA(isA<PhotoSnapException>()
              .having((e) => e.noFood, 'noFood', isTrue)));
    });
  });

  test('items get the SAME bounds discipline as the logging path', () {
    // An absurd per-portion value must not become loggable just because it
    // arrived through the conversational route.
    final c = EdgeFunctionPhotoSnap.parseConversation(_resp(items: '''
      [{"name":"x","portion_label":"1","grams":150,"energy_kcal":999999,
        "protein_g":9,"carb_g":22,"fat_g":6,"confidence":0.7}]'''));
    expect(c.items, isEmpty,
        reason: 'parseItems rejects it; the answer still stands');
    expect(c.answer, isNotEmpty);
  });
}
