import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A collapsible settings group.
///
/// The point of collapsing is not to hide things, it is to let the screen be
/// read at a glance. So every section carries a [summary] stating its current
/// setting while collapsed — "At 80%", "Recording", "2 of 3 on" — and the
/// controls appear only when someone wants to change something. A settings
/// screen where you must open six panels to learn what the app is doing would
/// be worse than the flat list it replaced.
///
/// Sections open independently rather than as a single-open accordion, because
/// comparing two groups (the drain threshold against the charge limit) is a
/// real thing people do here.
///
/// Everything in this file is deliberately sized down from Material's
/// defaults. Those defaults are tuned for a sparse preferences screen with a
/// handful of rows; this one is dense and technical, and at default sizing a
/// single section filled the screen and the page read as a stack of oversized
/// slabs rather than a settings list.
class SettingsAccordion extends StatefulWidget {
  const SettingsAccordion({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.children,
    this.accent,
    this.initiallyExpanded = false,
    this.warning = false,
  });

  final IconData icon;
  final String title;

  /// The current state of this group, shown while collapsed.
  final String summary;

  final List<Widget> children;
  final Color? accent;
  final bool initiallyExpanded;

  /// Draws attention to a section needing the user to do something.
  final bool warning;

  @override
  State<SettingsAccordion> createState() => _SettingsAccordionState();
}

class _SettingsAccordionState extends State<SettingsAccordion> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.warning
        ? AppColors.accent
        : (widget.accent ?? AppColors.primary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(widget.icon, size: 17, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              height: 1.25,
                              color: widget.warning
                                  ? AppColors.accent
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // AnimatedSize rather than a cross-fade: body heights vary a lot
            // between sections, so sliding the card open reads as the panel
            // growing rather than as content being swapped.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(
                          height: 1,
                          indent: 14,
                          endIndent: 14,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 4),
                        ...widget.children,
                        const SizedBox(height: 8),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact switch row.
///
/// Hand-built rather than a [SwitchListTile] because that control enforces a
/// 56dp minimum height and Material's full-size switch, which together make a
/// three-toggle section taller than the screen.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Material's switch is sized for a sparse preferences screen.
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled slider with its current value, for thresholds.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.note,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  /// One line explaining the trade-off at the chosen value.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                ),
              ),
              Text(
                valueLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              // The tick marks are decoration on a 20-division slider and
              // only add visual noise at this size.
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An action or navigation row inside a section.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  leading,
                  size: 17,
                  color: titleColor ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
