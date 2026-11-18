import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// The app's basic unit of information: a label, a value, and enough context
/// to know whether the value is good.
///
/// A battery app is read in glances, so the value is the largest thing in the
/// card and the label sits above it rather than below. Colour is used only to
/// carry meaning from [AppColors]'s severity ramp — never for decoration —
/// which is why [accent] is optional and defaults to plain text.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.icon,
    this.accent,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  final String label;
  final String value;

  /// Shown smaller, next to the value. Pass the unit here rather than in
  /// [value] so the figure itself stays the dominant element.
  final String? unit;

  /// One short line under the value: what it means, or why it is missing.
  final String? caption;

  final IconData? icon;
  final Color? accent;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(dense ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: accent ?? theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ?trailing,
                ],
              ),
              SizedBox(height: dense ? 8 : 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: AppTheme.numeric(
                        context,
                        size: dense ? 24 : 30,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: dense ? 12 : 14,
                      ),
                    ),
                  ],
                ],
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of label and value, for the dense specification lists.
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.caption,
    this.icon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(caption!, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A short status pill: confidence, charge speed, a warning.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a screen shows when it has nothing to show yet.
///
/// Used in place of a spinner or an empty chart, because for this app "no data
/// yet" is a normal state that lasts hours or days, and the user needs to know
/// it is expected rather than broken.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
