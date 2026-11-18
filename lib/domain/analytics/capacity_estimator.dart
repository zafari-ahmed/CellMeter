import 'dart:math' as math;

import '../models/session_models.dart';
import 'session_segmenter.dart';

/// One session's contribution to the capacity estimate.
class CapacityPoint {
  const CapacityPoint({
    required this.at,
    required this.impliedMah,
    required this.levelSpanPct,
    required this.weight,
    required this.method,
  });

  final DateTime at;
  final double impliedMah;
  final double levelSpanPct;

  /// How much this session counts toward the final figure.
  final double weight;

  final ChargeMethod method;
}

/// The app's answer to "how much capacity does this battery actually have".
class CapacityEstimate {
  const CapacityEstimate({
    required this.estimatedMah,
    required this.sessionCount,
    required this.totalLevelSpanPct,
    required this.confidence,
    required this.points,
    this.designMah,
    this.healthPct,
    this.spreadMah,
    this.oemStateOfHealthPct,
  });

  /// Best estimate of full-charge capacity, mAh.
  final double estimatedMah;

  /// Factory capacity this was compared against, mAh.
  final int? designMah;

  /// [estimatedMah] as a percentage of [designMah].
  final double? healthPct;

  final int sessionCount;

  /// Total battery percentage covered by the contributing sessions. The honest
  /// measure of how much evidence sits behind the number.
  final double totalLevelSpanPct;

  /// Interquartile range of the per-session estimates, mAh.
  final double? spreadMah;

  final Confidence confidence;
  final List<CapacityPoint> points;

  /// The manufacturer's own figure, when the OS exposes it. Shown alongside
  /// rather than merged in: it is a different measurement with different
  /// failure modes, and disagreement between the two is informative.
  final int? oemStateOfHealthPct;

  /// Wear as a percentage of design capacity.
  double? get wearPct {
    final health = healthPct;
    return health == null ? null : (100 - health).clamp(0, 100).toDouble();
  }

  bool get hasDesign => designMah != null;

  static const empty = CapacityEstimate(
    estimatedMah: 0,
    sessionCount: 0,
    totalLevelSpanPct: 0,
    confidence: Confidence.low,
    points: [],
  );

  bool get isEmpty => sessionCount == 0;
}

/// Estimates real battery capacity from charge sessions.
///
/// ## The measurement
///
/// A battery's full capacity is charge divided by the fraction of the battery
/// that charge filled. If the coulomb counter says 1 480 mAh went in and the
/// level went from 24% to 78%, the battery holds 1 480 / 0.54 ≈ 2 741 mAh.
/// Each qualifying session produces one such estimate; this class combines
/// them.
///
/// ## Why combining them is the hard part
///
/// Single sessions are noisy in ways that do not cancel if you simply average:
///
///  - The level is quantised to whole percent, so a session is systematically
///    uncertain by about ±1/span. The segmenter already discards spans too
///    narrow to survive that.
///  - Fuel gauges re-calibrate, usually at the top and bottom of the range,
///    and a re-calibration mid-session shows up as a single wild outlier.
///  - Temperature changes real capacity by several percent, and a phone
///    charging on a car dashboard is a different battery from the same phone
///    charging on a bedside table.
///
/// So the estimator uses a **weighted median**, not a mean. A median ignores
/// the gauge re-calibration outlier entirely, where a mean would be dragged by
/// it for weeks. Weighting by level span means a 70% charge counts for more
/// than a 25% one, which matches where the information actually is.
///
/// Recency is handled by a half-life decay rather than a fixed window: a
/// battery that genuinely degrades should see the estimate follow, but not so
/// fast that one unusual session moves the headline number.
class CapacityEstimator {
  const CapacityEstimator({
    this.halfLife = const Duration(days: 45),
    this.maxSessions = 60,
    this.minSessionsForMedium = 3,
    this.minSessionsForHigh = 6,
    this.minSpanForMediumPct = 80,
    this.minSpanForHighPct = 200,
    this.outlierMadMultiplier = 3.0,
  });

  /// How long until a session counts half as much as a fresh one.
  final Duration halfLife;

  /// Beyond this many sessions the oldest add nothing, and scanning them costs
  /// time on every recompute.
  final int maxSessions;

  final int minSessionsForMedium;
  final int minSessionsForHigh;

  /// Total battery percentage that must be covered before the estimate stops
  /// calling itself provisional.
  final double minSpanForMediumPct;
  final double minSpanForHighPct;

  /// Outliers beyond this many median absolute deviations are dropped before
  /// the final weighted median. Catches gauge re-calibration jumps.
  final double outlierMadMultiplier;

  /// Combines qualifying [sessions] into a single estimate.
  ///
  /// Sessions that the segmenter rejected are ignored here; [sessions] may
  /// contain them, and filtering happens in one place so callers cannot forget.
  CapacityEstimate estimate({
    required List<SegmentedSession> sessions,
    int? designMah,
    int? oemStateOfHealthPct,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    final usable = sessions
        .where((s) => s.usableForCapacity && s.impliedCapacityMah != null)
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));

    final considered =
        usable.length > maxSessions ? usable.sublist(0, maxSessions) : usable;

    if (considered.isEmpty) {
      return CapacityEstimate(
        estimatedMah: 0,
        designMah: designMah,
        healthPct: null,
        sessionCount: 0,
        totalLevelSpanPct: 0,
        confidence: Confidence.low,
        points: const [],
        oemStateOfHealthPct: oemStateOfHealthPct,
      );
    }

    final points = considered
        .map((s) => CapacityPoint(
              at: s.start,
              impliedMah: s.impliedCapacityMah!,
              levelSpanPct: s.levelSpanPct,
              weight: _weightFor(s, reference),
              method: s.chargeMethod,
            ))
        .toList();

