import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/native/native_models.dart';
import '../../domain/analytics/drain_analyzer.dart';
import '../../shared/widgets/battery_gauge.dart';
import '../../shared/widgets/metric_card.dart';

/// The screen the app opens on: what the battery is doing this second, and the
/// two or three figures that explain it.
///
/// Ordered by how often a question gets asked. Level and what it is doing come
/// first; the live electrical readings second; runtime forecasts third. The
/// long-term analysis lives on its own screens, because it answers a question
/// the user asks once a month rather than once an hour.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(liveSnapshotProvider).value;
    final settings = ref.watch(monitorSettingsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CellMeter'),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: () =>
                ref.read(syncControllerProvider.notifier).refreshNow(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).refreshNow(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _Hero(snapshot: snapshot, settings: settings),
            const SizedBox(height: 8),
            _LiveReadings(snapshot: snapshot),
            const _RuntimeSection(),
            const _HealthSummary(),
            const SizedBox(height: 8),
            _DeviceNotice(snapshot: snapshot),
          ],
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.snapshot, required this.settings});

  final BatterySnapshot? snapshot;
  final MonitorSettings? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final charging = snapshot?.isCharging ?? false;

    final toFull = ref.watch(timeToFullProvider).value;
    final toLimit = ref.watch(timeToChargeLimitProvider).value;
    final drain = ref.watch(drainProfileProvider).value ?? DrainProfile.empty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
        child: Column(
          children: [
            BatteryGauge(
              levelPct: snapshot?.levelPct,
              isCharging: charging,
              chargeLimitPct: (settings?.chargeAlarmEnabled ?? false)
                  ? settings?.chargeAlarmPct
                  : null,
              primaryLabel: _statusLine(snapshot),
              secondaryLabel: _forecastLine(
                snapshot: snapshot,
                toFull: toFull,
                toLimit: toLimit,
                limitPct: (settings?.chargeAlarmEnabled ?? false)
                    ? settings?.chargeAlarmPct
                    : null,
                drain: drain,
              ),
            ),
            if (snapshot?.powerSaveMode == true) ...[
              const SizedBox(height: 16),
              const StatusChip(
                label: 'Battery saver is on',
                color: AppColors.accent,
                icon: Icons.energy_savings_leaf_rounded,
              ),
            ],
            if (snapshot?.health.isProblem == true) ...[
              const SizedBox(height: 12),
              StatusChip(
                label: 'Android reports: ${snapshot!.health.label}',
                color: AppColors.critical,
                icon: Icons.warning_amber_rounded,
              ),
            ],
            if (snapshot == null) ...[
              const SizedBox(height: 16),
              Text(
                'Waiting for the first reading',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLine(BatterySnapshot? snapshot) {
    if (snapshot == null) return 'Starting up';
    if (snapshot.isCharging) {
      final plug = snapshot.plugType;
      return plug == PlugType.none || plug == PlugType.unknown
          ? snapshot.status.label
          : 'Charging · ${plug.label}';
    }
    return snapshot.screenOn ? 'In use' : 'Discharging';
  }

  /// One line of forecast, chosen for the situation.
  ///
  /// While charging toward a limit the user has set, the time to that limit is
  /// what they want — telling them when the battery will be full is answering
  /// a question they deliberately stopped asking.
  String? _forecastLine({
    required BatterySnapshot? snapshot,
    required Duration? toFull,
    required Duration? toLimit,
    required int? limitPct,
    required DrainProfile drain,
  }) {
    if (snapshot == null) return null;
    final level = snapshot.levelPct;

    if (snapshot.isCharging) {
      if (toLimit != null && limitPct != null && (level ?? 0) < limitPct) {
        return '${Units.remaining(toLimit)} to $limitPct%';
      }
      if (toFull != null) return '${Units.remaining(toFull)} to full';
      return null;
    }

    if (level == null) return null;
    final runtime = snapshot.screenOn
        ? drain.screenOnRuntime(level)
        : drain.mixedRuntime(level);
    if (runtime == null) return null;

    return snapshot.screenOn
        ? '${Units.remaining(runtime)} of screen time left'
        : '${Units.remaining(runtime)} left at your usual rate';
  }
}

class _LiveReadings extends ConsumerWidget {
  const _LiveReadings({required this.snapshot});

  final BatterySnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useFahrenheit =
        ref.watch(appPreferencesProvider).value?.useFahrenheit ?? false;
    final live = ref.watch(liveDrainProvider).value;
    final current = snapshot?.currentNowUa;
    final temperature = snapshot?.temperatureC;

    return Column(
      children: [
        const SectionHeader(
          title: 'Right now',
          subtitle: 'Read straight from the battery, updated every 2 seconds',
        ),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Current',
                value: current == null
                    ? Units.unavailable
                    : Units.currentMaSigned(current),
                caption: snapshot?.isCharging == true
                    ? 'Going in'
                    : 'Coming out',
                icon: Icons.electric_bolt_rounded,
                accent: current == null
                    ? null
                    : (current > 0 ? AppColors.primary : AppColors.info),
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Power',
                value: Units.watts(snapshot?.powerMw),
                caption: _powerCaption(snapshot),
                icon: Icons.power_rounded,
                dense: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Temperature',
                value: Units.temperature(
                  temperature,
                  useFahrenheit: useFahrenheit,
                ),
                caption: _temperatureCaption(temperature),
                icon: Icons.thermostat_rounded,
                accent: temperature == null
                    ? null
                    : AppColors.forTemperature(temperature),
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Voltage',
                value: Units.volts(snapshot?.voltageMv),
                caption: _voltageCaption(snapshot?.voltageMv),
                icon: Icons.show_chart_rounded,
                dense: true,
              ),
            ),
          ],
        ),
        if (live != null && live.hasData && !(snapshot?.isCharging ?? false)) ...[
          const SizedBox(height: 12),
          MetricCard(
            label: 'Drain over the last ${Units.duration(live.window)}',
            value: Units.percentPerHour(live.pctPerHour),
            caption: _liveDrainCaption(live),
            icon: Icons.trending_down_rounded,
            accent: live.pctPerHour == null
                ? null
                : AppColors.forScore(100 - (live.pctPerHour! * 4)),
          ),
        ],
      ],
    );
  }

  String? _powerCaption(BatterySnapshot? snapshot) {
    final mw = snapshot?.powerMw;
    if (mw == null) return 'Needs current and voltage';
    return snapshot!.isCharging ? 'Delivered by the charger' : 'Being consumed';
  }

  /// Context rather than a bare verdict: the point is that sustained heat is
  /// what wears a cell, not that 39 °C right now is an emergency.
  String? _temperatureCaption(double? celsius) {
    if (celsius == null) return 'Not reported';
    if (celsius >= 45) return 'Very hot — this shortens battery life';
    if (celsius >= 40) return 'Warm — fine briefly, not for hours';
    if (celsius <= 5) return 'Cold — capacity drops temporarily';
    return 'Comfortable range';
  }

  String? _voltageCaption(int? mv) {
    if (mv == null) return 'Not reported';
    if (mv >= 4300) return 'Near the top of the charge';
    if (mv <= 3500) return 'Running low';
    return 'Normal';
  }

  String _liveDrainCaption(LiveDrain live) {
    final share = live.screenOnShare;
    final parts = <String>[];
    if (live.averageMa != null) {
      parts.add('${Units.currentMa(live.averageMa! * 1000)} average');
    }
    if (share != null) {
      parts.add(share > 0.6
          ? 'mostly with the screen on'
          : share < 0.1
              ? 'with the screen off'
              : 'mixed screen use');
    }
    return parts.join(', ');
  }
}

