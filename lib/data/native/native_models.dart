/// Dart mirrors of the structures [BatteryChannel] receives from Kotlin.
///
/// Every numeric field is nullable, matching the native side: Android
/// guarantees almost nothing about which battery properties a given device
/// implements, and the difference between "zero" and "not reported" changes
/// what the UI is allowed to claim.
library;

/// Charging state as reported by the platform.
enum ChargingStatus {
  charging,
  discharging,
  full,
  notCharging,
  unknown;

  static ChargingStatus parse(String? raw) => switch (raw) {
        'charging' => ChargingStatus.charging,
        'discharging' => ChargingStatus.discharging,
        'full' => ChargingStatus.full,
        'notCharging' => ChargingStatus.notCharging,
        _ => ChargingStatus.unknown,
      };

  bool get isCharging =>
      this == ChargingStatus.charging || this == ChargingStatus.full;

  String get label => switch (this) {
        ChargingStatus.charging => 'Charging',
        ChargingStatus.discharging => 'Discharging',
        ChargingStatus.full => 'Full',
        ChargingStatus.notCharging => 'Not charging',
        ChargingStatus.unknown => 'Unknown',
      };
}

/// What the device is plugged into. Determines the charge-speed class we
/// compare a session against.
enum PlugType {
  none,
  ac,
  usb,
  wireless,
  dock,
  unknown;

  static PlugType parse(String? raw) => switch (raw) {
        'none' => PlugType.none,
        'ac' => PlugType.ac,
        'usb' => PlugType.usb,
        'wireless' => PlugType.wireless,
        'dock' => PlugType.dock,
        _ => PlugType.unknown,
      };

  String get label => switch (this) {
        PlugType.none => 'Unplugged',
        PlugType.ac => 'AC charger',
        PlugType.usb => 'USB',
        PlugType.wireless => 'Wireless',
        PlugType.dock => 'Dock',
        PlugType.unknown => 'Unknown source',
      };
}

/// The platform's own coarse health verdict. Useful as a warning flag, far too
/// coarse to be the health figure the app reports.
enum BatteryHealthFlag {
  good,
  overheat,
  dead,
  overVoltage,
  cold,
  unspecifiedFailure,
  unknown;

  static BatteryHealthFlag parse(String? raw) => switch (raw) {
        'good' => BatteryHealthFlag.good,
        'overheat' => BatteryHealthFlag.overheat,
        'dead' => BatteryHealthFlag.dead,
        'overVoltage' => BatteryHealthFlag.overVoltage,
        'cold' => BatteryHealthFlag.cold,
        'unspecifiedFailure' => BatteryHealthFlag.unspecifiedFailure,
        _ => BatteryHealthFlag.unknown,
      };

  String get label => switch (this) {
        BatteryHealthFlag.good => 'Good',
        BatteryHealthFlag.overheat => 'Overheating',
        BatteryHealthFlag.dead => 'Dead',
        BatteryHealthFlag.overVoltage => 'Over voltage',
        BatteryHealthFlag.cold => 'Too cold',
        BatteryHealthFlag.unspecifiedFailure => 'Failure reported',
        BatteryHealthFlag.unknown => 'Unknown',
      };

  bool get isProblem =>
      this != BatteryHealthFlag.good && this != BatteryHealthFlag.unknown;
}

/// One instantaneous reading of the battery.
class BatterySnapshot {
  const BatterySnapshot({
    required this.timestamp,
    this.levelPct,
    this.chargeCounterUah,
    this.currentNowUa,
    this.currentAvgUa,
    this.voltageMv,
    this.temperatureC,
    this.energyCounterNwh,
    this.status = ChargingStatus.unknown,
    this.plugType = PlugType.unknown,
    this.health = BatteryHealthFlag.unknown,
    this.technology,
    this.present = true,
    this.screenOn = false,
    this.uptimeMs = 0,
    this.elapsedRealtimeMs = 0,
    this.stateOfHealthPct,
    this.manufacturingDate,
    this.firstUsageDate,
    this.cycleCount,
    this.powerSaveMode = false,
  });

  final DateTime timestamp;

  /// Battery level, 0..100.
  final double? levelPct;

  /// Remaining charge in microamp-hours, straight off the coulomb counter.
  /// The basis of every capacity measurement in the app.
  final int? chargeCounterUah;

