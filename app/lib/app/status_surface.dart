import 'package:flutter/material.dart';

import 'theme.dart';

/// How a tracked number is doing against its target.
///
/// DELIBERATE PRODUCT DECISION (2026-08-26). Sakama previously refused to
/// colour a whole surface by a metric: PRODUCT.md listed it as an
/// anti-reference and principle 5 said "never colour the whole screen by a
/// calorie deficit". That was reversed on purpose — see PRODUCT.md, which was
/// amended rather than left contradicting the code, and DESIGN.md §0.1 for the
/// reasoning and the guardrails that came with it.
///
/// The guardrails are the part worth keeping honest. A full-bleed status colour
/// is a loud signal, and in a nutrition app loudness lands on someone's body,
/// so:
///  - **[over] is amber-to-red, not alarm red at one calorie past target.**
///    Being slightly over is normal; the surface should not scream at 2,001
///    kcal when the target was 2,000.
///  - **The copy stays neutral.** Colour carries the state; words never
///    editorialise ("Over by 240" — not "You blew your budget").
///  - **Contrast is enforced on every state** (`statusOn`), because a coloured
///    surface that cannot carry its own text is worse than no colour at all.
enum TrackStatus {
  /// Nothing logged yet, or no target set.
  ///
  /// Renders in the BRAND colour, same as [onTrack]. That is deliberate and it
  /// took a device to see why: making this grey meant the first screen anyone
  /// opens — an empty day — had no colour in it at all, and the whole
  /// treatment was invisible until the user had already logged something.
  ///
  /// A brand-coloured card is chrome, not congratulation. The reference apps
  /// work exactly this way: the card is the brand colour in the normal case
  /// and changes only when something needs attention. So the guardrail this
  /// replaces ("empty must not look like on-track") was solving the wrong
  /// problem — the risk is praising someone for not eating, and a card that
  /// says "1,750 kcal left" praises nothing.
  neutral,

  /// Within target.
  onTrack,

  /// Close to target (>=90%). Worth noticing, not worth alarm.
  nearing,

  /// Past target.
  over,

  /// The user turned status colouring off (Me -> Colour my day). Not a state
  /// of the data — a state of their preference — which is why it is separate
  /// from [neutral] rather than reusing it.
  muted,
}

/// Classify progress against a target.
///
/// [nearingAt] is 0.9 rather than something tighter because a person eating
/// their planned dinner passes 90% on the way to 100% every single day. That
/// is information, not a warning.
TrackStatus trackStatus({required double value, required double target}) {
  if (target <= 0) return TrackStatus.neutral;
  final ratio = value / target;
  if (ratio <= 0) return TrackStatus.neutral;
  if (ratio > 1.0) return TrackStatus.over;
  if (ratio >= 0.9) return TrackStatus.nearing;
  return TrackStatus.onTrack;
}

extension TrackStatusColors on TrackStatus {
  /// The surface fill. Saturated on purpose — this is the fintech treatment,
  /// where the card itself carries the state.
  Color surface(Brightness b) => switch (this) {
        TrackStatus.muted =>
          b == Brightness.light ? Colors.white : SakamaPalette.surfaceDark,
        // Brand colour for both: a normal day looks like the app.
        TrackStatus.neutral || TrackStatus.onTrack => SakamaPalette.accent,
        TrackStatus.nearing => const Color(0xFFF5C451),
        TrackStatus.over => const Color(0xFFFD8A5F),
      };

  /// Text and icons ON that surface. Every status resolves to a colour that
  /// clears WCAG AA against its own fill — asserted in theme_test.
  Color on(Brightness b) => switch (this) {
        TrackStatus.muted =>
          b == Brightness.light ? SakamaPalette.inkDark : Colors.white,
        // The bright fills are all light, so they take ink, not white.
        _ => SakamaPalette.onAccent,
      };
}

/// A full-bleed card whose colour IS the state — the fintech balance-card
/// pattern, applied to a nutrition target.
class StatusSurface extends StatelessWidget {
  const StatusSurface({
    super.key,
    required this.status,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 20),
    this.identifier,
  });

  final TrackStatus status;
  final Widget child;
  final EdgeInsets padding;
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final card = AnimatedContainer(
      // Long enough to read as a state change rather than a flicker, since
      // logging a meal can move the surface from lime to amber in one tap.
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutQuart,
      padding: padding,
      decoration: BoxDecoration(
        color: status.surface(b),
        borderRadius: BorderRadius.circular(24),
      ),
      // One place decides the on-colour, so no caller can put low-contrast
      // text on a saturated fill by accident.
      child: DefaultTextStyle.merge(
        style: TextStyle(color: status.on(b)),
        child: IconTheme.merge(
          data: IconThemeData(color: status.on(b)),
          child: child,
        ),
      ),
    );
    return identifier == null
        ? card
        : Semantics(identifier: identifier!, child: card);
  }
}
