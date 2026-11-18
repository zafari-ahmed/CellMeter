import 'dart:math' as math;

import '../../data/native/native_models.dart';
import '../models/session_models.dart';

/// Turns an ordered stream of samples into charge and discharge sessions.
///
/// This is the first analysis step and everything else depends on it, so it is
/// written as a pure function over a list: no database, no clock, no platform.
/// That makes the awkward cases — a phone that was plugged in for eight hours,
/// a sampler killed in the middle, a gauge that re-calibrated and jumped 4% —
/// straightforward to reproduce in a test.
class SessionSegmenter {
  const SessionSegmenter({
    this.maxGap = const Duration(minutes: 20),
    this.minDuration = const Duration(minutes: 2),
    this.minLevelSpanPct = 1.0,
    this.minLevelSpanForCapacityPct = 20.0,
    this.maxGapForCapacity = const Duration(minutes: 10),
    this.maxTemperatureForCapacityC = 45.0,
    this.minSamplesForCapacity = 12,
  });

  /// A gap longer than this ends the session. The sampler was not running, so
  /// whatever happened in between is unknown and cannot be averaged over.
  final Duration maxGap;

  /// Shorter stretches are plug jitter, not sessions worth recording.
  final Duration minDuration;

  final double minLevelSpanPct;

  /// How much of the battery a charge has to cover before its capacity
  /// measurement is worth anything.
  ///
  /// Set at 20% rather than demanding a full charge for a concrete reason: a
  /// capacity estimate is a ratio of charge moved to level moved, and its
  /// relative error is dominated by the level reading, which is quantised to
  /// whole percent. Over a 20% span a ±1% quantisation is a ±5% error, which
  /// averages out across sessions. Over a 5% span it is ±20%, which does not.
  /// Requiring a *full* charge, as some tools do, throws away most of a user's
  /// real charging behaviour and is why those tools can go weeks without
  /// producing a number.
  final double minLevelSpanForCapacityPct;

  final Duration maxGapForCapacity;

  /// Capacity read off a hot battery is not comparable to one read off a cool
  /// one, so hot sessions are excluded rather than silently skewing the result.
  final double maxTemperatureForCapacityC;

  final int minSamplesForCapacity;

  /// Segments [samples], which must be sorted ascending by timestamp.
  ///
  /// [openEnded] keeps the final session even though it has not ended yet,
  /// which is what the live dashboard needs. History views pass false so an
  /// in-progress charge is not written to the database as if it were complete.
  List<SegmentedSession> segment(
    List<BatterySnapshot> samples, {
    bool openEnded = false,
  }) {
    if (samples.length < 2) return const [];

    final sessions = <SegmentedSession>[];
    var runStart = 0;

    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1];
      final current = samples[i];

      final gap = current.timestamp.difference(previous.timestamp);
      final stateChanged = previous.isCharging != current.isCharging;

