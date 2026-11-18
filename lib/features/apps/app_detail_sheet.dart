import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/analytics/app_attributor.dart';
import '../../domain/analytics/drain_analyzer.dart';
import '../../shared/widgets/app_dialog.dart';

/// What CellMeter knows about one app, and what can actually be done about it.
///
/// The explanation is the point of this sheet. "This app used 12% of your
/// battery" invites the conclusion that the app is misbehaving, and for a
/// foreground app that is almost never true — the screen is on, and the
/// display costs roughly the same per hour whatever is being displayed. So the
/// sheet separates the two: what any app costs simply by holding the screen,
/// and what is left over.
class AppDetailSheet extends ConsumerStatefulWidget {
  const AppDetailSheet({
    super.key,
    required this.app,
    required this.icon,
    required this.isAttributed,
  });

  final AppConsumption app;
  final Uint8List? icon;

  /// False when the figures are foreground time only, with no discharge to
  /// divide up. The explanation changes completely.
  final bool isAttributed;

  static Future<void> show(
    BuildContext context, {
    required AppConsumption app,
    required Uint8List? icon,
    required bool isAttributed,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => AppDetailSheet(
          app: app,
          icon: icon,
          isAttributed: isAttributed,
        ),
      );

  @override
  ConsumerState<AppDetailSheet> createState() => _AppDetailSheetState();
}

class _AppDetailSheetState extends ConsumerState<AppDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drain = ref.watch(drainProfileProvider).value ?? DrainProfile.empty;
    final capabilities =
        ref.watch(appCapabilitiesProvider(widget.app.packageName)).value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme),
            const SizedBox(height: 18),
            _figures(theme),
            const SizedBox(height: 18),
            _explanation(theme, drain),
            const SizedBox(height: 18),
            _actions(theme, capabilities),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) => Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.icon != null
                ? Image.memory(widget.icon!, fit: BoxFit.contain)
                : Icon(
                    Icons.android_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.app.label,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.app.packageName,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );

  Widget _figures(ThemeData theme) => Row(
        children: [
          Expanded(
            child: _figure(
              theme,
              value: Units.duration(widget.app.foreground),
              label: 'on screen',
              color: AppColors.info,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: _figure(
              theme,
              value: widget.isAttributed
                  ? Units.percent(widget.app.attributedPct, decimals: 1)
                  : '—',
              label: widget.isAttributed ? 'of your battery' : 'not measured',
              color: AppColors.primary,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: _figure(
              theme,
              value: widget.isAttributed
                  ? Units.mah(widget.app.attributedMah)
                  : '—',
              label: 'charge used',
              color: AppColors.accent,
            ),
          ),
        ],
      );

  Widget _figure(
    ThemeData theme, {
    required String value,
    required String label,
    required Color color,
  }) =>
      Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
        ],
      );

  /// The "why is this so high" section.
  ///
  /// Built from the user's own measured screen-on and standby rates rather
  /// than from anything about the app, because that is what the data supports
  /// — and because the answer is usually "you looked at your phone", not
  /// "this app is broken". Where that is *not* the answer, the comparison
  /// makes it visible.
  Widget _explanation(ThemeData theme, DrainProfile drain) {
    final hours = widget.app.foreground.inMilliseconds / 3600000;
    final screenOn = drain.screenOnPctPerHour;
    final standby = drain.screenOffPctPerHour;

    final lines = <String>[];

    if (!widget.isAttributed) {
      lines.add(
        'Your phone has barely run on battery while CellMeter has been '
        'watching, so there is no consumption to divide up yet. This is time '
        'on screen only.',
      );
    } else if (screenOn != null && hours > 0) {
      final screenCost = screenOn * hours;
      final attributed = widget.app.attributedPct ?? 0;

      lines.add(
        'You had it open for ${Units.durationLong(widget.app.foreground)}.',
      );
      lines.add(
        'With the screen on, this phone uses about '
        '${Units.percentPerHour(screenOn)} no matter which app is showing — '
        'most of that is the display itself'
        '${standby != null ? ', against ${Units.percentPerHour(standby)} '
            'asleep' : ''}.',
      );

      if (screenCost >= attributed * 0.8) {
        lines.add(
          'So almost all of this ${Units.percent(attributed, decimals: 1)} is '
          'simply screen time. Using it less, or dimming the screen, will do '
          'far more than anything you can do to the app.',
        );
      } else {
        lines.add(
          'Screen time alone accounts for roughly '
          '${Units.percent(screenCost, decimals: 1)} of it, so this app does '
          'appear to be doing more than just being on screen.',
        );
      }
    } else {
      lines.add(
        'You had it open for ${Units.durationLong(widget.app.foreground)}. '
        'CellMeter needs a longer discharge before it can say how much of '
        'your battery that cost.',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Why this much', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _actions(ThemeData theme, AppCapabilitiesState? capabilities) {
    final channel = ref.read(batteryChannelProvider);
    final package = widget.app.packageName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What you can do', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // Said plainly rather than hidden: a "Close app" button here would be
        // theatre, and the user deserves to know where the real control is.
        Text(
          'Android does not let one app force-stop another. CellMeter opens '
          'the system page where Force stop and background limits live.',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              await channel.openAppSettings(package);
              if (mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.tune_rounded, size: 19),
            label: const Text('Force stop & battery settings'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (capabilities?.canLaunch ?? false) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await channel.launchApp(package);
                    if (mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (capabilities?.canUninstall ?? false)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmUninstall(channel, package),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.critical,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Uninstall'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmUninstall(dynamic channel, String package) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Uninstall ${widget.app.label}?',
      message: 'Android will ask you to confirm. CellMeter cannot remove an '
          'app on its own.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await channel.requestUninstall(package);
    if (mounted) Navigator.pop(context);
  }
}
