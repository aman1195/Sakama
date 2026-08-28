import 'package:flutter/material.dart';

/// How much to trust the numbers on a logged entry, from how it was logged.
///
/// Rule 7 makes every food row carry source, licence and confidence, and none
/// of it ever reached the screen. This is the same idea at the level the user
/// actually sees: an entry matched from the food database is a looked-up
/// number, and an entry a vision model produced from a photograph is a guess.
/// Both render as "412 kcal" and only one of them was measured.
///
/// Derived from `logged_via` rather than a new column, because that column
/// already records exactly this and is written on every path.
enum EntryConfidence {
  /// Came from a database row: the food database, a barcode, or a repeat of an
  /// earlier entry that itself came from one.
  verified,

  /// A model produced it. Photo estimates, AI estimation, Vita's chat logging.
  /// The number is plausible, not measured.
  estimated,

  /// The user typed it. Not verified by us and not guessed by us — theirs.
  manual;

  static EntryConfidence of(String loggedVia) => switch (loggedVia) {
        'search' || 'barcode' || 'recent' => EntryConfidence.verified,
        'photo' || 'ai_estimate' || 'vita' => EntryConfidence.estimated,
        _ => EntryConfidence.manual,
      };

  /// Null for [manual]: a number the user typed themselves needs no badge, and
  /// marking every hand-entered row would make the badge noise instead of
  /// signal. The two that matter are "we looked this up" and "we guessed".
  String? get label => switch (this) {
        EntryConfidence.verified => 'Verified',
        EntryConfidence.estimated => 'Estimate',
        EntryConfidence.manual => null,
      };

  IconData? get icon => switch (this) {
        EntryConfidence.verified => Icons.verified_outlined,
        EntryConfidence.estimated => Icons.auto_awesome_outlined,
        EntryConfidence.manual => null,
      };
}

/// A small badge, or nothing at all.
///
/// Deliberately not a colour-coded traffic light. An estimate is not a warning
/// and the user did nothing wrong by photographing their lunch; PRODUCT.md's
/// no-shame principle applies to how we mark data as much as to how we report a
/// day. It states which kind of number this is and stops there.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge(this.loggedVia, {super.key});
  final String loggedVia;

  @override
  Widget build(BuildContext context) {
    final c = EntryConfidence.of(loggedVia);
    final label = c.label;
    if (label == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // Both use the same muted ink. The distinction is the word and the glyph,
    // not alarm: colouring estimates amber would read as "this is wrong".
    final ink = scheme.onSurfaceVariant;

    return Semantics(
      identifier: 'confidence-${c.name}',
      label: c == EntryConfidence.verified
          ? 'Matched from the food database'
          : 'Estimated, not measured',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.icon, size: 13, color: ink),
          const SizedBox(width: 3),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: ink, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
