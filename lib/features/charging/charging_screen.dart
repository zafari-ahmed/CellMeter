import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/native/native_models.dart';
import '../../domain/models/session_models.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/metric_card.dart';

/// Charging: how fast this charger actually is, how long it will take, and
/// what each past session cost the battery.
///
/// The practical purpose is comparison. Chargers and cables are sold with
/// claims that often do not survive contact with a particular phone, and the
/// only way to know which of the three chargers in a house is the good one is
/// to measure the current each delivers to this device.
class ChargingScreen extends ConsumerWidget {
  const ChargingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(liveSnapshotProvider).value;
    final charging = snapshot?.isCharging ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Charging')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).refreshNow(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (charging)
              _LiveCharge(snapshot: snapshot!)
            else
              const _NotCharging(),
            const _ChargeHistory(),
          ],
        ),
      ),
    );
  }
}

class _LiveCharge extends ConsumerWidget {
  const _LiveCharge({required this.snapshot});

  final BatterySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final toFull = ref.watch(timeToFullProvider).value;
    final toLimit = ref.watch(timeToChargeLimitProvider).value;
    final settings = ref.watch(monitorSettingsProvider).value;

    final watts = snapshot.powerMw == null ? null : snapshot.powerMw! / 1000;
    final speed = watts == null ? null : ChargeSpeedClass.fromWatts(watts);

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      snapshot.plugType.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  Units.currentMa(snapshot.currentNowUa),
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: AppColors.primary,
                    fontSize: 48,
                  ),
                ),
                Text('going into the battery',
                    style: theme.textTheme.bodySmall),
                if (speed != null) ...[
                  const SizedBox(height: 14),
                  StatusChip(
                    label: '${speed.label} · ${Units.watts(snapshot.powerMw)}',
                    color: switch (speed) {
                      ChargeSpeedClass.veryFast => AppColors.primary,
                      ChargeSpeedClass.fast => AppColors.good,
                      ChargeSpeedClass.standard => AppColors.accent,
                      ChargeSpeedClass.slow => AppColors.poor,
                    },
                    icon: Icons.speed_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'Time remaining'),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'To full',
                value: Units.duration(toFull),
                caption: 'Allows for the slow tail above 80%',
                icon: Icons.battery_charging_full_rounded,
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: settings?.chargeAlarmEnabled == true
                    ? 'To ${settings!.chargeAlarmPct}%'
                    : 'Charge limit',
                value: settings?.chargeAlarmEnabled == true
                    ? Units.duration(toLimit)
                    : 'Off',
                caption: settings?.chargeAlarmEnabled == true
                    ? 'Your charge alarm'
                    : 'Set one to reduce wear',
                icon: Icons.notifications_active_rounded,
                accent: AppColors.accent,
                dense: true,
              ),
            ),
          ],
        ),
        const SectionHeader(title: 'This session'),
        const _LiveChargeChart(),
      ],
    );
  }
}

