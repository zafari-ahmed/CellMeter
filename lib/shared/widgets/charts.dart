import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format/units.dart';
import '../../core/theme/app_colors.dart';

/// One point on a time series.
class TimePoint {
  const TimePoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// A line chart over time, used for level, current, temperature and voltage.
///
/// Shared by every chart in the app so the axes, grid and tooltip behave
/// identically everywhere. The x axis is always real time rather than sample
/// index, which matters because sampling is deliberately irregular — a gap in
/// the data should look like a gap, not be silently compressed away.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.points,
    required this.color,
    this.secondaryPoints,
    this.secondaryColor,
    this.unitSuffix = '',
    this.minY,
    this.maxY,
    this.height = 180,
    this.fill = true,
    this.decimals = 0,
  });

  final List<TimePoint> points;
  final Color color;

  /// An optional second series on the same axes, e.g. temperature over level.
  final List<TimePoint>? secondaryPoints;
  final Color? secondaryColor;

  final String unitSuffix;
  final double? minY;
  final double? maxY;
  final double height;
  final bool fill;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough readings yet',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final spots = _toSpots(points);
    final secondarySpots =
        secondaryPoints == null ? null : _toSpots(secondaryPoints!);

    final allY = [
      ...points.map((p) => p.value),
      if (secondaryPoints != null) ...secondaryPoints!.map((p) => p.value),
    ];
    final lowest = allY.reduce((a, b) => a < b ? a : b);
    final highest = allY.reduce((a, b) => a > b ? a : b);
    // A flat series would otherwise collapse to a zero-height axis.
    final padding = ((highest - lowest).abs() * 0.15).clamp(0.5, 1e9);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY ?? lowest - padding,
          maxY: maxY ?? highest + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval:
                (((maxY ?? highest) - (minY ?? lowest)) / 3).abs().clamp(0.1, 1e9),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      value.toStringAsFixed(decimals),
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _bottomInterval(spots),
                getTitlesWidget: (value, meta) {
                  // fl_chart draws a label at the axis minimum as well as at
                  // every interval step, and with a short window the first
                  // interval step lands almost on top of it — two timestamps
                  // overprinted at the left edge. Drop any label that falls
                  // within a few percent of the start.
                  final span = meta.max - meta.min;
                  if (span > 0 && (value - meta.min) < span * 0.08) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      Units.clock(
                        DateTime.fromMillisecondsSinceEpoch(value.toInt()),
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItems: (touched) => touched.map((spot) {
                final time = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(decimals)}$unitSuffix\n',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: Units.clockWithSeconds(time),
                      style: TextStyle(
                        color: theme.colorScheme.onInverseSurface
                            .withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            _bar(spots, color, fill),
            if (secondarySpots != null)
              _bar(
                secondarySpots,
                secondaryColor ?? AppColors.info,
                false,
              ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _bar(List<FlSpot> spots, Color lineColor, bool filled) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        // Kept low: a high curve smoothing invents overshoot between samples,
        // which on a current chart would show currents the device never drew.
        curveSmoothness: 0.18,
        preventCurveOverShooting: true,
        color: lineColor,
        barWidth: 2.4,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: filled,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.28),
              lineColor.withValues(alpha: 0.0),
            ],
          ),
        ),
      );

  List<FlSpot> _toSpots(List<TimePoint> source) => source
      .map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value))
      .toList();

  double? _bottomInterval(List<FlSpot> spots) {
    if (spots.length < 2) return null;
    final span = spots.last.x - spots.first.x;
    return span <= 0 ? null : span / 3;
  }
}

/// Horizontal bars for the per-app breakdown.
///
/// A bar list rather than a pie: the question is "which app costs most, and by
/// how much", and length is far easier to compare than angle. It also degrades
/// gracefully when one app accounts for most of the total, where a pie becomes
/// a single wedge and a sliver.
class RankedBarList extends StatelessWidget {
  const RankedBarList({
    super.key,
    required this.entries,
    this.maxEntries = 10,
  });

  final List<RankedBarEntry> entries;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();

    final shown = entries.take(maxEntries).toList();
    final peak = shown
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b)
        .clamp(0.0001, double.infinity);

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shown[i].label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      shown[i].valueLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: shown[i].value / peak),
                    duration: Duration(milliseconds: 420 + i * 40),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.series[i % AppColors.series.length],
                      ),
                    ),
                  ),
                ),
                if (shown[i].caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      shown[i].caption!,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class RankedBarEntry {
  const RankedBarEntry({
    required this.label,
    required this.value,
    required this.valueLabel,
    this.caption,
  });

  final String label;
  final double value;
  final String valueLabel;
  final String? caption;
}