  /// Instantaneous current, microamps. Positive charging, negative discharging.
  final int? currentNowUa;
  final int? currentAvgUa;

  final int? voltageMv;
  final double? temperatureC;
  final int? energyCounterNwh;

  final ChargingStatus status;
  final PlugType plugType;
  final BatteryHealthFlag health;
  final String? technology;
  final bool present;

  /// Whether the screen was interactive. Splits screen-on from screen-off drain.
  final bool screenOn;

  /// Milliseconds awake since boot.
  final int uptimeMs;

  /// Milliseconds of wall clock since boot, deep sleep included.
  final int elapsedRealtimeMs;

  /// OEM-reported state of health. Android 14+, frequently absent.
  final int? stateOfHealthPct;

  final DateTime? manufacturingDate;
  final DateTime? firstUsageDate;
  final int? cycleCount;
  final bool powerSaveMode;

  bool get isCharging => status.isCharging;

  /// Instantaneous power, milliwatts, when current and voltage are both known.
  double? get powerMw {
    final ua = currentNowUa;
    final mv = voltageMv;
    if (ua == null || mv == null) return null;
    return (ua * mv) / 1000000;
  }

  /// The fraction of time since boot the device spent in deep sleep. A low
  /// number on an idle phone is the signature of a wakelock problem.
  double? get deepSleepRatio {
    if (elapsedRealtimeMs <= 0) return null;
    final awake = uptimeMs.clamp(0, elapsedRealtimeMs);
    return ((elapsedRealtimeMs - awake) / elapsedRealtimeMs).clamp(0.0, 1.0);
  }

  static BatterySnapshot fromMap(Map<dynamic, dynamic> map) {
    int? asInt(String key) => (map[key] as num?)?.toInt();
    double? asDouble(String key) => (map[key] as num?)?.toDouble();

    DateTime? epochSeconds(String key) {
      final value = asInt(key);
      if (value == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }

    return BatterySnapshot(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        asInt('timestampMs') ?? DateTime.now().millisecondsSinceEpoch,
      ),
      levelPct: asDouble('levelPct'),
      chargeCounterUah: asInt('chargeCounterUah'),
      currentNowUa: asInt('currentNowUa'),
      currentAvgUa: asInt('currentAvgUa'),
      voltageMv: asInt('voltageMv'),
      temperatureC: asDouble('temperatureC'),
      energyCounterNwh: asInt('energyCounterNwh'),
      status: ChargingStatus.parse(map['status'] as String?),
      plugType: PlugType.parse(map['plugType'] as String?),
      health: BatteryHealthFlag.parse(map['health'] as String?),
      technology: map['technology'] as String?,
      present: map['present'] as bool? ?? true,
      screenOn: map['screenOn'] as bool? ?? false,
      uptimeMs: asInt('uptimeMs') ?? 0,
      elapsedRealtimeMs: asInt('elapsedRealtimeMs') ?? 0,
      stateOfHealthPct: asInt('stateOfHealthPct'),
      manufacturingDate: epochSeconds('manufacturingDateSec'),
      firstUsageDate: epochSeconds('firstUsageDateSec'),
      cycleCount: asInt('cycleCount'),
      powerSaveMode: map['powerSaveMode'] as bool? ?? false,
    );
  }

  /// Parses the compact JSON the sampler spools to disk. The keys are
  /// abbreviated there because the file is appended to every few seconds.
  static BatterySnapshot fromSpoolJson(Map<String, dynamic> json) {
    int? asInt(String key) => (json[key] as num?)?.toInt();
    double? asDouble(String key) => (json[key] as num?)?.toDouble();

    DateTime? epochSeconds(String key) {
      final value = asInt(key);
      if (value == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }

    return BatterySnapshot(
      timestamp: DateTime.fromMillisecondsSinceEpoch(asInt('t') ?? 0),
      levelPct: asDouble('lvl'),
      chargeCounterUah: asInt('cc'),
      currentNowUa: asInt('cur'),
      currentAvgUa: asInt('cavg'),
      voltageMv: asInt('mv'),
      temperatureC: asDouble('temp'),
      energyCounterNwh: asInt('nwh'),
      status: ChargingStatus.parse(json['st'] as String?),
      plugType: PlugType.parse(json['plug'] as String?),
      health: BatteryHealthFlag.parse(json['hlth'] as String?),
      technology: json['tech'] as String?,
      present: json['pres'] as bool? ?? true,
      screenOn: json['scr'] as bool? ?? false,
      uptimeMs: asInt('up') ?? 0,
      elapsedRealtimeMs: asInt('ert') ?? 0,
      stateOfHealthPct: asInt('soh'),
      manufacturingDate: epochSeconds('mfg'),
      firstUsageDate: epochSeconds('fu'),
      cycleCount: asInt('cyc'),
      powerSaveMode: json['psm'] as bool? ?? false,
    );
  }
}

/// Where the design capacity figure came from, which decides how much the
/// health percentage can be trusted.
enum DesignCapacitySource {
  sysfs,
  powerProfile,
  userOverride,
  unknown;

