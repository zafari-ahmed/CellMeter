import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/native/battery_channel.dart';
import '../../data/native/native_models.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/settings_accordion.dart';

/// Settings.
///
/// Every group is collapsed by default and states its current setting in the
/// header, so the whole screen can be read without opening anything. Controls
/// appear only when someone wants to change something, which is the minority
/// of visits to this screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(monitorSettingsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _MonitoringSection(settings: settings),
                _ChargeAlarmSection(settings: settings),
                _AlertsSection(settings: settings),
                const _WidgetsSection(),
                const _DiagnosticsSection(),
                const _AboutSection(),
              ],
            ),
    );
  }
}

class _MonitoringSection extends ConsumerWidget {
  const _MonitoringSection({required this.settings});

  final MonitorSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(monitorSettingsProvider.notifier);
    final prefsController = ref.read(appPreferencesProvider.notifier);
    final useFahrenheit =
        ref.watch(appPreferencesProvider).value?.useFahrenheit ?? false;
    final unrestricted = ref.watch(batteryOptimizationProvider).value;

    final restricted = unrestricted == false;

    return SettingsAccordion(
      icon: Icons.sensors_rounded,
      title: 'Monitoring',
      // The header has to say whether the app is actually doing its job.
      summary: !settings.monitoringEnabled
          ? 'Paused — nothing is being recorded'
          : restricted
              ? 'Recording, but Android may suspend it'
              : 'Recording',
      warning: settings.monitoringEnabled && restricted,
      children: [
        SettingsSwitch(
          title: 'Record battery data',
          subtitle: 'Keeps a background service running so charges are '
              'measured without gaps',
          value: settings.monitoringEnabled,
          onChanged: controller.setMonitoring,
        ),
        SettingsSwitch(
          title: 'Live figures in the notification',
          subtitle: 'Current, temperature and voltage at a glance',
          value: settings.showStatsInNotification,
          onChanged: (value) =>
              controller.edit((s) => s.copyWith(showStatsInNotification: value)),
        ),
        SettingsSwitch(
          title: 'Show temperature in Fahrenheit',
          value: useFahrenheit,
          onChanged: prefsController.setUseFahrenheit,
        ),
        SettingsRow(
          leading: restricted
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          title: 'Background restrictions',
          subtitle: restricted
              ? 'Android may suspend monitoring and leave gaps in overnight '
                  'charges'
              : 'CellMeter is allowed to run unrestricted',
          trailing: restricted
              ? const Icon(Icons.chevron_right_rounded, size: 20)
              : null,
          onTap: restricted
              ? () async {
                  await ref
                      .read(batteryChannelProvider)
                      .requestIgnoreBatteryOptimizations();
                  ref.invalidate(batteryOptimizationProvider);
                }
              : null,
        ),
      ],
    );
  }
}

/// The charge alarm.
///
/// Framed around wear rather than around the alarm, because the setting only
/// makes sense if you know why you would want it: a lithium cell held at a
/// high state of charge ages faster, so stopping at 80–90% trades a little
/// runtime for a longer-lived battery.
class _ChargeAlarmSection extends ConsumerWidget {
  const _ChargeAlarmSection({required this.settings});

  final MonitorSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(monitorSettingsProvider.notifier);

