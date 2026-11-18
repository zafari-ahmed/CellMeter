import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/units.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/analytics/capacity_estimator.dart';
import '../../domain/models/session_models.dart';
import '../../shared/widgets/battery_gauge.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/metric_card.dart';

/// Battery health: what the cell actually holds now compared with what it held
/// when it was new, how that estimate was reached, and how much of it to trust.
///
/// The screen is built around one principle: never show a health percentage
/// without also showing what it is based on. A number like "87%" is only
/// meaningful next to the number of sessions behind it and how closely they
/// agreed, and an app that hides that is asking to be believed rather than
/// earning it.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimateAsync = ref.watch(capacityEstimateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Health')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).refreshNow(),
        child: estimateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(error: error),
          data: (estimate) => estimate.isEmpty
              ? const _NotYetMeasured()
              : _HealthContent(estimate: estimate),
        ),
      ),
    );
  }
}

class _HealthContent extends ConsumerWidget {
  const _HealthContent({required this.estimate});

  final CapacityEstimate estimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final design = ref.watch(designCapacityProvider).value;
    final cycles = ref.watch(cyclesUsedProvider).value;
    final history = ref.watch(capacityHistoryProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _HeadlineCard(estimate: estimate),
        const SectionHeader(title: 'Capacity'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                MetricRow(
                  label: 'Measured capacity',
                  value: Units.mah(estimate.estimatedMah),
                  caption: 'What the battery holds today',
                  valueColor: AppColors.primary,
                ),
                const Divider(),
                MetricRow(
                  label: 'Design capacity',
                  value: Units.mah(estimate.designMah),
                  caption: design?.source.label ?? 'Factory rating',
                ),
                const Divider(),
                MetricRow(
                  label: 'Capacity lost',
                  value: estimate.designMah == null
                      ? Units.unavailable
                      : Units.mah(
                          estimate.designMah! - estimate.estimatedMah,
                        ),
                  caption: 'Compared with a new battery',
                ),
                if (estimate.oemStateOfHealthPct != null) ...[
                  const Divider(),
                  MetricRow(
                    label: 'Manufacturer estimate',
                    value: Units.percent(estimate.oemStateOfHealthPct),
                    // Deliberately not blended into the headline: it is a
                    // separate measurement with its own failure modes, and a
                    // disagreement between the two is worth seeing.
                    caption: 'Reported by Android, measured independently',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SectionHeader(
          title: 'Wear',
          subtitle: 'Charge cycles consumed since CellMeter started watching',
        ),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Cycles used',
                value: cycles == null ? Units.unavailable
                    : cycles.toStringAsFixed(1),
                caption: 'Battery moved ÷ 100',
                icon: Icons.autorenew_rounded,
                dense: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Wear',
                value: Units.percent(estimate.wearPct, decimals: 1),
                caption: 'Of original capacity',
                icon: Icons.trending_down_rounded,
                accent: estimate.wearPct == null
                    ? null
                    : AppColors.forScore(100 - estimate.wearPct!),
                dense: true,
              ),
            ),
          ],
        ),
        if (history.length > 2) ...[
          const SectionHeader(
            title: 'How the estimate has settled',
            subtitle: 'Each point is a recalculation as new charges arrived',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 18, 8),
              child: TimeSeriesChart(
                points: history
                    .map((row) => TimePoint(
                          DateTime.fromMillisecondsSinceEpoch(row.computedAtMs),
                          row.estimatedMah,
                        ))
                    .toList(),
                color: AppColors.primary,
                unitSuffix: ' mAh',
                height: 170,
              ),
            ),
          ),
        ],
        _EvidenceCard(estimate: estimate),
        const _RejectedSessionsCard(),
        const SizedBox(height: 16),
        Text(
          'CellMeter measures capacity by comparing the charge that went into '
          'the battery with how far the level moved. It does not need a full '
          'charge — any session covering 20% or more counts.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.estimate});

  final CapacityEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = estimate.healthPct;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Text(
              Units.percent(health),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 64,
                color: health == null ? null : AppColors.forScore(health),
              ),
            ),
            Text('battery health', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            HealthBar(healthPct: health, height: 14),
            const SizedBox(height: 18),
            StatusChip(
              label: _verdict(health),
              color: health == null ? null : AppColors.forScore(health),
              icon: Icons.verified_outlined,
            ),
          ],
        ),
      ),
    );
  }

  /// Plain-language verdicts, pitched at what the number means for the user
  /// rather than at the number itself. 80% is the threshold manufacturers
  /// themselves use for warranty replacement, so that is where the language
  /// changes.
  String _verdict(double? health) {
    if (health == null) return 'Not enough data';
    if (health >= 95) return 'As good as new';
    if (health >= 85) return 'Healthy';
    if (health >= 80) return 'Normal wear for its age';
    if (health >= 70) return 'Noticeably worn';
    if (health >= 55) return 'Heavily worn — consider replacing';
    return 'Replacement recommended';
  }
}