      if (stateChanged || gap > maxGap) {
        final run = samples.sublist(runStart, i);
        final built = _build(run);
        if (built != null) sessions.add(built);
        runStart = i;
      }
    }

    final tail = samples.sublist(runStart);
    if (openEnded || _isClosed(tail, samples)) {
      final built = _build(tail);
      if (built != null) sessions.add(built);
    }

    return sessions;
  }

  /// The trailing run is complete only if it is not the live one. Without a
  /// later sample to prove the state changed, treat it as still running.
  bool _isClosed(List<BatterySnapshot> run, List<BatterySnapshot> all) =>
      run.isNotEmpty && !identical(run.last, all.last);

  SegmentedSession? _build(List<BatterySnapshot> run) {
    if (run.length < 2) return null;

    final first = run.first;
    final last = run.last;
    final duration = last.timestamp.difference(first.timestamp);
    if (duration < minDuration) return null;

    final startLevel = first.levelPct;
    final endLevel = last.levelPct;
    if (startLevel == null || endLevel == null) return null;

    final levelSpan = (endLevel - startLevel).abs();
    if (levelSpan < minLevelSpanPct) return null;

    final kind =
        first.isCharging ? SessionKind.charge : SessionKind.discharge;

    final stats = _Aggregates.from(run);
    final chargeMoved = _chargeMoved(run);

    final implied = _impliedCapacity(
      chargeMovedMah: chargeMoved.mah,
      levelSpanPct: levelSpan,
    );

    final rejection = _capacityRejection(
      kind: kind,
      run: run,
      levelSpan: levelSpan,
      maxGapMs: stats.maxGapMs,
      maxTemperature: stats.maxTemperatureC,
      chargeMoved: chargeMoved,
      implied: implied,
    );

    return SegmentedSession(
      kind: kind,
      start: first.timestamp,
      end: last.timestamp,
      startLevelPct: startLevel,
      endLevelPct: endLevel,
      startChargeUah: first.chargeCounterUah,
      endChargeUah: last.chargeCounterUah,
      chargeMovedMah: chargeMoved.mah,
      chargeMethod: chargeMoved.method,
      avgCurrentMa: stats.avgCurrentMa,
      maxCurrentMa: stats.maxCurrentMa,
      avgTemperatureC: stats.avgTemperatureC,
      maxTemperatureC: stats.maxTemperatureC,
      avgVoltageMv: stats.avgVoltageMv,
      screenOnMs: stats.screenOnMs,
      screenOffMs: stats.screenOffMs,
      screenOnDropPct: stats.screenOnDropPct,
      screenOffDropPct: stats.screenOffDropPct,
      plugType: stats.dominantPlug,
      sampleCount: run.length,
      maxGapMs: stats.maxGapMs,
      usableForCapacity: rejection == null,
      rejectionReason: rejection,
      impliedCapacityMah: implied,
      cyclesUsed: levelSpan / 100,
    );
  }

  /// Full capacity implied by one session: charge moved divided by the
  /// fraction of the battery it moved through.
  double? _impliedCapacity({
    required double? chargeMovedMah,
    required double levelSpanPct,
  }) {
    if (chargeMovedMah == null || levelSpanPct <= 0) return null;
    final capacity = chargeMovedMah.abs() / (levelSpanPct / 100);
    // Outside this range it is a unit error or a gauge glitch, not a battery.
    if (capacity < 300 || capacity > 30000) return null;
    return capacity;
  }

  /// Returns the reason this session cannot be used for capacity measurement,
  /// or null if it can.
  ///
  /// The text is written to be shown to the user. Telling someone *why* their
  /// overnight charge did not count is the difference between an app that
  /// seems broken and one that is visibly doing something careful.
  String? _capacityRejection({
    required SessionKind kind,
    required List<BatterySnapshot> run,
    required double levelSpan,
    required int maxGapMs,
    required double? maxTemperature,
    required _ChargeMoved chargeMoved,
    required double? implied,
  }) {
    if (kind != SessionKind.charge) {
      return 'Capacity is measured while charging.';
    }
    // Checked before the generic "no data" case: a derived counter also
    // leaves the method as none, and the specific explanation is far more
    // useful than being told the device reported nothing.
    if (chargeMoved.syntheticCounter) {
      return 'This device reports a charge counter derived from the battery '
          'percentage rather than a real measurement, so it cannot be used to '
          'measure capacity.';
    }
    if (chargeMoved.method == ChargeMethod.none) {
      return 'This device did not report enough charge data during the session.';
    }
    if (levelSpan < minLevelSpanForCapacityPct) {
      return 'Charged ${levelSpan.toStringAsFixed(0)}%. A session needs at '
          'least ${minLevelSpanForCapacityPct.toStringAsFixed(0)}% to measure '
          'capacity accurately.';
    }
    if (run.length < minSamplesForCapacity) {
      return 'Too few readings were recorded during this session.';
    }
    if (maxGapMs > maxGapForCapacity.inMilliseconds) {
      final minutes = (maxGapMs / 60000).round();
      return 'Monitoring was interrupted for $minutes minutes during this '
          'session, so the measurement would be incomplete.';
    }
    if (maxTemperature != null && maxTemperature > maxTemperatureForCapacityC) {
      return 'The battery reached ${maxTemperature.toStringAsFixed(1)} °C. '
          'Readings taken this hot are not comparable.';
    }
    if (implied == null) {
      return 'The measured capacity was outside a plausible range.';
    }
    return null;
  }

  /// Charge moved during the session, in mAh.
  ///
  /// Prefers the coulomb counter and falls back to integrating current. Both
  /// paths are needed: many devices expose a usable `CHARGE_COUNTER`, many
  /// expose only `CURRENT_NOW`, and a few expose a counter that is secretly
  /// just the level in disguise, which is detected here rather than quietly
  /// producing a capacity equal to the design figure.
  _ChargeMoved _chargeMoved(List<BatterySnapshot> run) {
    final start = run.first.chargeCounterUah;
    final end = run.last.chargeCounterUah;

    if (start != null && end != null && start != end) {
      if (_counterLooksSynthetic(run)) {
        return const _ChargeMoved(
          mah: null,
          method: ChargeMethod.none,
          syntheticCounter: true,
        );
      }
      return _ChargeMoved(
        mah: (end - start) / 1000,
        method: ChargeMethod.coulomb,
        syntheticCounter: false,
      );
    }

    final integrated = _integrateCurrent(run);
    if (integrated != null) {
      return _ChargeMoved(
        mah: integrated,
        method: ChargeMethod.integrated,
        syntheticCounter: false,
      );
    }

    return const _ChargeMoved(
      mah: null,
      method: ChargeMethod.none,
      syntheticCounter: false,
    );
  }

  /// Detects a charge counter that is computed from the level rather than
  /// measured.
  ///
  /// Some devices implement `BATTERY_PROPERTY_CHARGE_COUNTER` as
  /// `level% x design_capacity` instead of reading the fuel gauge. Such a
  /// counter is worse than no counter at all: dividing it by the level change
  /// returns the design capacity exactly, every time, so the app would report
  /// a pristine 100% health for a worn-out battery and never notice.
  ///
  /// The tell is that the ratio `counter / level` is *constant*. A real gauge
  /// measures charge continuously while the level is quantised to whole
  /// percent, so between two level steps the counter keeps moving and the
  /// ratio keeps changing. A derived counter holds the ratio fixed to within
  /// rounding.
  ///
  /// Testing the ratio rather than, say, counting distinct values also
  /// generalises correctly: if the ratio is constant then the capacity this
  /// session would imply is a fixed number independent of the battery's actual
  /// state, which carries no information about wear whatever the device's
  /// reason for reporting it that way.
  bool _counterLooksSynthetic(List<BatterySnapshot> run) {
    final ratios = <double>[];
    for (final sample in run) {
      final counter = sample.chargeCounterUah;
      final level = sample.levelPct;
      if (counter == null || level == null || level <= 0) continue;
      ratios.add(counter / level);
    }

    // Too few points for "constant" to be a meaningful observation.
    if (ratios.length < 6) return false;

    var min = ratios.first;
    var max = ratios.first;
    var sum = 0.0;
    for (final ratio in ratios) {
      if (ratio < min) min = ratio;
      if (ratio > max) max = ratio;
      sum += ratio;
    }

    final mean = sum / ratios.length;
    if (mean <= 0) return false;

    // The tolerance only has to absorb integer rounding in the device's own
    // multiplication. A real gauge varies by far more than this: one whole
    // percent of level is around 3% of the ratio.
    return (max - min) / mean < _syntheticRatioTolerance;
  }

  /// Relative spread below which `counter / level` counts as constant.
  static const double _syntheticRatioTolerance = 0.002;

  /// Trapezoidal integration of current over time, in mAh.
  ///
  /// Intervals longer than [maxGapForCapacity] are skipped rather than
  /// interpolated across: assuming the current held steady through a gap the
  /// sampler did not observe is exactly the kind of invented data this app
  /// exists to avoid.
  double? _integrateCurrent(List<BatterySnapshot> run) {
    var microAmpMillis = 0.0;
    var covered = 0;

    for (var i = 1; i < run.length; i++) {
      final a = run[i - 1];
      final b = run[i];
      final currentA = a.currentNowUa;
      final currentB = b.currentNowUa;
      if (currentA == null || currentB == null) continue;

      final dtMs = b.timestamp.difference(a.timestamp).inMilliseconds;
      if (dtMs <= 0 || dtMs > maxGapForCapacity.inMilliseconds) continue;

      microAmpMillis += ((currentA + currentB) / 2) * dtMs;
      covered += dtMs;
    }

    if (covered <= 0) return null;

    // Needs to span most of the session to be worth reporting.
    final total = run.last.timestamp.difference(run.first.timestamp)
        .inMilliseconds;
    if (total > 0 && covered / total < 0.8) return null;

    // uA*ms -> uAh is /3.6e6, uAh -> mAh is /1000.
    return microAmpMillis / 3.6e6 / 1000;
  }
}

