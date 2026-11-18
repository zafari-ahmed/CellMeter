import '../../data/native/native_models.dart';

enum SessionKind {
  charge,
  discharge;

  static SessionKind parse(String raw) =>
      raw == 'charge' ? SessionKind.charge : SessionKind.discharge;

  String get wire => this == SessionKind.charge ? 'charge' : 'discharge';

  String get label => this == SessionKind.charge ? 'Charge' : 'Discharge';
}

/// How the charge moved during a session was measured.
enum ChargeMethod {
  /// Differenced from the coulomb counter. Accurate, and what the whole
  /// capacity measurement rests on when available.
  coulomb,

  /// Integrated from current readings over time. Usable, but it accumulates
  /// the error of every sample and of the gaps between them.
  integrated,

  /// Neither was possible on this device.
  none;

  static ChargeMethod parse(String raw) => switch (raw) {
        'coulomb' => ChargeMethod.coulomb,
        'integrated' => ChargeMethod.integrated,
        _ => ChargeMethod.none,
      };

  String get wire => switch (this) {
        ChargeMethod.coulomb => 'coulomb',
        ChargeMethod.integrated => 'integrated',
        ChargeMethod.none => 'none',
      };

  String get label => switch (this) {
        ChargeMethod.coulomb => 'Measured from the battery gauge',
        ChargeMethod.integrated => 'Estimated from current readings',
        ChargeMethod.none => 'Not measured',
      };
}

/// How much the app trusts a capacity figure.
enum Confidence {
  low,
  medium,
  high;

  static Confidence parse(String raw) => switch (raw) {
        'high' => Confidence.high,
        'medium' => Confidence.medium,
        _ => Confidence.low,
      };

  String get wire => name;

  String get label => switch (this) {
        Confidence.low => 'Still measuring',
        Confidence.medium => 'Reasonable',
        Confidence.high => 'Confident',
      };
}

/// A completed charge or discharge, with everything the UI needs to describe
/// it without going back to the raw samples.
class BatterySession {
  const BatterySession({
    required this.id,
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

  final int id;
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

  /// Signed level change: positive for a charge, negative for a discharge.
  double get levelDeltaPct => endLevelPct - startLevelPct;

  /// Magnitude of the level change, which is what quality gates compare.
  double get levelSpanPct => levelDeltaPct.abs();

  Duration get screenOn => Duration(milliseconds: screenOnMs);
  Duration get screenOff => Duration(milliseconds: screenOffMs);

  /// Average rate of change in percentage points per hour.
  double? get pctPerHour {
    final hours = duration.inMilliseconds / 3600000;
    if (hours <= 0) return null;
    return levelSpanPct / hours;
  }

  /// Drain while the screen was on. The number most users actually want: it
  /// answers "how long will this last while I use it".
  double? get screenOnPctPerHour {
    final drop = screenOnDropPct;
    if (drop == null || screenOnMs <= 0) return null;
    return drop / (screenOnMs / 3600000);
  }

  /// Standby drain. A high value here is the signature of a misbehaving app
  /// holding the device awake.
  double? get screenOffPctPerHour {
    final drop = screenOffDropPct;
    if (drop == null || screenOffMs <= 0) return null;
    return drop / (screenOffMs / 3600000);
  }

  /// Average charging power in watts, for comparing chargers and cables.
  double? get avgPowerW {
    final ma = avgCurrentMa;
    final mv = avgVoltageMv;
    if (ma == null || mv == null) return null;
    return (ma.abs() * mv) / 1000000;
  }
}

/// How fast a charger delivered power, as a label a person can act on.
enum ChargeSpeedClass {
  slow,
  standard,
  fast,
  veryFast;

  /// Thresholds are in watts rather than amps because a 2 A reading means
  /// something quite different at 5 V than at 9 V, and the user is comparing
  /// chargers, not currents.
  static ChargeSpeedClass fromWatts(double watts) {
    if (watts < 5) return ChargeSpeedClass.slow;
    if (watts < 12) return ChargeSpeedClass.standard;
    if (watts < 25) return ChargeSpeedClass.fast;
    return ChargeSpeedClass.veryFast;
  }

  String get label => switch (this) {
        ChargeSpeedClass.slow => 'Slow',
        ChargeSpeedClass.standard => 'Standard',
        ChargeSpeedClass.fast => 'Fast',
        ChargeSpeedClass.veryFast => 'Very fast',
      };
}
