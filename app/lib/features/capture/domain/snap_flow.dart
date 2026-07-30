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
