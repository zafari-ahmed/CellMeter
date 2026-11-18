import 'package:cellmeter/data/native/native_models.dart';

/// Sample generators that behave like a real device.
///
/// These model the physics rather than drawing a straight line: charge
/// accumulates continuously from the current, and the reported level is the
/// quantised consequence of it. That matters because several of the
/// segmenter's decisions — above all whether a device's charge counter is real
/// or derived from the level — turn precisely on the difference between a
/// measured quantity and a computed one. A fixture that interpolated both
/// linearly would be indistinguishable from the fake it is supposed to catch.
abstract final class Fixtures {
  /// A charge from [startLevelPct] to [endLevelPct] on a battery that really
  /// holds [capacityMah].
  ///
  /// The coulomb counter integrates the current; the level is floor()ed from
  /// it, exactly as a device reports it. So the implied capacity recovered by
  /// the segmenter should come back close to [capacityMah], limited only by
  /// the one-percent level quantisation.
  static List<BatterySnapshot> charge({
    required DateTime start,
    required double capacityMah,
    required double startLevelPct,
    required double endLevelPct,
    Duration interval = const Duration(seconds: 30),
    int currentUa = 1500000,
    double temperatureC = 30,
    bool screenOn = false,
    int voltageMv = 4100,
  }) {
    final capacityUah = capacityMah * 1000;
    final targetUah = capacityUah * (endLevelPct / 100);
    final perSampleUah = currentUa * (interval.inMilliseconds / 3600000);

    var chargeUah = capacityUah * (startLevelPct / 100);
    var at = start;
    final samples = <BatterySnapshot>[];

    while (chargeUah <= targetUah) {
      samples.add(
        BatterySnapshot(
          timestamp: at,
          levelPct: (chargeUah / capacityUah * 100).floorToDouble(),
          chargeCounterUah: chargeUah.round(),
          currentNowUa: currentUa,
          voltageMv: voltageMv,
          temperatureC: temperatureC,
          status: ChargingStatus.charging,
          plugType: PlugType.ac,
          health: BatteryHealthFlag.good,
          screenOn: screenOn,
        ),
      );
      chargeUah += perSampleUah;
      at = at.add(interval);
    }

    return samples;
  }

  /// A discharge, built the same way: charge drains at [currentUa] and the
  /// level follows.
  static List<BatterySnapshot> discharge({
    required DateTime start,
    required double capacityMah,
    required double startLevelPct,
    required double endLevelPct,
    Duration interval = const Duration(minutes: 1),
    int currentUa = 400000,
    double temperatureC = 28,
    bool screenOn = false,
    int voltageMv = 3800,
  }) {
    final capacityUah = capacityMah * 1000;
    final targetUah = capacityUah * (endLevelPct / 100);
    final perSampleUah = currentUa * (interval.inMilliseconds / 3600000);

    var chargeUah = capacityUah * (startLevelPct / 100);
    var at = start;
    final samples = <BatterySnapshot>[];

    while (chargeUah >= targetUah) {
      samples.add(
        BatterySnapshot(
          timestamp: at,
          levelPct: (chargeUah / capacityUah * 100).floorToDouble(),
          chargeCounterUah: chargeUah.round(),
          currentNowUa: -currentUa,
          voltageMv: voltageMv,
          temperatureC: temperatureC,
          status: ChargingStatus.discharging,
          plugType: PlugType.none,
          health: BatteryHealthFlag.good,
          screenOn: screenOn,
        ),
      );
      chargeUah -= perSampleUah;
      at = at.add(interval);
    }

    return samples;
  }

  /// A device whose charge counter is really `level x constant`.
  ///
  /// This is the case the app has to catch: the arithmetic works, the numbers
  /// look plausible, and the capacity it implies is the design figure no
  /// matter how worn the cell is.
  static List<BatterySnapshot> chargeWithDerivedCounter({
    required DateTime start,
    required double designMah,
    required double startLevelPct,
    required double endLevelPct,
    Duration interval = const Duration(minutes: 1),
    int samplesPerPercent = 3,
  }) {
    final samples = <BatterySnapshot>[];
    var at = start;

    for (var level = startLevelPct; level <= endLevelPct; level++) {
      for (var i = 0; i < samplesPerPercent; i++) {
        samples.add(
          BatterySnapshot(
            timestamp: at,
            levelPct: level,
            // The whole problem in one line.
            chargeCounterUah: (level * designMah * 10).round(),
            currentNowUa: 1500000,
            voltageMv: 4100,
            temperatureC: 30,
            status: ChargingStatus.charging,
            plugType: PlugType.ac,
            health: BatteryHealthFlag.good,
          ),
        );
        at = at.add(interval);
      }
    }

    return samples;
  }

  /// A device that reports no coulomb counter at all, only current.
  static List<BatterySnapshot> chargeWithoutCounter({
    required DateTime start,
    required double capacityMah,
    required double startLevelPct,
    required double endLevelPct,
    Duration interval = const Duration(seconds: 30),
    int currentUa = 2000000,
  }) =>
      charge(
        start: start,
        capacityMah: capacityMah,
        startLevelPct: startLevelPct,
        endLevelPct: endLevelPct,
        interval: interval,
        currentUa: currentUa,
      ).map((s) => _withoutCounter(s)).toList();

  static BatterySnapshot _withoutCounter(BatterySnapshot s) => BatterySnapshot(
        timestamp: s.timestamp,
        levelPct: s.levelPct,
        chargeCounterUah: null,
        currentNowUa: s.currentNowUa,
        voltageMv: s.voltageMv,
        temperatureC: s.temperatureC,
        status: s.status,
        plugType: s.plugType,
        health: s.health,
        screenOn: s.screenOn,
      );

  /// Re-stamps a run with a new screen state, for building a session that
  /// spans a screen-on and a screen-off stretch.
  static List<BatterySnapshot> withScreen(
    List<BatterySnapshot> samples, {
    required bool screenOn,
  }) =>
      samples
          .map((s) => BatterySnapshot(
                timestamp: s.timestamp,
                levelPct: s.levelPct,
                chargeCounterUah: s.chargeCounterUah,
                currentNowUa: s.currentNowUa,
                voltageMv: s.voltageMv,
                temperatureC: s.temperatureC,
                status: s.status,
                plugType: s.plugType,
                health: s.health,
                screenOn: screenOn,
              ))
          .toList();
}