/// What the headline figure rests on.
class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.estimate});

  final CapacityEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spread = estimate.spreadMah;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'What this is based on',
          subtitle: 'So you can judge the number rather than take it on faith',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                MetricRow(
                  label: 'Charge sessions used',
                  value: estimate.sessionCount.toString(),
                  caption: 'Sessions that met the accuracy bar',
                ),
                const Divider(),
                MetricRow(
                  label: 'Battery covered in total',
                  value: Units.percent(estimate.totalLevelSpanPct),
                  caption: 'More coverage means a tighter estimate',
                ),
                const Divider(),
                MetricRow(
                  label: 'Agreement between sessions',
                  value: spread == null
                      ? Units.unavailable
                      : '± ${Units.mah(spread / 2)}',
                  caption: spread == null
                      ? 'Needs a few more sessions'
                      : _spreadCaption(spread, estimate.estimatedMah),
                ),
                const Divider(),
                MetricRow(
                  label: 'Confidence',
                  value: estimate.confidence.label,
                  caption: _confidenceCaption(estimate.confidence),
                ),
              ],
            ),
          ),
        ),
        if (estimate.confidence == Confidence.low) ...[
          const SizedBox(height: 12),
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
                    'This figure will move as more charges are measured. '
                    'Treat it as provisional until the confidence rises.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _spreadCaption(double spread, double estimated) {
    if (estimated <= 0) return '';
    final relative = spread / estimated;
    if (relative < 0.05) return 'Sessions agree closely';
    if (relative < 0.15) return 'Reasonable agreement';
    return 'Sessions still disagree — keep measuring';
  }

  String _confidenceCaption(Confidence confidence) => switch (confidence) {
        Confidence.high => 'Enough consistent evidence to rely on',
        Confidence.medium => 'Usable, still tightening',
        Confidence.low => 'Early days — not yet reliable',
      };
}

/// Why recent charges did not count.
///
/// Users who see "still measuring" for days need to know whether that is
/// normal or whether something on their device is blocking it. An app that
/// just says nothing invites the conclusion that it is broken.
class _RejectedSessionsCard extends ConsumerWidget {
  const _RejectedSessionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions =
        ref.watch(sessionsOfKindProvider(SessionKind.charge)).value ?? const [];

    final rejected = sessions
        .where((s) => !s.usableForCapacity && s.rejectionReason != null)
        .take(4)
        .toList();

    if (rejected.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Charges that did not count',
          subtitle: 'And why — most of these are perfectly normal',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              children: [
                for (var i = 0; i < rejected.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 17,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${Units.friendlyDateTime(rejected[i].start)}'
                              ' · ${rejected[i].startLevelPct.round()}%'
                              ' → ${rejected[i].endLevelPct.round()}%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              rejected[i].rejectionReason!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NotYetMeasured extends ConsumerWidget {
  const _NotYetMeasured();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final design = ref.watch(designCapacityProvider).value;

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 40),
        const EmptyState(
          icon: Icons.science_rounded,
          title: 'Measuring has not finished yet',
          message: 'CellMeter works out what your battery really holds by '
              'watching it charge. Plug in at 50% or below and let it run — '
              'one charge covering 20% of the battery is enough to start.\n\n'
              'You do not need to charge to 100%.',
        ),
        const SizedBox(height: 24),
        if (design?.isKnown ?? false)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: MetricRow(
                label: 'Design capacity',
                value: Units.mah(design!.mah),
                caption: design.source.label,
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This device does not report its design capacity',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'CellMeter can still measure what the battery holds, but '
                    'without the factory figure it cannot express that as a '
                    'health percentage. You can enter it in Settings.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not work out battery health',
            message: '$error',
          ),
        ],
      );
}
