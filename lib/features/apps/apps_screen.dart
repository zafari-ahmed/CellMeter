import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repository/battery_repository.dart';
import 'app_usage_list.dart';
import '../../shared/widgets/metric_card.dart';

/// Which apps the battery went to.
///
/// The screen is unusually explicit about its own limits, and that is
/// deliberate. Android does not let an app measure another app's energy use;
/// what CellMeter can do is measure the charge the battery actually lost and
/// divide it by the time each app spent in the foreground. The result is
/// genuinely useful and genuinely not the same thing as a per-app wattage, and
/// saying so is what separates a measurement from a guess dressed up as one.
class AppsScreen extends ConsumerWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(appUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Apps')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).refreshNow(),
        child: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Error(error: error),
          data: (data) => data.hasAccess
              ? _Breakdown(report: data)
              : const _NeedsPermission(),
        ),
      ),
    );
  }
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown({required this.report});

  final AppUsageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final icons = ref.watch(appIconsProvider).value ?? const {};

    if (report.isEmpty) {
      // "Plugged in the whole time" and "used the phone but nothing to
      // attribute" are different situations with different fixes, and telling
      // someone to wait when the real answer is "unplug it" is the kind of
      // empty state that makes an app look broken.
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: report.hasDischargeData
                ? Icons.apps_rounded
                : Icons.power_rounded,
            title: report.hasDischargeData
                ? 'No screen time to attribute yet'
                : 'Nothing has been used yet',
            message: report.hasDischargeData
                ? 'The battery has only dropped while the screen was off, so '
                    'no app accounts for it. Use the phone for a few minutes '
                    'and the breakdown will appear.'
                : 'Your phone has been charging the whole time CellMeter has '
                    'been watching. Unplug it and use it for a few minutes, '
                    'and the apps you used will appear here.',
          ),
        ],
      );
    }

    // Without a discharge to divide up, the figures are foreground time and
    // nothing more. Saying so plainly is the difference between a weaker
    // claim and a false one.
    if (!report.isAttributed) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.hasDischargeData
                        ? 'Your phone has barely run on battery yet, so there '
                            'is nothing to divide up. This is screen time '
                            'only — battery figures appear once CellMeter has '
                            'watched a longer discharge.'
                        : 'Your phone has been charging the whole time, so '
                            'there is no battery use to attribute. This is '
                            'screen time only.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Time on screen',
            subtitle: 'Last 24 hours',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: AppUsageList(
                apps: report.apps,
                icons: icons,
                isAttributed: false,
                valueOf: (a) => a.foreground.inSeconds.toDouble(),
                valueLabel: (a) => Units.duration(a.foreground),
                captionOf: (a) => 'Tap for details and settings',
              ),
            ),
          ),
          const SizedBox(height: 20),
          _MethodNote(),
        ],
      );
    }

    final total = report.apps.fold<double>(
      0,
      (sum, app) => sum + (app.attributedPct ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST 24 HOURS',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        value: Units.percent(total, decimals: 1),
                        label: 'used by apps on screen',
                        color: AppColors.info,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _Figure(
                        value: Units.percent(
                          report.unattributedPct,
                          decimals: 1,
                        ),
                        label: 'standby and background',
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(
          title: 'By battery used',
          subtitle: 'Charge lost while each app was the one on screen',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AppUsageList(
              apps: report.apps,
              icons: icons,
              isAttributed: true,
              valueOf: (a) => a.attributedPct ?? 0,
              valueLabel: (a) => Units.percent(a.attributedPct, decimals: 1),
              captionOf: (a) => _caption(a.foreground, a.attributedMah),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _MethodNote(),
      ],
    );
  }

  String _caption(Duration foreground, double? mah) {
    final parts = <String>['${Units.duration(foreground)} on screen'];
    if (mah != null) parts.add(Units.mah(mah));
    return parts.join(' · ');
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// States plainly what the numbers above do and do not mean.
class _MethodNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
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
                Icons.info_outline_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('How this is worked out',
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'CellMeter measures exactly how much charge the battery lost, then '
            'divides it between apps by how long each was on screen.\n\n'
            'So these figures cover the time an app was in front, including '
            'the display and radio it was using — not the app in isolation. '
            'Work an app does in the background cannot be attributed by any '
            'app on Android, so it stays in "standby and background".',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NeedsPermission extends ConsumerWidget {
  const _NeedsPermission();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 40),
        EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Usage access is needed',
          message: 'To work out which apps used the battery, CellMeter needs '
              'to know which app was on screen. Android keeps that behind a '
              'permission you grant in Settings.',
          action: FilledButton.icon(
            onPressed: () async {
              await ref.read(batteryChannelProvider).openUsageAccessSettings();
              ref.invalidate(usageAccessProvider);
              ref.invalidate(appUsageProvider);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open Settings'),
          ),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What CellMeter does with it',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'It reads only how long each app was in the foreground, and '
                  'only on this device. Nothing is uploaded, and CellMeter '
                  'never sees what you did inside an app.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text('Where to find it', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Settings → Apps → Special app access → Usage access → '
                  'CellMeter. The exact path varies between manufacturers.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load app usage',
            message: '$error',
          ),
        ],
      );
}