    return SettingsAccordion(
      icon: Icons.notifications_active_rounded,
      title: 'Charge alarm',
      summary: settings.chargeAlarmEnabled
          ? 'Alert at ${settings.chargeAlarmPct}%'
          : 'Off',
      accent: AppColors.accent,
      children: [
        SettingsSwitch(
          title: 'Alert me at a charge limit',
          subtitle: 'Stopping short of 100% slows how fast a battery wears',
          value: settings.chargeAlarmEnabled,
          onChanged: (value) =>
              controller.edit((s) => s.copyWith(chargeAlarmEnabled: value)),
        ),
        if (settings.chargeAlarmEnabled)
          SettingsSlider(
            label: 'Notify at',
            valueLabel: '${settings.chargeAlarmPct}%',
            value: settings.chargeAlarmPct.toDouble(),
            min: 50,
            max: 100,
            divisions: 10,
            note: _alarmAdvice(settings.chargeAlarmPct),
            onChanged: (value) => controller
                .edit((s) => s.copyWith(chargeAlarmPct: value.round())),
          ),
      ],
    );
  }

  /// Honest about the trade-off at each setting rather than pushing one.
  String _alarmAdvice(int pct) {
    if (pct >= 100) {
      return 'Charging to 100% every time is the hardest setting on a lithium '
          'battery, though it does give you the most runtime.';
    }
    if (pct >= 90) return 'A gentle limit. Small gain in battery life.';
    if (pct >= 80) {
      return 'The usual recommendation: a worthwhile reduction in wear for a '
          'fifth less runtime.';
    }
    return 'Very protective. Only worth it if the phone is usually near a '
        'charger.';
  }
}

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection({required this.settings});

  final MonitorSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(monitorSettingsProvider.notifier);
    final useFahrenheit =
        ref.watch(appPreferencesProvider).value?.useFahrenheit ?? false;

    final on = [
      settings.highDrainEnabled,
      settings.lowBatteryEnabled,
      settings.temperatureAlertEnabled,
    ].where((e) => e).length;

    return SettingsAccordion(
      icon: Icons.campaign_rounded,
      title: 'Alerts',
      summary: on == 0 ? 'All off' : '$on of 3 on',
      accent: AppColors.info,
      children: [
        SettingsSwitch(
          title: 'High battery drain',
          subtitle: settings.highDrainEnabled
              ? 'Above ${settings.highDrainPctPerHour.round()}% per hour for '
                  '${settings.highDrainSustainMinutes} minutes'
              : 'Off',
          value: settings.highDrainEnabled,
          onChanged: (value) =>
              controller.edit((s) => s.copyWith(highDrainEnabled: value)),
        ),
        if (settings.highDrainEnabled)
          SettingsSlider(
            label: 'Threshold',
            valueLabel: '${settings.highDrainPctPerHour.round()}%/h',
            value: settings.highDrainPctPerHour,
            min: 5,
            max: 50,
            divisions: 9,
            note: 'Measured over a window rather than from a momentary '
                'reading, so a brief spike will not set it off.',
            onChanged: (value) =>
                controller.edit((s) => s.copyWith(highDrainPctPerHour: value)),
          ),
        SettingsSwitch(
          title: 'Low battery',
          subtitle: settings.lowBatteryEnabled
              ? 'At ${settings.lowBatteryPct}%'
              : 'Off',
          value: settings.lowBatteryEnabled,
          onChanged: (value) =>
              controller.edit((s) => s.copyWith(lowBatteryEnabled: value)),
        ),
        if (settings.lowBatteryEnabled)
          SettingsSlider(
            label: 'Notify at',
            valueLabel: '${settings.lowBatteryPct}%',
            value: settings.lowBatteryPct.toDouble(),
            min: 5,
            max: 50,
            divisions: 9,
            onChanged: (value) => controller
                .edit((s) => s.copyWith(lowBatteryPct: value.round())),
          ),
        SettingsSwitch(
          title: 'High temperature',
          subtitle: settings.temperatureAlertEnabled
              ? 'At ${Units.temperature(
                  settings.temperatureAlertC,
                  useFahrenheit: useFahrenheit,
                )}'
              : 'Off',
          value: settings.temperatureAlertEnabled,
          onChanged: (value) =>
              controller.edit((s) => s.copyWith(temperatureAlertEnabled: value)),
        ),
        if (settings.temperatureAlertEnabled)
          SettingsSlider(
            label: 'Warn above',
            valueLabel: Units.temperature(
              settings.temperatureAlertC,
              useFahrenheit: useFahrenheit,
            ),
            value: settings.temperatureAlertC,
            min: 35,
            max: 55,
            divisions: 20,
            note: 'Sustained heat is the fastest way to wear a cell out.',
            onChanged: (value) =>
                controller.edit((s) => s.copyWith(temperatureAlertC: value)),
          ),
      ],
    );
  }
}

/// Home screen widgets.
///
/// Android never lets an app place a widget by itself, so this is an offer
/// rather than a switch. On launchers that support pinning the button opens
/// the system's own add-widget dialog; where it is unsupported it shows how to
/// add it from the widget picker, which always works.
class _WidgetsSection extends ConsumerWidget {
  const _WidgetsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(widgetStatusProvider).value;
    final canPin = status?.canPin ?? false;