  static DesignCapacitySource parse(String? raw) => switch (raw) {
        'sysfs' => DesignCapacitySource.sysfs,
        'powerProfile' => DesignCapacitySource.powerProfile,
        'userOverride' => DesignCapacitySource.userOverride,
        _ => DesignCapacitySource.unknown,
      };

  String get label => switch (this) {
        DesignCapacitySource.sysfs => 'Read from the battery gauge',
        DesignCapacitySource.powerProfile => 'From the device power profile',
        DesignCapacitySource.userOverride => 'Entered by you',
        DesignCapacitySource.unknown => 'Not available',
      };
}

class DesignCapacityInfo {
  const DesignCapacityInfo({this.mah, this.source = DesignCapacitySource.unknown});

  final int? mah;
  final DesignCapacitySource source;

  bool get isKnown => mah != null;

  static DesignCapacityInfo fromMap(Map<dynamic, dynamic> map) =>
      DesignCapacityInfo(
        mah: (map['mah'] as num?)?.toInt(),
        source: DesignCapacitySource.parse(map['source'] as String?),
      );
}

/// Foreground time for one package over a window.
class ForegroundSlice {
  const ForegroundSlice({
    required this.packageName,
    required this.label,
    required this.foregroundMs,
    required this.isSystemApp,
  });

  final String packageName;
  final String label;
  final int foregroundMs;
  final bool isSystemApp;

  Duration get foreground => Duration(milliseconds: foregroundMs);

  static ForegroundSlice fromMap(Map<dynamic, dynamic> map) => ForegroundSlice(
        packageName: map['packageName'] as String? ?? '',
        label: map['label'] as String? ?? '',
        foregroundMs: (map['foregroundMs'] as num?)?.toInt() ?? 0,
        isSystemApp: map['isSystemApp'] as bool? ?? false,
      );
}

/// What the device is and which of the optional capabilities it has. Drives
/// the "why is this value missing" copy throughout the app.
class NativeDeviceInfo {
  const NativeDeviceInfo({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.device,
    required this.sdkInt,
    required this.release,
    required this.hasUsageAccess,
    required this.ignoringBatteryOptimizations,
  });

  final String manufacturer;
  final String brand;
  final String model;
  final String device;
  final int sdkInt;
  final String release;
  final bool hasUsageAccess;
  final bool ignoringBatteryOptimizations;

  String get displayName => '$manufacturer $model';

  static NativeDeviceInfo fromMap(Map<dynamic, dynamic> map) => NativeDeviceInfo(
        manufacturer: map['manufacturer'] as String? ?? 'Unknown',
        brand: map['brand'] as String? ?? '',
        model: map['model'] as String? ?? '',
        device: map['device'] as String? ?? '',
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
        release: map['release'] as String? ?? '',
        hasUsageAccess: map['hasUsageAccess'] as bool? ?? false,
        ignoringBatteryOptimizations:
            map['ignoringBatteryOptimizations'] as bool? ?? false,
      );

