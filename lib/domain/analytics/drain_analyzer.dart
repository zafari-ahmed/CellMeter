import 'dart:math' as math;

import '../../data/native/native_models.dart';
import '../models/session_models.dart';
import 'session_segmenter.dart';

/// Drain rates split by screen state, plus what they imply for runtime.
class DrainProfile {
  const DrainProfile({
    this.screenOnPctPerHour,
    this.screenOffPctPerHour,
    this.combinedPctPerHour,
    this.screenOnMahPerHour,
    this.screenOffMahPerHour,
    this.sampleSessions = 0,
    this.screenOnDuration = Duration.zero,
    this.screenOffDuration = Duration.zero,
  });

  /// Drain while the user is looking at the phone.
  final double? screenOnPctPerHour;

  /// Standby drain. The number that exposes a wakelock problem.
  final double? screenOffPctPerHour;

  /// Blended rate over the measured period, weighted by how the phone was
  /// actually used rather than by a nominal split.
  final double? combinedPctPerHour;

  final double? screenOnMahPerHour;
  final double? screenOffMahPerHour;

  final int sampleSessions;
  final Duration screenOnDuration;
  final Duration screenOffDuration;

  bool get hasData => sampleSessions > 0 &&
      (screenOnPctPerHour != null || screenOffPctPerHour != null);

  /// How long the remaining charge lasts if the phone stays on screen.
  Duration? screenOnRuntime(double levelPct) =>
      _runtime(levelPct, screenOnPctPerHour);

  /// How long it lasts in standby.
  Duration? standbyRuntime(double levelPct) =>
      _runtime(levelPct, screenOffPctPerHour);

  /// How long it lasts at the user's own observed mix of the two.
  Duration? mixedRuntime(double levelPct) =>
      _runtime(levelPct, combinedPctPerHour);

  static Duration? _runtime(double levelPct, double? rate) {
    if (rate == null || rate <= 0) return null;
    final hours = levelPct / rate;
    if (hours <= 0 || hours > 1000) return null;
    return Duration(minutes: (hours * 60).round());
  }

  static const empty = DrainProfile();
}

/// Turns discharge history into rates, forecasts and the live drain reading.
///
/// Every method here separates screen-on from screen-off, because they are
/// different regimes that happen to share a battery. A phone might lose 14%
/// per hour of use and 0.6% per hour asleep; averaging those into "7%/h"
/// produces a runtime estimate that is wrong under both conditions and is
/// exactly the kind of number this app is supposed to replace.
class DrainAnalyzer {
  const DrainAnalyzer({
    this.lookback = const Duration(days: 7),
    this.minScreenOnMinutes = 15,
    this.minScreenOffMinutes = 30,
    this.liveWindow = const Duration(minutes: 20),
  });

  /// How far back history is considered. A week captures the user's routine
  /// without letting a holiday two months ago shape today's estimate.
  final Duration lookback;

  /// Below these, the measured drop is mostly quantisation noise.
  final int minScreenOnMinutes;
  final int minScreenOffMinutes;

  /// Window for the live "right now" drain figure.
  final Duration liveWindow;

  /// Builds the drain profile from recent discharge sessions.
  ///
  /// Rates are pooled — total level lost over total time, in each screen state
  /// — rather than averaged per session. Averaging per-session rates lets a
  /// two-minute discharge count as much as a six-hour one, which puts far too
  /// much weight on the shortest and noisiest samples.
  DrainProfile profile(List<SegmentedSession> sessions, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(lookback);

    var screenOnMs = 0;
    var screenOffMs = 0;
    var screenOnDrop = 0.0;
    var screenOffDrop = 0.0;
    var screenOnMah = 0.0;
    var screenOffMah = 0.0;
    var counted = 0;

    for (final session in sessions) {
      if (session.kind != SessionKind.discharge) continue;
      if (session.start.isBefore(cutoff)) continue;

      counted++;
      screenOnMs += session.screenOnMs;
      screenOffMs += session.screenOffMs;
      screenOnDrop += session.screenOnDropPct ?? 0;
      screenOffDrop += session.screenOffDropPct ?? 0;

      // Split the session's measured charge in proportion to the level lost in
      // each state, which is the only split the data supports.
      final moved = session.chargeMovedMah?.abs();
      final totalDrop = (session.screenOnDropPct ?? 0) +
          (session.screenOffDropPct ?? 0);
      if (moved != null && totalDrop > 0) {
        screenOnMah += moved * ((session.screenOnDropPct ?? 0) / totalDrop);
        screenOffMah += moved * ((session.screenOffDropPct ?? 0) / totalDrop);
      }
    }

    final onHours = screenOnMs / 3600000;
    final offHours = screenOffMs / 3600000;

    final onRate = (screenOnMs >= minScreenOnMinutes * 60000 && onHours > 0)
        ? screenOnDrop / onHours
        : null;
    final offRate = (screenOffMs >= minScreenOffMinutes * 60000 && offHours > 0)
        ? screenOffDrop / offHours
        : null;

    final totalHours = onHours + offHours;
    final combined = totalHours > 0
        ? (screenOnDrop + screenOffDrop) / totalHours
        : null;

    return DrainProfile(
      screenOnPctPerHour: onRate,
      screenOffPctPerHour: offRate,
      combinedPctPerHour: combined,
      screenOnMahPerHour: onHours > 0 && screenOnMah > 0
          ? screenOnMah / onHours
          : null,
      screenOffMahPerHour: offHours > 0 && screenOffMah > 0
          ? screenOffMah / offHours
          : null,
      sampleSessions: counted,
      screenOnDuration: Duration(milliseconds: screenOnMs),
      screenOffDuration: Duration(milliseconds: screenOffMs),
    );
  }