    final cleaned = _withoutOutliers(points);
    final estimated = _weightedMedian(cleaned);
    final spread = _interquartileRange(cleaned.map((p) => p.impliedMah).toList());
    final totalSpan =
        cleaned.fold<double>(0, (sum, p) => sum + p.levelSpanPct);

    final health = (designMah != null && designMah > 0)
        ? (estimated / designMah * 100)
        : null;

    return CapacityEstimate(
      estimatedMah: estimated,
      designMah: designMah,
      // Clamped: a gauge can legitimately report slightly over design on a new
      // battery, but a figure above 110% is noise, not a better-than-new cell.
      healthPct: health?.clamp(0, 110).toDouble(),
      sessionCount: cleaned.length,
      totalLevelSpanPct: totalSpan,
      spreadMah: spread,
      confidence: _confidenceFor(
        sessionCount: cleaned.length,
        totalSpanPct: totalSpan,
        spreadMah: spread,
        estimatedMah: estimated,
      ),
      points: cleaned,
      oemStateOfHealthPct: oemStateOfHealthPct,
    );
  }

  /// A session's weight: how wide it was, decayed by how long ago it happened.
  ///
  /// Span enters linearly because the measurement's precision scales with it.
  /// Age enters as an exponential half-life so the estimate tracks genuine
  /// degradation without letting any single recent session dominate.
  double _weightFor(SegmentedSession session, DateTime now) {
    final spanWeight = session.levelSpanPct / 100;

    final ageDays = now.difference(session.start).inHours / 24;
    final halfLifeDays = halfLife.inHours / 24;
    final decay = math.pow(0.5, ageDays / halfLifeDays).toDouble();

    // A session measured by integrating current carries the accumulated error
    // of every sample, so it counts, but for less.
    final methodWeight =
        session.chargeMethod == ChargeMethod.coulomb ? 1.0 : 0.6;

    return (spanWeight * decay * methodWeight).clamp(0.0001, double.infinity);
  }

  /// Drops points far from the median, measured in median absolute deviations.
  ///
  /// MAD is used rather than standard deviation because it does not itself get
  /// inflated by the outlier it is supposed to find — with only a handful of
  /// sessions, one bad value makes a standard deviation wide enough to accept
  /// that same bad value.
  List<CapacityPoint> _withoutOutliers(List<CapacityPoint> points) {
    if (points.length < 4) return points;

    final values = points.map((p) => p.impliedMah).toList()..sort();
    final median = _median(values);

    final deviations = values.map((v) => (v - median).abs()).toList()..sort();
    final mad = _median(deviations);

    // Identical readings give a zero MAD; nothing to reject.
    if (mad <= 0) return points;

    final limit = outlierMadMultiplier * mad;
    final kept = points
        .where((p) => (p.impliedMah - median).abs() <= limit)
        .toList();

    // Never throw away so much that the estimate rests on almost nothing.
    return kept.length >= 3 ? kept : points;
  }

  /// Weighted median: the value where half the total weight sits on each side.
  double _weightedMedian(List<CapacityPoint> points) {
    if (points.isEmpty) return 0;
    if (points.length == 1) return points.first.impliedMah;

    final sorted = [...points]
      ..sort((a, b) => a.impliedMah.compareTo(b.impliedMah));
    final totalWeight = sorted.fold<double>(0, (sum, p) => sum + p.weight);
    if (totalWeight <= 0) {
      return _median(sorted.map((p) => p.impliedMah).toList());
    }

    final target = totalWeight / 2;
    var running = 0.0;

    for (var i = 0; i < sorted.length; i++) {
      running += sorted[i].weight;
      if (running >= target) {
        // Landing exactly on a boundary means two values split the weight
        // evenly; take their midpoint rather than arbitrarily picking one.
        if (running == target && i + 1 < sorted.length) {
          return (sorted[i].impliedMah + sorted[i + 1].impliedMah) / 2;
        }
        return sorted[i].impliedMah;
      }
    }
    return sorted.last.impliedMah;
  }

  double _median(List<double> sortedOrNot) {
    if (sortedOrNot.isEmpty) return 0;
    final values = [...sortedOrNot]..sort();
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
  }

  /// Spread of the raw per-session estimates, used to describe how settled the
  /// measurement is. The IQR is reported rather than the full range so one
  /// surviving outlier does not make a converged estimate look unstable.
  double? _interquartileRange(List<double> values) {
    if (values.length < 4) return null;
    final sorted = [...values]..sort();
    final q1 = sorted[(sorted.length * 0.25).floor()];
    final q3 = sorted[(sorted.length * 0.75).floor()];
    return q3 - q1;
  }

  /// Confidence is deliberately conservative.
  ///
  /// It depends on three things rather than a session count alone: how many
  /// sessions there are, how much of the battery they covered in total, and how
  /// closely they agree. A dozen narrow sessions that disagree with each other
  /// is not a confident measurement, and saying so is more useful than a
  /// precise-looking number that moves next week.
  Confidence _confidenceFor({
    required int sessionCount,
    required double totalSpanPct,
    required double? spreadMah,
    required double estimatedMah,
  }) {
    if (sessionCount < minSessionsForMedium ||
        totalSpanPct < minSpanForMediumPct) {
      return Confidence.low;
    }

    final relativeSpread =
        (spreadMah != null && estimatedMah > 0) ? spreadMah / estimatedMah : null;

    if (sessionCount >= minSessionsForHigh &&
        totalSpanPct >= minSpanForHighPct &&
        (relativeSpread == null || relativeSpread <= 0.08)) {
      return Confidence.high;
    }

    if (relativeSpread != null && relativeSpread > 0.25) {
      return Confidence.low;
    }

    return Confidence.medium;
  }
}
