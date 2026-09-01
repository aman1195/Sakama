import 'package:flutter_test/flutter_test.dart';
import 'package:sakama/features/coach/domain/spoken_intent.dart';

/// Confirming writes to a health diary; declining writes nothing. So these
/// tests are deliberately lopsided: a handful pin that plain answers work, and
/// the rest hunt for anything that could turn a refusal, a correction or a
/// stray noise into a write the user never asked for.
void main() {
  SpokenIntent of(String s) => classifySpokenReply(s);

  group('plain answers work, or the feature is pointless', () {
    for (final yes in [
      'yes', 'Yes', 'YES', 'yes.', 'yeah', 'yep', 'ok', 'Okay!', 'sure',
      'log it', 'Log it.', 'save it', 'go ahead', 'confirm', 'that\'s right',
      'sounds good', 'do it',
    ]) {
      test('"$yes" confirms', () => expect(of(yes), SpokenIntent.confirm));
    }

    for (final no in [
      'no', 'No.', 'nope', 'nah', 'cancel', 'discard', 'never mind',
      'not yet', "that's wrong", 'no thanks', 'skip', 'leave it',
    ]) {
      test('"$no" dismisses', () => expect(of(no), SpokenIntent.dismiss));
    }
  });

  group('Hindi and Indian English, because that is who this is for', () {
    for (final yes in ['haan', 'haan ji', 'bilkul', 'theek hai', 'sahi hai',
      'kar do', 'ji haan']) {
      test('"$yes" confirms', () => expect(of(yes), SpokenIntent.confirm));
    }
    for (final no in ['nahi', 'nahin', 'mat karo', 'rehne do', 'nahi ji']) {
      test('"$no" dismisses', () => expect(of(no), SpokenIntent.dismiss));
    }
  });

  group('speech-engine noise does not change the meaning', () {
    test('punctuation and case are ignored', () {
      expect(of('  YES!  '), SpokenIntent.confirm);
      expect(of('No,'), SpokenIntent.dismiss);
    });

    test('leading filler is skipped', () {
      expect(of('um yes'), SpokenIntent.confirm);
      expect(of('uh, no'), SpokenIntent.dismiss);
    });

    test('filler in the MIDDLE is not skipped, because it is not filler there',
        () {
      // "yes um no" is a person changing their mind mid-sentence. Resolving it
      // either way is a guess, and one of the guesses writes.
      expect(of('yes um no'), SpokenIntent.unrecognised);
      // The case that actually PINS leading-only: stripping anywhere would
      // turn this into "yes" and confirm it. Review showed the assertion
      // above passes either way, so on its own it tested nothing.
      expect(of('yes um'), SpokenIntent.unrecognised);
      expect(of('ok well'), SpokenIntent.unrecognised);
    });

    test('filler does not buy extra words', () {
      // Length is judged BEFORE stripping. The other order let seven filler
      // words vanish and an eight-word utterance confirm.
      expect(of('um uh er hmm well so like yes'), SpokenIntent.unrecognised);
      expect(of('um yes'), SpokenIntent.confirm, reason: 'a hesitant yes is a yes');
    });
  });

  /// THE PART THAT MATTERS. Every case here must NOT confirm.
  group('nothing ambiguous is ever allowed to write', () {
    test('an answer carrying both a yes and a no is not a decision', () {
      for (final both in ['no yes', 'yes no', 'yeah no', 'no yeah']) {
        expect(of(both), SpokenIntent.unrecognised, reason: both);
      }
    });

    test('a correction is a message, not a confirmation', () {
      // The catastrophic case: the user is fixing the amount, and the first
      // word is an affirmative. Logging the WRONG figure here is worse than
      // not logging, because they believe they corrected it.
      expect(of('yes but it was two rotis'), SpokenIntent.unrecognised);
      expect(of('yeah actually make it half'), SpokenIntent.unrecognised);
      expect(of('no I had two rotis not three'), SpokenIntent.unrecognised);
    });

    test('a question is never a confirmation', () {
      expect(of('how many calories'), SpokenIntent.unrecognised);
      expect(of('is that a lot'), SpokenIntent.unrecognised);
    });

    test('a word merely CONTAINING yes does not confirm', () {
      // Substring matching would fire on all of these. Exact match is the
      // reason it does not.
      for (final s in ['yesterday', 'yes man syndrome thing', 'eyes']) {
        expect(of(s), isNot(SpokenIntent.confirm), reason: s);
      }
    });

    test('a long utterance is never a decision, however it starts', () {
      expect(of('yes yes yes yes yes'), SpokenIntent.unrecognised);
      expect(of('ok so what should I eat tonight'), SpokenIntent.unrecognised);
    });

    test('empty, blank and punctuation-only input is not a decision', () {
      for (final s in ['', '   ', '...', '?', '\n']) {
        expect(of(s), SpokenIntent.unrecognised, reason: '"$s"');
      }
    });

    test('an ordinary food sentence never confirms', () {
      // A user dictating a NEW entry while a proposal is up must not have it
      // read as agreement with the old one.
      for (final s in [
        'two rotis and dal',
        'I had chai',
        'add a banana',
        'log two eggs and toast',
      ]) {
        expect(of(s), isNot(SpokenIntent.confirm), reason: s);
      }
    });
  });

  group('the boundary between an answer and a message', () {
    test('four words can still be an answer', () {
      expect(of('yes please'), SpokenIntent.confirm);
    });

    test('past the limit it is a message', () {
      expect(of('one two three four five'), SpokenIntent.unrecognised);
    });

    test('the limit itself does the work, not just the word list', () {
      // Five words that are ALL affirmative tokens. Only the length rule can
      // refuse this, so raising the limit reddens the test.
      expect(of('yes yes yes yes yes'), SpokenIntent.unrecognised);
      expect(of('ok ok ok ok ok'), SpokenIntent.unrecognised);
    });
  });

  /// The decision the widget dispatches on. Extracted so the branch that turns
  /// speech into a health-diary WRITE is reachable by a test at all.
  group('actionForDictation', () {
    DictationAction act(String text, {bool pending = true}) =>
        actionForDictation(text: text, hasPendingDraft: pending);

    test('with nothing pending, even "yes" is just dictation', () {
      // No card is asking a question, so there is nothing to agree to.
      expect(act('yes', pending: false), DictationAction.fillComposer);
      expect(act('no', pending: false), DictationAction.fillComposer);
    });

    test('a clear yes to a pending proposal confirms it', () {
      expect(act('yes'), DictationAction.confirmDraft);
      expect(act('log it'), DictationAction.confirmDraft);
      expect(act('haan'), DictationAction.confirmDraft);
    });

    test('a clear no discards it', () {
      expect(act('no'), DictationAction.dismissDraft);
      expect(act('nahi'), DictationAction.dismissDraft);
    });

    test('anything else leaves the proposal standing', () {
      // The proposal is NOT dismissed here — the user gets to see it and the
      // words go to the composer, so nothing is lost either way.
      for (final s in [
        'yes but it was two rotis',
        'no I had two rotis not three',
        'how many calories is that',
        'two rotis and dal',
        '',
      ]) {
        expect(act(s), DictationAction.fillComposer, reason: '"$s"');
      }
    });

    test('nothing except an unmistakable yes can reach the write', () {
      // The property that matters, stated once: sweep a spread of realistic
      // utterances and assert none of the ambiguous ones confirms.
      const risky = [
        'yes no', 'no yes', 'yeah actually no', 'yesterday', 'eyes',
        'yes I think so maybe', 'ok but change it', 'not yet', 'wrong',
      ];
      for (final s in risky) {
        expect(act(s), isNot(DictationAction.confirmDraft), reason: '"$s"');
      }
    });
  });

  /// Removed after review. Every one of these reached a database write.
  group('words that are not consent', () {
    test('a laugh is not a yes', () {
      // Someone amused by a 900 kcal samosa is not agreeing to log it.
      expect(of('ha'), SpokenIntent.unrecognised);
      expect(of('Ha!'), SpokenIntent.unrecognised);
    });

    test('a bare "ji" is a request to REPEAT, not agreement', () {
      // In Hindi "ji?" commonly means "sorry, what?". Confirming a write on a
      // request to repeat is the exact inversion this file exists to prevent.
      expect(of('ji'), SpokenIntent.unrecognised);
      expect(of('ji?'), SpokenIntent.unrecognised);
      // The unambiguous forms still work.
      expect(of('haan ji'), SpokenIntent.confirm);
      expect(of('ji haan'), SpokenIntent.confirm);
    });

    test('a single stray letter is not a decision', () {
      expect(of('k'), SpokenIntent.unrecognised);
    });

    test('a bare verb is a clipped command, not an answer', () {
      // "log" is what "log two rotis" degrades to, and confirming would write
      // a pending draft for a completely different food.
      expect(of('log'), SpokenIntent.unrecognised);
      expect(of('save'), SpokenIntent.unrecognised);
      // With the object, it is unmistakable.
      expect(of('log it'), SpokenIntent.confirm);
      expect(of('save it'), SpokenIntent.confirm);
    });
  });
}