    return SettingsAccordion(
      icon: Icons.widgets_rounded,
      title: 'Home screen',
      summary: status?.hasPlacedWidgets == true
          ? 'Widget added'
          : 'Add a widget to your home screen',
      children: [
        SettingsRow(
          leading: Icons.battery_charging_full_rounded,
          title: 'Battery widget',
          subtitle: 'Level, current, temperature and time remaining. Resize '
              'from a compact readout to a full panel.',
          trailing: const Icon(Icons.add_rounded, size: 20),
          onTap: () => _add(context, ref, WidgetKind.battery, canPin),
        ),
        SettingsRow(
          leading: Icons.favorite_outline_rounded,
          title: 'Health widget',
          subtitle: 'Measured capacity and health at 2×2.',
          trailing: const Icon(Icons.add_rounded, size: 20),
          onTap: () => _add(context, ref, WidgetKind.health, canPin),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Widgets keep the CellMeter colours rather than following the app '
            'theme or your wallpaper, so a glance means the same thing '
            'everywhere.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    WidgetKind kind,
    bool canPin,
  ) async {
    if (canPin) {
      final shown =
          await ref.read(batteryChannelProvider).requestPinWidget(kind: kind);
      ref.invalidate(widgetStatusProvider);
      if (shown) return;
    }
    if (!context.mounted) return;
    await AppDialog.inform(
      context,
      title: 'Add it from the home screen',
      message: 'Press and hold an empty part of your home screen, choose '
          'Widgets, find CellMeter, then drag the '
          '${kind.label.toLowerCase()} where you want it.\n\n'
          'The exact wording varies between launchers.',
    );
  }
}

/// What this device actually reports.
///
/// Design capacity lives here rather than in a section of its own: it is
/// detected automatically from the device, and what the user needs is to see
/// which figure health is being measured against, not to manage it.
class _DiagnosticsSection extends ConsumerWidget {
  const _DiagnosticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(databaseStatsProvider).value;
    final device = ref.watch(deviceInfoProvider).value;
    final design = ref.watch(designCapacityProvider).value;
    final snapshot = ref.watch(liveSnapshotProvider).value;

    return SettingsAccordion(
      icon: Icons.memory_rounded,
      title: 'Diagnostics',
      summary: device?.displayName ?? 'What this device reports',
      accent: AppColors.info,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              MetricRow(
                dense: true,
                label: 'Device',
                value: device?.displayName ?? Units.unavailable,
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Android',
                value: device == null
                    ? Units.unavailable
                    : '${device.release} (API ${device.sdkInt})',
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Design capacity',
                value: Units.mah(design?.mah),
                caption: design?.isKnown ?? false
                    ? design!.source.label
                    : 'Not reported by this device, so health cannot be '
                        'shown as a percentage',
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Charge counter',
                value: snapshot?.chargeCounterUah == null
                    ? 'Not reported'
                    : Units.capacityMah(snapshot!.chargeCounterUah),
                caption: 'The basis of capacity measurement',
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Current sensor',
                value: snapshot?.currentNowUa == null
                    ? 'Not reported'
                    : Units.currentMaSigned(snapshot!.currentNowUa),
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Battery technology',
                value: snapshot?.technology ?? Units.unavailable,
              ),
              const Divider(height: 1),
              MetricRow(
                dense: true,
                label: 'Readings stored',
                value: Units.count(stats?.sampleCount),
                caption: stats == null
                    ? null
                    : '${Units.count(stats.sessionCount)} sessions, '
                        '${Units.bytes(stats.spoolBytes)} waiting',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsRow(
          leading: Icons.build_rounded,
          title: 'Rebuild analysis from raw readings',
          subtitle: 'Re-derives every session from the stored samples',
          onTap: () async {
            await ref.read(syncControllerProvider.notifier).rebuildEverything();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sessions rebuilt from stored readings.'),
                ),
              );
            }
          },
        ),
        // The only way back to a clean slate. Kept out of the way rather than
        // removed: a measurement history can be made meaningless by a battery
        // service, a factory reset restoring a backup, or simply bad early
        // data, and without this the median would carry that for months.
        SettingsRow(
          leading: Icons.delete_outline_rounded,
          title: 'Reset measurement data',
          subtitle: 'Deletes all readings and starts measuring again',
          titleColor: AppColors.critical,
          onTap: () => _confirmReset(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Reset measurement data?',
      message: 'This permanently deletes every recorded reading, session and '
          'capacity estimate, and CellMeter starts measuring from scratch.\n\n'
          'It cannot be undone.',
      confirmLabel: 'Delete and restart',
      destructive: true,
    );
    if (!confirmed) return;

    await ref.read(batteryRepositoryProvider).resetForNewBattery();
    ref.invalidate(capacityEstimateProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(syncControllerProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Measurement data cleared.')),
      );
    }
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SettingsAccordion(
      icon: Icons.info_outline_rounded,
      title: 'About',
      summary: 'Monitor. Analyze. Optimize.',
      accent: AppColors.primary,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'CellMeter measures what your battery really holds by watching it '
            'charge, rather than repeating the figure it shipped with.\n\n'
            'Every measurement stays on this device. There is no account, no '
            'analytics, and no network permission at all.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