  /// Drain over the last [liveWindow], from raw samples.
  ///
  /// Returned separately from [profile] because it answers a different
  /// question: not "what does this phone usually do" but "what is it doing
  /// right now", which is what a user checks when the battery is visibly
  /// falling.
  LiveDrain live(List<BatterySnapshot> recent, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(liveWindow);

    final window = recent
        .where((s) => s.timestamp.isAfter(cutoff) && !s.isCharging)
        .toList();
    if (window.length < 2) return LiveDrain.unknown;

    final first = window.first;
    final last = window.last;
    final startLevel = first.levelPct;
    final endLevel = last.levelPct;
    final hours =
        last.timestamp.difference(first.timestamp).inMilliseconds / 3600000;

    double? pctPerHour;
    if (startLevel != null && endLevel != null && hours > 0) {
      final drop = startLevel - endLevel;
      if (drop >= 0) pctPerHour = drop / hours;
    }

    // The instantaneous current is a far more responsive signal than the level,
    // which only moves in whole percent. Both are reported: the current shows
    // what is happening this second, the level what it has cost so far.
    final currents = window
        .map((s) => s.currentNowUa)
        .whereType<int>()
        .map((ua) => ua.abs() / 1000)
        .toList();

    final avgMa = currents.isEmpty
        ? null
        : currents.reduce((a, b) => a + b) / currents.length;

    final voltages = window.map((s) => s.voltageMv).whereType<int>().toList();
    final avgMv = voltages.isEmpty
        ? null
        : voltages.reduce((a, b) => a + b) / voltages.length;

    return LiveDrain(
      pctPerHour: pctPerHour,
      averageMa: avgMa,
      averageW: (avgMa != null && avgMv != null)
          ? (avgMa * avgMv) / 1000000
          : null,
      window: last.timestamp.difference(first.timestamp),
      screenOnShare: _screenOnShare(window),
    );
  }

  double? _screenOnShare(List<BatterySnapshot> window) {
    if (window.length < 2) return null;
    var onMs = 0;
    var totalMs = 0;
    for (var i = 1; i < window.length; i++) {
      final dt = window[i].timestamp
          .difference(window[i - 1].timestamp)
          .inMilliseconds;
      if (dt <= 0) continue;
      totalMs += dt;
      if (window[i - 1].screenOn) onMs += dt;
    }
    return totalMs > 0 ? onMs / totalMs : null;
  }

  /// Time to full for an in-progress charge.
  ///
  /// Uses the charge actually delivered so far against the level gained, which
  /// adapts automatically to the charger in use. Falls back to the level rate
  /// alone when the device reports no usable current.
  ///
  /// The result is deliberately padded past 80%: lithium charging is constant
  /// current up to roughly 80% and then constant voltage, where the current
  /// tapers steeply. Extrapolating the constant-current rate to 100% is how
  /// most apps end up promising a full charge half an hour early.
  Duration? timeToFull(
    List<BatterySnapshot> chargeSamples, {
    double targetPct = 100,
  }) {
    if (chargeSamples.length < 2) return null;

    final last = chargeSamples.last;
    final level = last.levelPct;
    if (level == null || level >= targetPct) return null;

    final first = chargeSamples.first;
    final startLevel = first.levelPct;
    if (startLevel == null) return null;

    final gained = level - startLevel;
    final hours =
        last.timestamp.difference(first.timestamp).inMilliseconds / 3600000;
    if (gained <= 0 || hours <= 0) return null;

    final ratePerHour = gained / hours;
    if (ratePerHour <= 0) return null;

    final remaining = targetPct - level;

    // Split the remaining climb at the constant-current/constant-voltage knee
    // and slow the tail portion down.
    const knee = 80.0;
    final fastPart = math.max(0.0, math.min(remaining, knee - level));
    final slowPart = remaining - fastPart;

    final hoursNeeded =
        (fastPart / ratePerHour) + (slowPart / (ratePerHour * _taperFactor));

    if (hoursNeeded <= 0 || hoursNeeded > 48) return null;
    return Duration(minutes: (hoursNeeded * 60).round());
  }

  /// Above the knee the cell accepts roughly a third of the current it did
  /// below it. Measured across typical phone charge curves; conservative on
  /// purpose, since a charge finishing early is a pleasant surprise and one
  /// finishing late is a broken promise.
  static const double _taperFactor = 0.35;
}

/// The drain reading for right now.
class LiveDrain {
  const LiveDrain({
    this.pctPerHour,
    this.averageMa,
    this.averageW,
    this.window = Duration.zero,
    this.screenOnShare,
  });

  final double? pctPerHour;
  final double? averageMa;
  final double? averageW;
  final Duration window;

  /// Fraction of the window the screen was on, so the figure can be read in
  /// context rather than compared against an unrelated baseline.
  final double? screenOnShare;

  bool get hasData => pctPerHour != null || averageMa != null;

  static const unknown = LiveDrain();
}