class _RuntimeSection extends ConsumerWidget {
  const _RuntimeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drain = ref.watch(drainProfileProvider).value;
    final level = ref.watch(liveSnapshotProvider).value?.levelPct;

    if (drain == null || !drain.hasData || level == null) {
      return const SizedBox.shrink();
    }

    final screenOn = drain.screenOnRuntime(level);
    final standby = drain.standbyRuntime(level);

    return Column(
      children: [
        const SectionHeader(
          title: 'How long this charge lasts',
          subtitle: 'Measured from how you actually use this phone',
        ),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Screen on',
                value: Units.duration(screenOn),
                caption: drain.screenOnPctPerHour == null
                    ? null
                    : 'at ${Units.percentPerHour(drain.screenOnPctPerHour)}',
                icon: Icons.smartphone_rounded,
                accent: AppColors.info,
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Standby',
                value: Units.duration(standby),
                caption: drain.screenOffPctPerHour == null
                    ? null
                    : 'at ${Units.percentPerHour(drain.screenOffPctPerHour)}',
                icon: Icons.bedtime_rounded,
                accent: AppColors.primary,
                dense: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HealthSummary extends ConsumerWidget {
  const _HealthSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final estimate = ref.watch(capacityEstimateProvider).value;

    if (estimate == null || estimate.isEmpty) {
      return Column(
        children: [
          const SectionHeader(title: 'Battery health'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.science_rounded, color: AppColors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Still measuring',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Charge your phone by 20% or more in one go and '
                          'CellMeter will measure what the battery really '
                          'holds. It does not need a full charge.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final health = estimate.healthPct;

    return Column(
      children: [
        SectionHeader(
          title: 'Battery health',
          action: StatusChip(
            label: estimate.confidence.label,
            color: switch (estimate.confidence.index) {
              2 => AppColors.primary,
              1 => AppColors.accent,
              _ => theme.colorScheme.onSurfaceVariant,
            },
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Units.percent(health),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: health == null
                                  ? null
                                  : AppColors.forScore(health),
                            ),
                          ),
                          Text(
                            'of its original capacity',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Units.mah(estimate.estimatedMah),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          estimate.designMah == null
                              ? 'measured'
                              : 'of ${Units.mah(estimate.designMah)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                HealthBar(healthPct: health),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Surfaces the two settings that decide whether the app can do its job.
///
/// Shown on the dashboard rather than buried in settings because a sampler
/// that Doze keeps suspending produces exactly the symptom users blame the app
/// for: charge sessions that mysteriously do not count.
class _DeviceNotice extends ConsumerWidget {
  const _DeviceNotice({required this.snapshot});

  final BatterySnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final optimised = ref.watch(batteryOptimizationProvider).value;
    final monitoring =
        ref.watch(monitorSettingsProvider).value?.monitoringEnabled ?? true;

    final issues = <Widget>[];

    if (!monitoring) {
      issues.add(
        _NoticeTile(
          icon: Icons.pause_circle_outline_rounded,
          color: AppColors.accent,
          title: 'Monitoring is paused',
          message: 'Nothing is being recorded while this is off.',
          actionLabel: 'Resume',
          onAction: () => ref
              .read(monitorSettingsProvider.notifier)
              .setMonitoring(true),
        ),
      );
    }

    if (optimised == false) {
      issues.add(
        _NoticeTile(
          icon: Icons.battery_alert_rounded,
          color: AppColors.accent,
          title: 'Android may suspend monitoring',
          message: 'Allow CellMeter to run unrestricted so overnight charges '
              'are measured without gaps.',
          actionLabel: 'Allow',
          onAction: () => ref
              .read(batteryChannelProvider)
              .requestIgnoreBatteryOptimizations(),
        ),
      );
    }

    if (issues.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
          child: Text('Needs your attention', style: theme.textTheme.titleMedium),
        ),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: issue,
          ),
      ],
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