/// A session as produced by the segmenter, before it has a database id.
class SegmentedSession {
  const SegmentedSession({
    required this.kind,
    required this.start,
    required this.end,
    required this.startLevelPct,
    required this.endLevelPct,
    this.startChargeUah,
    this.endChargeUah,
    this.chargeMovedMah,
    this.chargeMethod = ChargeMethod.none,
    this.avgCurrentMa,
    this.maxCurrentMa,
    this.avgTemperatureC,
    this.maxTemperatureC,
    this.avgVoltageMv,
    this.screenOnMs = 0,
    this.screenOffMs = 0,
    this.screenOnDropPct,
    this.screenOffDropPct,
    this.plugType,
    this.sampleCount = 0,
    this.maxGapMs = 0,
    this.usableForCapacity = false,
    this.rejectionReason,
    this.impliedCapacityMah,
    this.cyclesUsed = 0,
  });

  final SessionKind kind;
  final DateTime start;
  final DateTime end;
  final double startLevelPct;
  final double endLevelPct;
  final int? startChargeUah;
  final int? endChargeUah;
  final double? chargeMovedMah;
  final ChargeMethod chargeMethod;
  final double? avgCurrentMa;
  final double? maxCurrentMa;
  final double? avgTemperatureC;
  final double? maxTemperatureC;
  final double? avgVoltageMv;
  final int screenOnMs;
  final int screenOffMs;
  final double? screenOnDropPct;
  final double? screenOffDropPct;
  final PlugType? plugType;
  final int sampleCount;
  final int maxGapMs;
  final bool usableForCapacity;
  final String? rejectionReason;
  final double? impliedCapacityMah;
  final double cyclesUsed;

