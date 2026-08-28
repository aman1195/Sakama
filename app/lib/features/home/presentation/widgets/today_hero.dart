import 'package:flutter/material.dart';

import '../../../../app/status_surface.dart';

/// The day, as one bright card.
///
/// Modelled directly on the reference apps' balance card, and the first
/// version of this refresh missed the point of it. That card works because it
/// is a single saturated surface carrying a huge number and its actions —
/// everything else on the screen is quiet by comparison. What shipped instead
/// was a grey card containing a grey ring and grey bars, which took the
/// palette and none of the hierarchy.
///
/// So: no ring. The reference states a number and gets out of the way, and a
/// progress ring is a different design language (it belongs to the app this
/// replaced). Progress is a thin bar under the number instead — legible at a
/// glance, and it does not fight the figure for attention.
class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.status,
    required this.target,
    required this.eaten,
    required this.actions,
    this.macros,
    this.burned,
    this.burnedUnknown = 0,
  });

  final TrackStatus status;
  final int target;
  final double eaten;
  final List<Widget> actions;
  final Widget? macros;

  /// Calories burned today, or null when nothing was computed.
  ///
  /// SHOWN BESIDE "eaten", NEVER SUBTRACTED FROM THE TARGET. Netting it would
  /// move the day's budget by a number derived from a MET formula and a
  /// weigh-in, silently, and the user would eat the difference. They can see it
  /// and decide what it is worth.
  final double? burned;

  /// Workouts today whose burn could not be computed — an unrecognised
  /// activity, or no duration. Counted out loud so the burn figure does not
  /// read as the whole day's effort.
  final int burnedUnknown;

  String _activityLine() {
    final parts = <String>['${eaten.round()} eaten'];
    // Only when we actually computed one. A "0 burned" on a rest day is fine;
    // a "0 burned" on a day with three logged lifts is a lie by rounding.
    if (burned != null && burned! > 0) parts.add('${burned!.round()} burned');
    if (burnedUnknown > 0) {
      parts.add('$burnedUnknown without an estimate');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT `target - eaten + burned`. See [burned].
    final remaining = target - eaten;
    final over = remaining < 0;
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    final ink = status.on(Theme.of(context).brightness);
    final text = Theme.of(context).textTheme;

    return StatusSurface(
      identifier: 'today-hero',
      status: status,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The small qualifier sits ABOVE the number, as in the
              // reference's "USD VISA" — it tells you what you are looking at
              // without competing with it.
              Text(over ? 'OVER BY' : 'REMAINING',
                  style: text.labelSmall?.copyWith(
                    color: ink.withValues(alpha: 0.6),
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text('of $target kcal',
                  style: text.labelMedium
                      ?.copyWith(color: ink.withValues(alpha: 0.7))),
            ],
          ),
          const SizedBox(height: 2),
          // THE number. Oversized on purpose — this is the one thing a person
          // opens the app to see, and the reference makes its equivalent
          // impossible to miss.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                remaining.abs().round().toString(),
                style: text.displaySmall?.copyWith(
                  color: ink,
                  fontSize: 56,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.5,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('kcal',
                    style: text.titleMedium
                        ?.copyWith(color: ink.withValues(alpha: 0.75))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: ink,
              backgroundColor: ink.withValues(alpha: 0.22),
            ),
          ),
          const SizedBox(height: 4),
          Text(_activityLine(),
              style: text.bodySmall
                  ?.copyWith(color: ink.withValues(alpha: 0.7))),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            // Circular actions in a row, the reference's signature move. They
            // live ON the bright card so the primary things you can do are
            // inside the primary surface, not scattered below it.
            Row(children: [
              for (final a in actions) ...[a, const SizedBox(width: 10)]
            ]),
          ],
          if (macros != null) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: ink.withValues(alpha: 0.15)),
            const SizedBox(height: 14),
            macros!,
          ],
        ],
      ),
    );
  }
}

/// A circular action on the hero card — ink-on-translucent, so it reads as
/// part of the card rather than as a floating button.
class HeroAction extends StatelessWidget {
  const HeroAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.identifier,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String identifier;

  @override
  Widget build(BuildContext context) {
    final ink = DefaultTextStyle.of(context).style.color ?? Colors.black;
    return Semantics(
      identifier: identifier,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 21, color: ink),
          ),
        ),
      ),
    );
  }
}

/// Macros as three columns rather than three stacked bars.
///
/// Stacked full-width bars ate half the card and said little; three short
/// columns give the same information in a third of the height and read as a
/// summary, which is what they are.
class MacroRow extends StatelessWidget {
  const MacroRow({
    super.key,
    required this.protein,
    required this.proteinTarget,
    required this.carbs,
    required this.carbTarget,
    required this.fat,
    required this.fatTarget,
  });

  final double protein, carbs, fat;
  final int proteinTarget, carbTarget, fatTarget;

  @override
  Widget build(BuildContext context) {
    final ink = DefaultTextStyle.of(context).style.color ?? Colors.black;
    return Row(
      children: [
        _col(context, 'Protein', protein, proteinTarget, ink),
        _col(context, 'Carbs', carbs, carbTarget, ink),
        _col(context, 'Fat', fat, fatTarget, ink),
      ],
    );
  }

  Widget _col(BuildContext context, String label, double eaten, int target,
      Color ink) {
    final text = Theme.of(context).textTheme;
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: text.labelSmall?.copyWith(
                    color: ink.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('${eaten.round()}',
                style: text.titleLarge?.copyWith(
                    color: ink, fontWeight: FontWeight.w800, height: 1.1)),
            Text('of ${target}g',
                style: text.labelSmall
                    ?.copyWith(color: ink.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: ink,
                backgroundColor: ink.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
