/// What a spoken reply to a pending proposal means.
///
/// A5 (voice-first Vita). Vita proposes; the user confirms. Until now the only
/// way to confirm was a tap, which is the safe default but breaks the pillar
/// the feature exists for: hands are wet, the phone is on the counter, and
/// "log it" should finish the job.
///
/// THE ASYMMETRY IS THE WHOLE DESIGN. Confirming writes to the user's health
/// diary; declining writes nothing. So the two errors are not equal:
///
///   - hearing "no" as "yes"  → food they did not eat is in their diary, and
///     they may never notice it went in
///   - hearing "yes" as "no"  → the card is still on screen and they tap it
///
/// Everything below is built around never making the first mistake. Anything
/// ambiguous, anything long, anything carrying both an agreement and a refusal
/// resolves to [SpokenIntent.unrecognised], which leaves the proposal standing
/// and treats the words as an ordinary message. ADR 0016 decision 2 still
/// holds: Vita never writes on its own, and a spoken confirmation is an
/// explicit user act, not the model deciding.
enum SpokenIntent {
  /// An unmistakable yes. Writes the pending draft.
  confirm,

  /// An unmistakable no. Discards it; nothing is written.
  dismiss,

  /// Anything else, INCLUDING anything ambiguous. The proposal stays up and
  /// the words are handled as a new message.
  unrecognised,
}

/// What the app should DO with a finished dictation.
///
/// Separate from [SpokenIntent] because the same words mean different things
/// depending on whether a proposal is on screen: with nothing pending, "yes"
/// is just a word to put in the composer.
enum DictationAction {
  /// Write the pending draft.
  confirmDraft,

  /// Discard it.
  dismissDraft,

  /// Put the words in the composer, unsent, for the user to send or edit.
  fillComposer,
}

/// Decide what a dictation result does.
///
/// PURE AND PUBLIC so it is testable. Left inside the widget, the branch that
/// turns speech into a health-diary WRITE would be reachable by no test — the
/// same absence that let an unreachable error message ship in #151.
DictationAction actionForDictation({
  required String text,
  required bool hasPendingDraft,
}) {
  if (!hasPendingDraft) return DictationAction.fillComposer;
  return switch (classifySpokenReply(text)) {
    SpokenIntent.confirm => DictationAction.confirmDraft,
    SpokenIntent.dismiss => DictationAction.dismissDraft,
    // Not an answer. The proposal stays up and the words become dictation, so
    // a misheard word costs a tap rather than a wrong entry.
    SpokenIntent.unrecognised => DictationAction.fillComposer,
  };
}

/// Words that mean yes, in the English and Hindi an Indian user actually
/// speaks to a phone. Romanised Hindi because that is what a speech engine set
/// to en-IN returns.
const _affirmatives = {
  'yes', 'yeah', 'yep', 'yup', 'ya', 'yah', 'yes please', 'ok', 'okay', 'k',
  'sure', 'confirm', 'confirmed', 'correct', 'right', 'thats right',
  'that is right', 'log it', 'log that', 'log', 'save it', 'save that', 'save',
  'add it', 'add that', 'do it', 'go ahead', 'please do', 'perfect', 'exactly',
  'sounds good', 'looks good', 'thats it', 'that is it', 'good',
  // Hindi / Indian English, romanised.
  'haan', 'han', 'ha', 'haan ji', 'ji', 'ji haan', 'bilkul', 'theek hai',
  'thik hai', 'sahi hai', 'kar do', 'kar de', 'haan kar do',
};

/// Words that mean no.
const _negatives = {
  'no', 'nope', 'nah', 'na', 'no thanks', 'no thank you', 'cancel', 'dont',
  'do not', 'dont log it', 'do not log it', 'discard', 'delete', 'remove',
  'forget it', 'never mind', 'nevermind', 'not right', 'thats wrong',
  'that is wrong', 'wrong', 'not yet', 'skip', 'stop', 'leave it',
  // Hindi / Indian English, romanised.
  'nahi', 'nahin', 'nai', 'mat karo', 'rehne do', 'chodo', 'nahi ji',
};

/// The most words an answer to "shall I log this?" can be.
///
/// A real answer is short. Past this, the user is talking rather than
/// answering — "no I had two rotis not three" is a CORRECTION, and treating
/// its first word as a decision would throw away what they actually said.
const _maxAnswerWords = 4;

/// Classify a spoken reply given to a pending proposal.
///
/// Only call this when a proposal is actually on screen. With nothing pending,
/// "yes" is just a word.
SpokenIntent classifySpokenReply(String utterance) {
  final normalised = _normalise(utterance);
  if (normalised.isEmpty) return SpokenIntent.unrecognised;

  final words = normalised.split(' ');
  if (words.length > _maxAnswerWords) return SpokenIntent.unrecognised;

  final yes = _affirmatives.contains(normalised);
  final no = _negatives.contains(normalised);

  // Both, or neither, means we did not understand. "no yes" is not a decision,
  // and guessing at one would guess at a write.
  if (yes == no) return SpokenIntent.unrecognised;
  if (yes) return SpokenIntent.confirm;
  return SpokenIntent.dismiss;
}

/// Lowercase, strip punctuation and filler, collapse whitespace.
///
/// Speech engines punctuate ("Yes."), capitalise, and prepend filler ("um,
/// yes"). None of that changes the meaning, and all of it would defeat an
/// exact-match lookup.
String _normalise(String raw) {
  var s = raw.toLowerCase().trim();
  // Apostrophes are DELETED, not spaced, so "that's" becomes "thats" rather
  // than "that s" — the latter is three words and would blow the answer-length
  // limit as well as missing the lookup. Curly quotes too: phone keyboards and
  // some speech engines emit them.
  s = s.replaceAll(RegExp("['‘’ʼ]"), '');
  // Everything else non-alphanumeric becomes a separator.
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return s;

  // Leading filler only. A filler word in the middle ("yes um no") is exactly
  // the confusion this must not resolve.
  final words = s.split(' ');
  const filler = {'um', 'uh', 'er', 'hmm', 'hm', 'well', 'so', 'like'};
  var start = 0;
  while (start < words.length - 1 && filler.contains(words[start])) {
    start++;
  }
  return words.sublist(start).join(' ');
}