  Duration get duration => end.difference(start);
  double get levelSpanPct => (endLevelPct - startLevelPct).abs();
}

class _ChargeMoved {
  const _ChargeMoved({
    required this.mah,
    required this.method,
    required this.syntheticCounter,
  });

  final double? mah;
  final ChargeMethod method;
  final bool syntheticCounter;
}

/// Everything that is a simple reduction over the samples of one session.
/// Computed in a single pass because history screens segment months at a time.
class _Aggregates {
  _Aggregates({
    required this.avgCurrentMa,
    required this.maxCurrentMa,
    required this.avgTemperatureC,
    required this.maxTemperatureC,
    required this.avgVoltageMv,
    required this.screenOnMs,
    required this.screenOffMs,
    required this.screenOnDropPct,
    required this.screenOffDropPct,
    required this.maxGapMs,
    required this.dominantPlug,
  });

  final double? avgCurrentMa;
  final double? maxCurrentMa;
  final double? avgTemperatureC;
  final double? maxTemperatureC;
  final double? avgVoltageMv;
  final int screenOnMs;
  final int screenOffMs;
  final double? screenOnDropPct;
  final double? screenOffDropPct;
  final int maxGapMs;
  final PlugType? dominantPlug;

  static _Aggregates from(List<BatterySnapshot> run) {
    var currentSum = 0.0;
    var currentCount = 0;
    var currentMax = 0.0;

    var tempSum = 0.0;
    var tempCount = 0;
    double? tempMax;

    var voltSum = 0.0;
    var voltCount = 0;

    var screenOnMs = 0;
    var screenOffMs = 0;
    var screenOnDrop = 0.0;
    var screenOffDrop = 0.0;

    var maxGapMs = 0;
    final plugCounts = <PlugType, int>{};

    for (var i = 0; i < run.length; i++) {
      final sample = run[i];

      final current = sample.currentNowUa;
      if (current != null) {
        final ma = current / 1000;
        currentSum += ma;
        currentCount++;
        currentMax = math.max(currentMax, ma.abs());
      }

      final temperature = sample.temperatureC;
      if (temperature != null) {
        tempSum += temperature;
        tempCount++;
        tempMax = tempMax == null ? temperature : math.max(tempMax, temperature);
      }

      final voltage = sample.voltageMv;
      if (voltage != null) {
        voltSum += voltage;
        voltCount++;
      }

      plugCounts.update(sample.plugType, (v) => v + 1, ifAbsent: () => 1);

      if (i == 0) continue;

      // Each interval is attributed to the screen state it started in, and to
      // the level change observed across it.
      final previous = run[i - 1];
      final dtMs = sample.timestamp.difference(previous.timestamp).inMilliseconds;
      if (dtMs <= 0) continue;
      maxGapMs = math.max(maxGapMs, dtMs);

      final levelFrom = previous.levelPct;
      final levelTo = sample.levelPct;
      final drop = (levelFrom != null && levelTo != null)
          ? (levelFrom - levelTo)
          : 0.0;

      if (previous.screenOn) {
        screenOnMs += dtMs;
        if (drop > 0) screenOnDrop += drop;
      } else {
        screenOffMs += dtMs;
        if (drop > 0) screenOffDrop += drop;
      }
    }

    PlugType? dominant;
    var best = 0;
    plugCounts.forEach((plug, count) {
      if (plug != PlugType.none && count > best) {
        best = count;
        dominant = plug;
      }
    });

    return _Aggregates(
      avgCurrentMa: currentCount > 0 ? currentSum / currentCount : null,
      maxCurrentMa: currentCount > 0 ? currentMax : null,
      avgTemperatureC: tempCount > 0 ? tempSum / tempCount : null,
      maxTemperatureC: tempMax,
      avgVoltageMv: voltCount > 0 ? voltSum / voltCount : null,
      screenOnMs: screenOnMs,
      screenOffMs: screenOffMs,
      screenOnDropPct: screenOnMs > 0 ? screenOnDrop : null,
      screenOffDropPct: screenOffMs > 0 ? screenOffDrop : null,
      maxGapMs: maxGapMs,
      dominantPlug: dominant,
    );
  }
}
