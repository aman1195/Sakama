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
  });
}
