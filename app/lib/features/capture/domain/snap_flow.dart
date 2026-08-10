import 'snap_draft.dart';

/// The states of the PhotoSnap flow, as a sealed value the UI switches over
/// (same discipline as BarcodeResult — failures are data, off the Riverpod
/// auto-retry path).
sealed class SnapState {
  const SnapState();
}

/// No photo yet — the capture prompt.
class SnapIdle extends SnapState {
  const SnapIdle();
}

/// Photo taken, model working.
class SnapAnalyzing extends SnapState {
  const SnapAnalyzing();
}

/// Items detected — the editable confirm list.
class SnapReady extends SnapState {
  SnapReady(this.drafts);
  final List<SnapDraft> drafts;
}

/// Recoverable failures, worded distinctly.
class SnapNoFood extends SnapState {
  const SnapNoFood();
}

class SnapBudgetExhausted extends SnapState {
  const SnapBudgetExhausted();
}

class SnapError extends SnapState {
  const SnapError();
}

/// The AI provider failed, which is NOT a connectivity problem. Split out
/// because [SnapError] renders a "check your connection" message, and on
/// 2026-08-07 that sent us debugging the network while the real cause was an
/// exhausted provider balance. Retrying immediately will not help, so this
/// state deliberately offers no retry-and-hope affordance.
class SnapProviderDown extends SnapState {
  const SnapProviderDown();
}

/// We could not obtain a session, so the request went out unauthenticated.
/// Also previously indistinguishable from a network failure.
class SnapSignInFailed extends SnapState {
  const SnapSignInFailed();
}

/// The camera/photo permission was denied — a Settings-flavoured message, not
/// the network-flavoured SnapError (review #57).
class SnapPermissionDenied extends SnapState {
  const SnapPermissionDenied();
}