  static const empty = NativeDeviceInfo(
    manufacturer: 'Unknown',
    brand: '',
    model: '',
    device: '',
    sdkInt: 0,
    release: '',
    hasUsageAccess: false,
    ignoringBatteryOptimizations: false,
  );
}

/// The alert and sampler settings mirrored on the native side so they keep
/// working with no Dart engine alive.
class MonitorSettings {
  const MonitorSettings({
    this.monitoringEnabled = true,
    this.chargeAlarmEnabled = true,
    this.chargeAlarmPct = 80,
    this.lowBatteryEnabled = true,
    this.lowBatteryPct = 15,
    this.highDrainEnabled = true,
    this.highDrainPctPerHour = 18,
    this.highDrainSustainMinutes = 10,
    this.temperatureAlertEnabled = true,
    this.temperatureAlertC = 42,
    this.showStatsInNotification = true,
  });

  final bool monitoringEnabled;
  final bool chargeAlarmEnabled;
  final int chargeAlarmPct;
  final bool lowBatteryEnabled;
  final int lowBatteryPct;
  final bool highDrainEnabled;
  final double highDrainPctPerHour;
  final int highDrainSustainMinutes;
  final bool temperatureAlertEnabled;
  final double temperatureAlertC;
  final bool showStatsInNotification;

  MonitorSettings copyWith({
    bool? monitoringEnabled,
    bool? chargeAlarmEnabled,
    int? chargeAlarmPct,
    bool? lowBatteryEnabled,
    int? lowBatteryPct,
    bool? highDrainEnabled,
    double? highDrainPctPerHour,
    int? highDrainSustainMinutes,
    bool? temperatureAlertEnabled,
    double? temperatureAlertC,
    bool? showStatsInNotification,
  }) =>
      MonitorSettings(
        monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
        chargeAlarmEnabled: chargeAlarmEnabled ?? this.chargeAlarmEnabled,
        chargeAlarmPct: chargeAlarmPct ?? this.chargeAlarmPct,
        lowBatteryEnabled: lowBatteryEnabled ?? this.lowBatteryEnabled,
        lowBatteryPct: lowBatteryPct ?? this.lowBatteryPct,
        highDrainEnabled: highDrainEnabled ?? this.highDrainEnabled,
        highDrainPctPerHour: highDrainPctPerHour ?? this.highDrainPctPerHour,
        highDrainSustainMinutes:
            highDrainSustainMinutes ?? this.highDrainSustainMinutes,
        temperatureAlertEnabled:
            temperatureAlertEnabled ?? this.temperatureAlertEnabled,
        temperatureAlertC: temperatureAlertC ?? this.temperatureAlertC,
        showStatsInNotification:
            showStatsInNotification ?? this.showStatsInNotification,
      );

  Map<String, dynamic> toMap() => {
        'monitoringEnabled': monitoringEnabled,
        'chargeAlarmEnabled': chargeAlarmEnabled,
        'chargeAlarmPct': chargeAlarmPct,
        'lowBatteryEnabled': lowBatteryEnabled,
        'lowBatteryPct': lowBatteryPct,
        'highDrainEnabled': highDrainEnabled,
        'highDrainPctPerHour': highDrainPctPerHour,
        'highDrainSustainMinutes': highDrainSustainMinutes,
        'temperatureAlertEnabled': temperatureAlertEnabled,
        'temperatureAlertC': temperatureAlertC,
        'showStatsInNotification': showStatsInNotification,
      };

  static MonitorSettings fromMap(Map<dynamic, dynamic> map) => MonitorSettings(
        monitoringEnabled: map['monitoringEnabled'] as bool? ?? true,
        chargeAlarmEnabled: map['chargeAlarmEnabled'] as bool? ?? true,
        chargeAlarmPct: (map['chargeAlarmPct'] as num?)?.toInt() ?? 80,
        lowBatteryEnabled: map['lowBatteryEnabled'] as bool? ?? true,
        lowBatteryPct: (map['lowBatteryPct'] as num?)?.toInt() ?? 15,
        highDrainEnabled: map['highDrainEnabled'] as bool? ?? true,
        highDrainPctPerHour:
            (map['highDrainPctPerHour'] as num?)?.toDouble() ?? 18,
        highDrainSustainMinutes:
            (map['highDrainSustainMinutes'] as num?)?.toInt() ?? 10,
        temperatureAlertEnabled:
            map['temperatureAlertEnabled'] as bool? ?? true,
        temperatureAlertC: (map['temperatureAlertC'] as num?)?.toDouble() ?? 42,
        showStatsInNotification:
            map['showStatsInNotification'] as bool? ?? true,
      );
}
