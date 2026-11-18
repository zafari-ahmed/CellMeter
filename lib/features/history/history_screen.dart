import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/native/native_models.dart';
import '../../domain/models/session_models.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/metric_card.dart';

/// Everything that has happened to the battery, as a scrollable record.
///
/// Two views over the same data: a continuous level chart for "what happened
/// last night", and a session list for "what has this phone been doing all
/// week". Both are needed — the chart shows shape and the list shows totals,
/// and neither substitutes for the other.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  SessionKind? _filter;

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(recentSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Charges',
                  selected: _filter == SessionKind.charge,
                  onTap: () => setState(() => _filter = SessionKind.charge),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Discharges',
                  selected: _filter == SessionKind.discharge,
                  onTap: () => setState(() => _filter = SessionKind.discharge),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).refreshNow(),
        child: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorList(error: error),
          data: (all) {
            final filtered = _filter == null
                ? all
                : all.where((s) => s.kind == _filter).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _LevelChart(),
                const _TodaySummary(),
                SectionHeader(
                  title: 'Sessions',
                  subtitle: filtered.isEmpty
                      ? null
                      : '${filtered.length} recorded',
                ),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: 'Nothing recorded yet',
                      message: 'Sessions appear here once CellMeter has '
                          'watched the battery charge or discharge for a '
                          'few minutes.',
                    ),
                  )
                else
                  for (final session in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SessionTile(session: session),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Battery level over the last 24 hours.
class _LevelChart extends ConsumerWidget {
  const _LevelChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = ref.watch(_dayOfSamplesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 18, 12),
        child: samples.when(
          loading: () => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox(height: 180),
          data: (list) {
            final points = list
                .where((s) => s.levelPct != null)
                .map((s) => TimePoint(s.timestamp, s.levelPct!))
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 8),
                  child: Text(
                    'LEVEL, LAST 24 HOURS',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                TimeSeriesChart(
                  points: points,
                  color: AppColors.primary,
                  unitSuffix: '%',
                  minY: 0,
                  maxY: 100,
                  height: 180,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _dayOfSamplesProvider =
    FutureProvider.autoDispose<List<BatterySnapshot>>((ref) async {
  await ref.watch(syncControllerProvider.future);
  return ref
      .watch(batteryRepositoryProvider)
      .recentSamples(window: const Duration(hours: 24));
});

class _TodaySummary extends ConsumerWidget {
  const _TodaySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(recentSessionsProvider).value ?? const [];
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final today = sessions.where((s) => s.start.isAfter(since)).toList();

    if (today.isEmpty) return const SizedBox.shrink();

    final charged = today
        .where((s) => s.kind == SessionKind.charge)
        .fold<double>(0, (sum, s) => sum + s.levelSpanPct);
    final discharged = today
        .where((s) => s.kind == SessionKind.discharge)
        .fold<double>(0, (sum, s) => sum + s.levelSpanPct);
    final screenOn = today.fold<int>(0, (sum, s) => sum + s.screenOnMs);
    final cycles = today.fold<double>(
      0,
      (sum, s) => s.kind == SessionKind.charge ? sum + s.cyclesUsed : sum,
    );

    return Column(
      children: [
        const SectionHeader(title: 'Last 24 hours'),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Charged',
                value: Units.percent(charged),
                icon: Icons.arrow_upward_rounded,
                accent: AppColors.primary,
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Used',
                value: Units.percent(discharged),
                icon: Icons.arrow_downward_rounded,
                accent: AppColors.info,
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
                label: 'Screen on',
                value: Units.duration(Duration(milliseconds: screenOn)),
                icon: Icons.smartphone_rounded,
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Cycles used',
                value: cycles.toStringAsFixed(2),
                caption: 'Wear from today',
                icon: Icons.autorenew_rounded,
                accent: AppColors.accent,
                dense: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final BatterySession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCharge = session.kind == SessionKind.charge;
    final accent = isCharge ? AppColors.primary : AppColors.info;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCharge
                        ? Icons.bolt_rounded
                        : Icons.trending_down_rounded,
                    size: 19,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCharge ? 'Charged' : 'Discharged',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        Units.friendlyDateTime(session.start),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isCharge ? '+' : '−'}'
                      '${session.levelSpanPct.round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      Units.duration(session.duration),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Pill(
                  label: 'Level',
                  value: '${session.startLevelPct.round()}%'
                      ' → ${session.endLevelPct.round()}%',
                ),
                if (session.chargeMovedMah != null)
                  _Pill(
                    label: isCharge ? 'Added' : 'Used',
                    value: Units.mah(session.chargeMovedMah!.abs()),
                  ),
                if (session.avgTemperatureC != null)
                  _Pill(
                    label: 'Avg temp',
                    value: Units.celsius(session.avgTemperatureC),
                  ),
                if (!isCharge && session.screenOnPctPerHour != null)
                  _Pill(
                    label: 'Screen on',
                    value:
                        Units.percentPerHour(session.screenOnPctPerHour),
                  ),
                if (!isCharge && session.screenOffPctPerHour != null)
                  _Pill(
                    label: 'Standby',
                    value:
                        Units.percentPerHour(session.screenOffPctPerHour),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? AppColors.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load history',
            message: '$error',
          ),
        ],
      );
}
