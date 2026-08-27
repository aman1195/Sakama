import 'package:flutter/material.dart';

import '../status_surface.dart';
import '../theme.dart';

/// The component kit. Every screen is built from these, so the app reads as
/// one product rather than as twenty screens that happen to share a palette —
/// which is exactly what the first refresh produced.
///
/// The grammar, taken from the reference apps and applied consistently:
///  - ONE bright surface per screen, carrying the thing you came for.
///  - Everything else is a dark card on near-black, quiet by comparison.
///  - Numbers are large, tight-tracked and unmissable.
///  - Rows have a coloured icon chip on the left — a fixed optical anchor so a
///    list scans as a column instead of as prose.
///  - Actions are circles or stadium pills. Nothing is a bare text button.
/// Spacing scale. Named so layout code stops inventing numbers.
abstract final class Sk {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  static const radius = 24.0;
  static const radiusSm = 16.0;
}

/// The bright hero. One per screen, at the top, carrying the primary number
/// or the primary action.
class SkHero extends StatelessWidget {
  const SkHero({
    super.key,
    required this.child,
    this.status = TrackStatus.neutral,
    this.identifier,
    this.padding = const EdgeInsets.fromLTRB(22, 20, 22, 22),
  });

  final Widget child;
  final TrackStatus status;
  final String? identifier;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => StatusSurface(
        status: status,
        identifier: identifier,
        padding: padding,
        child: child,
      );
}

/// A dark content card. The quiet counterpart to [SkHero].
class SkCard extends StatelessWidget {
  const SkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sk.lg),
    this.onTap,
    this.identifier,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final card = Material(
      color: light ? Colors.white : SakamaPalette.surfaceDark,
      borderRadius: BorderRadius.circular(Sk.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return identifier == null
        ? card
        : Semantics(identifier: identifier!, child: card);
  }
}

/// A section heading with an optional trailing action.
class SkSection extends StatelessWidget {
  const SkSection(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sk.xs, Sk.xl, Sk.xs, Sk.md),
        child: Row(
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: -0.2)),
            const Spacer(),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: Sk.sm)),
                child: Text(action!),
              ),
          ],
        ),
      );
}

/// The signature list row: coloured icon chip, title, subtitle, trailing.
///
/// The chip is what makes a list scannable — a fixed anchor at a fixed size,
/// so the eye runs down a column instead of reading every line.
class SkRow extends StatelessWidget {
  const SkRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.identifier,
    this.tint,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? identifier;

  /// Overrides the chip colour — used where a row has its own identity
  /// (a macro, a meal), never to signal that a number is good or bad.
  final Color? tint;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final chip = tint ?? scheme.primaryContainer;
    final onChip = tint != null ? SakamaPalette.onAccent : scheme.onPrimaryContainer;

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: Sk.lg, vertical: dense ? Sk.sm + 2 : Sk.md),
        child: Row(
          children: [
            Container(
              width: dense ? 34 : 42,
              height: dense ? 34 : 42,
              decoration: BoxDecoration(
                color: chip,
                borderRadius: BorderRadius.circular(dense ? 10 : 13),
              ),
              child: Icon(icon, size: dense ? 17 : 20, color: onChip),
            ),
            const SizedBox(width: Sk.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (dense ? text.bodyLarge : text.titleMedium)
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Sk.sm), trailing!],
          ],
        ),
      ),
    );
    return identifier == null
        ? row
        : Semantics(identifier: identifier!, child: row);
  }
}

/// A number with a label under it. The unit of a stat strip.
class SkStat extends StatelessWidget {
  const SkStat(
      {super.key,
      required this.value,
      required this.label,
      this.sub,
      this.color});

  final String value;
  final String label;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ink = color ?? DefaultTextStyle.of(context).style.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: text.labelSmall?.copyWith(
                color: ink?.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(value,
            style: text.titleLarge?.copyWith(
                color: ink, fontWeight: FontWeight.w800, height: 1.1)),
        if (sub != null)
          Text(sub!,
              style: text.labelSmall
                  ?.copyWith(color: ink?.withValues(alpha: 0.55))),
      ],
    );
  }
}

/// A circular icon action. Lives on a hero, or anywhere a verb needs a shape.
class SkCircleAction extends StatelessWidget {
  const SkCircleAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.identifier,
    this.size = 46,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String identifier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return Semantics(
      identifier: identifier,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: ink.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.45, color: ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// A stadium tag — for filters, meal pickers, recent foods.
class SkPill extends StatelessWidget {
  const SkPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.identifier,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? identifier;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Material(
      color: selected ? SakamaPalette.accent : scheme.onSurface.withValues(alpha: 0.07),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sk.lg, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected ? SakamaPalette.onAccent : scheme.onSurface),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? SakamaPalette.onAccent : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      )),
            ],
          ),
        ),
      ),
    );
    return identifier == null
        ? pill
        : Semantics(identifier: identifier!, button: true, child: pill);
  }
}

/// A consistent empty state: shape, sentence, one action.
class SkEmpty extends StatelessWidget {
  const SkEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.identifier,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final content = Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: Sk.lg),
        Text(title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        if (actionLabel != null) ...[
          const SizedBox(height: Sk.xl),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sk.xl, vertical: Sk.xxl),
      child: identifier == null
          ? content
          : Semantics(identifier: identifier!, child: content),
    );
  }
}

/// A large screen title, matching the reference's oversized headers.
class SkTitle extends StatelessWidget {
  const SkTitle(this.text, {super.key, this.trailing});

  final String text;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sk.xs, Sk.sm, Sk.xs, Sk.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -1)),
            ),
            ...?trailing,
          ],
        ),
      );
}
