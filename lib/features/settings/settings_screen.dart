import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/native/battery_channel.dart';
import '../../data/native/native_models.dart';
import '../../shared/widgets/metric_card.dart';

/// Settings, alerts and diagnostics.
///
/// Alert thresholds sit at the top because they are the controls people come
/// here to change; diagnostics sit at the bottom because they are the controls
/// people come here to find when something looks wrong.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(monitorSettingsProvider).value;
    final prefs = ref.watch(appPreferencesProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null || prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _MonitoringSection(settings: settings),
                _ChargeAlarmSection(settings: settings),
                _AlertsSection(settings: settings),
                _AppearanceSection(prefs: prefs),
                const _WidgetsSection(),
                const _BatterySection(),
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
    final unrestricted = ref.watch(batteryOptimizationProvider).value;

    return Column(
      children: [
        const SectionHeader(title: 'Monitoring'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.monitoringEnabled,
                onChanged: controller.setMonitoring,
                title: const Text('Record battery data'),
                subtitle: const Text(
                  'Keeps a background service running so charges are measured '
                  'without gaps',
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.showStatsInNotification,
                onChanged: (value) => controller.edit(
                  (s) => s.copyWith(showStatsInNotification: value),
                ),
                title: const Text('Live figures in the notification'),
                subtitle: const Text(
                  'Show current, temperature and voltage at a glance',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  unrestricted == true
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: unrestricted == true
                      ? AppColors.primary
                      : AppColors.accent,
                ),
                title: const Text('Background restrictions'),
                subtitle: Text(
                  unrestricted == true
                      ? 'CellMeter is allowed to run unrestricted'
                      : 'Android may suspend monitoring and leave gaps in '
                          'overnight charges',
                ),
                trailing: unrestricted == true
                    ? null
                    : const Icon(Icons.chevron_right_rounded),
                onTap: unrestricted == true
                    ? null
                    : () async {
                        await ref
                            .read(batteryChannelProvider)
                            .requestIgnoreBatteryOptimizations();
                        ref.invalidate(batteryOptimizationProvider);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The charge alarm.
///
/// Framed around wear rather than around the alarm itself, because the setting
/// only makes sense if you know why you would want it: a lithium cell held at
/// a high state of charge ages faster, so stopping at 80–90% trades a little
/// runtime for a longer-lived battery.
class _ChargeAlarmSection extends ConsumerWidget {
  const _ChargeAlarmSection({required this.settings});

  final MonitorSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(monitorSettingsProvider.notifier);

    return Column(
      children: [
        const SectionHeader(
          title: 'Charge alarm',
          subtitle: 'Stopping short of 100% slows how fast a battery wears',
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.chargeAlarmEnabled,
                onChanged: (value) => controller.edit(
                  (s) => s.copyWith(chargeAlarmEnabled: value),
                ),
                title: const Text('Alert me at a charge limit'),
                secondary: const Icon(Icons.notifications_active_rounded),
              ),
              if (settings.chargeAlarmEnabled) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notify at',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '${settings.chargeAlarmPct}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: settings.chargeAlarmPct.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 10,
                  label: '${settings.chargeAlarmPct}%',
                  onChanged: (value) => controller.edit(
                    (s) => s.copyWith(chargeAlarmPct: value.round()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Text(
                    _alarmAdvice(settings.chargeAlarmPct),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Honest about the trade-off at each setting rather than pushing one.
  String _alarmAdvice(int pct) {
    if (pct >= 100) {
      return 'Charging to 100% every time is the hardest setting on a '
          'lithium battery, though it does give you the most runtime.';
    }
    if (pct >= 90) return 'A gentle limit. Small gain in battery life.';
    if (pct >= 80) {
      return 'The usual recommendation: a worthwhile reduction in wear for '
          'a fifth less runtime.';
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
    final theme = Theme.of(context);
    final controller = ref.read(monitorSettingsProvider.notifier);
    final useFahrenheit =
        ref.watch(appPreferencesProvider).value?.useFahrenheit ?? false;

    return Column(
      children: [
        const SectionHeader(title: 'Alerts'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: settings.highDrainEnabled,
                onChanged: (value) => controller.edit(
                  (s) => s.copyWith(highDrainEnabled: value),
                ),
                title: const Text('High battery drain'),
                subtitle: Text(
                  settings.highDrainEnabled
                      ? 'Above ${settings.highDrainPctPerHour.round()}% per '
                          'hour for ${settings.highDrainSustainMinutes} minutes'
                      : 'Off',
                ),
                secondary: const Icon(Icons.trending_down_rounded),
              ),
              if (settings.highDrainEnabled) ...[
                Slider(
                  value: settings.highDrainPctPerHour,
                  min: 5,
                  max: 50,
                  divisions: 9,
                  label: '${settings.highDrainPctPerHour.round()}%/h',
                  onChanged: (value) => controller.edit(
                    (s) => s.copyWith(highDrainPctPerHour: value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Text(
                    'Measured over a window rather than from a momentary '
                    'reading, so a brief spike will not set it off.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                value: settings.lowBatteryEnabled,
                onChanged: (value) => controller.edit(
                  (s) => s.copyWith(lowBatteryEnabled: value),
                ),
                title: const Text('Low battery'),
                subtitle: Text(
                  settings.lowBatteryEnabled
                      ? 'At ${settings.lowBatteryPct}%'
                      : 'Off',
                ),
                secondary: const Icon(Icons.battery_2_bar_rounded),
              ),
              if (settings.lowBatteryEnabled)
                Slider(
                  value: settings.lowBatteryPct.toDouble(),
                  min: 5,
                  max: 50,
                  divisions: 9,
                  label: '${settings.lowBatteryPct}%',
                  onChanged: (value) => controller.edit(
                    (s) => s.copyWith(lowBatteryPct: value.round()),
                  ),
                ),
              const Divider(height: 1),
              SwitchListTile(
                value: settings.temperatureAlertEnabled,
                onChanged: (value) => controller.edit(
                  (s) => s.copyWith(temperatureAlertEnabled: value),
                ),
                title: const Text('High temperature'),
                subtitle: Text(
                  settings.temperatureAlertEnabled
                      ? 'At ${Units.temperature(
                          settings.temperatureAlertC,
                          useFahrenheit: useFahrenheit,
                        )}'
                      : 'Off',
                ),
                secondary: const Icon(Icons.thermostat_rounded),
              ),
              if (settings.temperatureAlertEnabled)
                Slider(
                  value: settings.temperatureAlertC,
                  min: 35,
                  max: 55,
                  divisions: 20,
                  label: Units.celsius(settings.temperatureAlertC),
                  onChanged: (value) => controller.edit(
                    (s) => s.copyWith(temperatureAlertC: value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection({required this.prefs});

  final AppPreferences prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appPreferencesProvider.notifier);

    return Column(
      children: [
        const SectionHeader(title: 'Appearance'),
        Card(
          child: Column(
            children: [
              RadioGroup<AppThemeMode>(
                groupValue: prefs.themeMode,
                onChanged: (value) {
                  if (value != null) controller.setThemeMode(value);
                },
                child: Column(
                  children: [
                    for (final mode in AppThemeMode.values)
                      RadioListTile<AppThemeMode>(
                        value: mode,
                        title: Text(mode.label),
                        subtitle: mode == AppThemeMode.amoled
                            ? const Text(
                                'True black — unlit pixels use no power on '
                                'OLED screens',
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: prefs.useFahrenheit,
                onChanged: controller.setUseFahrenheit,
                title: const Text('Show temperature in Fahrenheit'),
                secondary: const Icon(Icons.thermostat_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Home screen widgets.
///
/// Android never lets an app place a widget by itself, so this section is an
/// offer rather than a switch. On launchers that support pinning, the button
/// opens the system's own add-widget dialog — one tap instead of five. Where
/// pinning is unsupported, it shows how to add it from the widget picker,
/// which always works.
class _WidgetsSection extends ConsumerWidget {
  const _WidgetsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(widgetStatusProvider).value;
    final canPin = status?.canPin ?? false;

    return Column(
      children: [
        const SectionHeader(
          title: 'Home screen',
          subtitle: 'Widgets keep their own colours, not the app theme',
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Battery widget'),
                subtitle: const Text(
                  'Level, current, temperature and time remaining. Resize it '
                  'from a compact readout to a full panel.',
                ),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => _add(context, ref, WidgetKind.battery, canPin),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.favorite_outline_rounded),
                title: const Text('Health widget'),
                subtitle: const Text(
                  'Measured capacity and health at 2×2.',
                ),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => _add(context, ref, WidgetKind.health, canPin),
              ),
            ],
          ),
        ),
        if (!canPin && status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              'Your launcher does not support adding widgets from inside an '
              'app, so these open instructions instead.',
              style: theme.textTheme.bodySmall,
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
      if (shown) return;
    }
    if (!context.mounted) return;
    await _showManualInstructions(context, kind);
  }

  Future<void> _showManualInstructions(
    BuildContext context,
    WidgetKind kind,
  ) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add it from the home screen'),
          content: Text(
            'Press and hold an empty part of your home screen, choose '
            'Widgets, find CellMeter, then drag the ${kind.label.toLowerCase()} '
            'where you want it.\n\n'
            'The exact wording varies between launchers.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
}

class _BatterySection extends ConsumerWidget {
  const _BatterySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final design = ref.watch(designCapacityProvider).value;

    return Column(
      children: [
        const SectionHeader(title: 'This battery'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.battery_full_rounded),
                title: const Text('Design capacity'),
                subtitle: Text(
                  design?.isKnown ?? false
                      ? '${Units.mah(design!.mah)} · ${design.source.label}'
                      : 'Not reported by this device',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 19),
                onTap: () => _editDesignCapacity(context, ref, design),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('I replaced the battery'),
                subtitle: const Text(
                  'Clears measurement history so the new cell is measured '
                  'from scratch',
                ),
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editDesignCapacity(
    BuildContext context,
    WidgetRef ref,
    DesignCapacityInfo? current,
  ) async {
    final controller = TextEditingController(
      text: current?.mah?.toString() ?? '',
    );

    final value = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Design capacity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The capacity this battery had when new, in mAh. It is printed '
              'on the battery and listed in the phone\'s specifications.\n\n'
              'Health is measured against this figure, so getting it right '
              'matters more than any other setting here.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                suffixText: 'mAh',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, -1),
            child: const Text('Use detected'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value == null) return;
    await ref
        .read(batteryChannelProvider)
        .setDesignCapacityOverride(value == -1 ? null : value);
    ref.invalidate(designCapacityProvider);
    ref.invalidate(capacityEstimateProvider);
  }

  /// A replaced cell makes every stored measurement describe a different
  /// battery, so this is a real feature rather than a debug escape hatch.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start measuring again?'),
        content: const Text(
          'Every reading CellMeter has taken describes your old battery, so '
          'keeping them would drag the health figure for months.\n\n'
          'This permanently deletes all recorded samples, sessions and '
          'capacity estimates. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.critical,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete and restart'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(batteryRepositoryProvider).resetForNewBattery();
    ref.invalidate(capacityEstimateProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(syncControllerProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Measurement history cleared. Measuring afresh.'),
        ),
      );
    }
  }
}

class _DiagnosticsSection extends ConsumerWidget {
  const _DiagnosticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(databaseStatsProvider).value;
    final device = ref.watch(deviceInfoProvider).value;
    final snapshot = ref.watch(liveSnapshotProvider).value;

    return Column(
      children: [
        const SectionHeader(
          title: 'Diagnostics',
          subtitle: 'What this device actually reports',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                MetricRow(
                  label: 'Device',
                  value: device?.displayName ?? Units.unavailable,
                ),
                const Divider(),
                MetricRow(
                  label: 'Android',
                  value: device == null
                      ? Units.unavailable
                      : '${device.release} (API ${device.sdkInt})',
                ),
                const Divider(),
                MetricRow(
                  label: 'Charge counter',
                  value: snapshot?.chargeCounterUah == null
                      ? 'Not reported'
                      : Units.capacityMah(snapshot!.chargeCounterUah),
                  caption: 'The basis of capacity measurement',
                ),
                const Divider(),
                MetricRow(
                  label: 'Current sensor',
                  value: snapshot?.currentNowUa == null
                      ? 'Not reported'
                      : Units.currentMaSigned(snapshot!.currentNowUa),
                ),
                const Divider(),
                MetricRow(
                  label: 'Battery technology',
                  value: snapshot?.technology ?? Units.unavailable,
                ),
                const Divider(),
                MetricRow(
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
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(syncControllerProvider.notifier).rebuildEverything();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sessions rebuilt from stored readings.'),
                ),
              );
            }
          },
          icon: const Icon(Icons.build_rounded),
          label: const Text('Rebuild analysis from raw readings'),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'About'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.battery_charging_full_rounded,
                        color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('CellMeter', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Monitor. Analyze. Optimize.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Every measurement stays on this device. CellMeter has no '
                  'account, no analytics and no network permission at all.',
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