/// The current and level curves for the charge in progress.
///
/// Worth showing live because the shape is diagnostic: a current that falls
/// away early means the charger, cable or port is limiting things, which looks
/// identical to a healthy charge if you only read the final time.
class _LiveChargeChart extends ConsumerWidget {
  const _LiveChargeChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samplesAsync = ref.watch(_chargeSamplesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 18, 12),
        child: samplesAsync.when(
          loading: () => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox(height: 180),
          data: (samples) {
            if (samples.length < 3) {
              return const SizedBox(
                height: 180,
                child: Center(child: Text('Collecting readings…')),
              );
            }
            return Column(
              children: [
                TimeSeriesChart(
                  points: samples
                      .where((s) => s.currentNowUa != null)
                      .map((s) => TimePoint(
                            s.timestamp,
                            s.currentNowUa!.abs() / 1000,
                          ))
                      .toList(),
                  color: AppColors.primary,
                  unitSuffix: ' mA',
                  height: 170,
                ),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Legend(color: AppColors.primary, label: 'Charging current'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Samples of the charge currently in progress.
final _chargeSamplesProvider =
    FutureProvider.autoDispose<List<BatterySnapshot>>((ref) async {
  ref.watch(liveSnapshotProvider);
  final repository = ref.watch(batteryRepositoryProvider);
  final samples = await repository.recentSamples(
    window: const Duration(hours: 6),
  );

  // Keep only the trailing run where the device has been charging: an earlier
  // charge from this morning is a different session and would distort the
  // shape of this one.
  final run = <BatterySnapshot>[];
  for (final sample in samples.reversed) {
    if (!sample.isCharging) break;
    run.insert(0, sample);
  }
  return run;
});

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _NotCharging extends ConsumerWidget {
  const _NotCharging();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(sessionsOfKindProvider(SessionKind.charge)).value ?? const [];
    final last = sessions.isEmpty ? null : sessions.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.power_off_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Not charging',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              last == null
                  ? 'Plug in and CellMeter will measure the charger.'
                  : 'Last charge ${Units.relative(last.start)} · '
                      '${last.startLevelPct.round()}% → '
                      '${last.endLevelPct.round()}%',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargeHistory extends ConsumerWidget {
  const _ChargeHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(sessionsOfKindProvider(SessionKind.charge)).value ?? const [];

    if (sessions.isEmpty) return const SizedBox.shrink();

    final withPower = sessions
        .where((s) => s.avgPowerW != null && s.plugType != null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withPower.length >= 2) ...[
          const SectionHeader(
            title: 'Your chargers compared',
            subtitle: 'Average power actually delivered to this phone',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: RankedBarList(
                entries: _byCharger(withPower),
                maxEntries: 5,
              ),
            ),
          ),
        ],
        const SectionHeader(title: 'Recent charges'),
        for (final session in sessions.take(20))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChargeSessionTile(session: session),
          ),
      ],
    );
  }

  /// Groups past charges by plug type and averages the power each delivered.
  ///
  /// Plug type is the only handle Android gives on "which charger": it cannot
  /// tell two AC chargers apart. Grouping by it still answers the question
  /// most people have, which is whether wireless or the USB port is costing
  /// them time.
  List<RankedBarEntry> _byCharger(List<BatterySession> sessions) {
    final totals = <PlugType, List<double>>{};
    for (final session in sessions) {
      totals
          .putIfAbsent(session.plugType!, () => [])
          .add(session.avgPowerW!);
    }

    final entries = totals.entries.map((entry) {
      final average =
          entry.value.reduce((a, b) => a + b) / entry.value.length;
      return RankedBarEntry(
        label: entry.key.label,
        value: average,
        valueLabel: '${average.toStringAsFixed(1)} W',
        caption: '${entry.value.length} '
            '${entry.value.length == 1 ? 'session' : 'sessions'}',
      );
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries;
  }
}

class _ChargeSessionTile extends StatelessWidget {
  const _ChargeSessionTile({required this.session});

  final BatterySession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watts = session.avgPowerW;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Units.friendlyDateTime(session.start),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (session.usableForCapacity)
                  const StatusChip(
                    label: 'Measured',
                    color: AppColors.primary,
                    icon: Icons.check_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(
                  label: 'Level',
                  value: '${session.startLevelPct.round()}'
                      ' → ${session.endLevelPct.round()}%',
                ),
                _Stat(
                  label: 'Took',
                  value: Units.duration(session.duration),
                ),
                _Stat(
                  label: 'Power',
                  value: watts == null
                      ? Units.unavailable
                      : '${watts.toStringAsFixed(1)} W',
                ),
                _Stat(
                  label: 'Added',
                  value: Units.mah(session.chargeMovedMah),
                ),
              ],
            ),
            if (session.impliedCapacityMah != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.straighten_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Implied capacity '
                    '${Units.mah(session.impliedCapacityMah)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ] else if (session.rejectionReason != null) ...[
              const Divider(height: 24),
              Text(
                session.rejectionReason!,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
