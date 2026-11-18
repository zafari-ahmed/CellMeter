import 'package:drift/drift.dart';

/// Raw battery readings, exactly as the sampler recorded them.
///
/// This is the app's source of truth and the only table that is never derived
/// from anything else. Sessions, capacity estimates and every chart are
/// recomputed from these rows, so a bug in the analytics can be fixed by
/// rebuilding rather than by asking the user to collect another month of data.
///
/// Rows arrive from the native spool. Null means "this device does not report
/// that value", which the analytics must distinguish from zero.
class Samples extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Epoch milliseconds. Indexed; almost every query is a time range.
  IntColumn get timestampMs => integer()();

  RealColumn get levelPct => real().nullable()();

  /// Coulomb counter, microamp-hours remaining.
  IntColumn get chargeCounterUah => integer().nullable()();

  /// Microamps. Positive charging, negative discharging.
  IntColumn get currentNowUa => integer().nullable()();
  IntColumn get currentAvgUa => integer().nullable()();

  IntColumn get voltageMv => integer().nullable()();
  RealColumn get temperatureC => real().nullable()();
  IntColumn get energyCounterNwh => integer().nullable()();

  TextColumn get status => text().withLength(min: 1, max: 20)();
  TextColumn get plugType => text().withLength(min: 1, max: 20)();
  TextColumn get health => text().withLength(min: 1, max: 24)();
  TextColumn get technology => text().nullable()();

  BoolColumn get screenOn => boolean().withDefault(const Constant(false))();
  BoolColumn get powerSaveMode => boolean().withDefault(const Constant(false))();

  /// Awake and wall-clock milliseconds since boot. Their difference is deep
  /// sleep, which is how standby drain problems are diagnosed.
  IntColumn get uptimeMs => integer().withDefault(const Constant(0))();
  IntColumn get elapsedRealtimeMs =>
      integer().withDefault(const Constant(0))();

  IntColumn get cycleCount => integer().nullable()();
  IntColumn get stateOfHealthPct => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        // The spool is re-read when an ingest is interrupted, so the same
        // sample can be offered twice. The timestamp is unique per reading.
        {timestampMs},
      ];
}

/// A continuous stretch of charging or discharging.
///
/// Derived from [Samples] by the segmenter. Stored rather than recomputed on
/// every screen because history views scan months of data, and because a
/// session carries judgements (was it clean enough to measure capacity from?)
/// that should stay stable once made.
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'charge' or 'discharge'.
  TextColumn get kind => text().withLength(min: 1, max: 12)();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  RealColumn get startLevelPct => real()();
  RealColumn get endLevelPct => real()();

  /// Charge counter at each end, microamp-hours. Their difference over the
  /// level change is the capacity measurement.
  IntColumn get startChargeUah => integer().nullable()();
  IntColumn get endChargeUah => integer().nullable()();

  /// Charge moved during the session, mAh. Measured from the coulomb counter
  /// when it is trustworthy, otherwise integrated from the current readings.
  RealColumn get chargeMovedMah => real().nullable()();

  /// How [chargeMovedMah] was obtained: 'coulomb', 'integrated' or 'none'.
  TextColumn get chargeMethod => text().withLength(min: 1, max: 16)
      .withDefault(const Constant('none'))();

  RealColumn get avgCurrentMa => real().nullable()();
  RealColumn get maxCurrentMa => real().nullable()();
  RealColumn get avgTemperatureC => real().nullable()();
  RealColumn get maxTemperatureC => real().nullable()();
  RealColumn get avgVoltageMv => real().nullable()();

  /// Milliseconds of the session spent with the screen on and off. Drives the
  /// screen-on and screen-off drain rates shown separately throughout the app.
  IntColumn get screenOnMs => integer().withDefault(const Constant(0))();
  IntColumn get screenOffMs => integer().withDefault(const Constant(0))();

  /// Level lost while the screen was on, and while it was off.
  RealColumn get screenOnDropPct => real().nullable()();
  RealColumn get screenOffDropPct => real().nullable()();

  /// Dominant plug type for a charge session.
  TextColumn get plugType => text().nullable()();

  IntColumn get sampleCount => integer().withDefault(const Constant(0))();

  /// Longest gap between consecutive samples, milliseconds. A large gap means
  /// the sampler was suspended, which is the main reason a session is rejected
  /// for capacity measurement.
  IntColumn get maxGapMs => integer().withDefault(const Constant(0))();

  /// Whether this session met the quality bar for a capacity measurement.
  BoolColumn get usableForCapacity =>
      boolean().withDefault(const Constant(false))();

  /// Why it was not, in plain words. Shown in the UI so a user is never left
  /// wondering why their charge did not count.
  TextColumn get rejectionReason => text().nullable()();

  /// Full capacity implied by this session alone, mAh.
  RealColumn get impliedCapacityMah => real().nullable()();

  /// Battery wear attributed to this session, in charge cycles
  /// (level moved / 100).
  RealColumn get cyclesUsed => real().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {kind, startMs},
      ];
}

/// The app's running estimate of true full-charge capacity.
///
/// One row is appended whenever the estimate is recomputed, which keeps the
/// history of the estimate itself — useful for showing that measurement has
/// settled, and for spotting a battery replacement as a step change.
class CapacityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get computedAtMs => integer()();

  /// Best estimate of full capacity, mAh.
  RealColumn get estimatedMah => real()();

  /// Design capacity used for the health percentage, mAh.
  IntColumn get designMah => integer().nullable()();

  /// Health as a percentage of design capacity.
  RealColumn get healthPct => real().nullable()();

  /// How many sessions the estimate was built from, and how wide they were.
  IntColumn get sessionCount => integer()();
  RealColumn get totalLevelSpanPct => real()();

  /// Spread of the underlying per-session estimates, mAh. A wide spread is
  /// what "still measuring" looks like, and the UI says so rather than
  /// presenting a single confident number.
  RealColumn get spreadMah => real().nullable()();

  /// 'low', 'medium' or 'high'.
  TextColumn get confidence =>
      text().withLength(min: 1, max: 10).withDefault(const Constant('low'))();
}

/// Foreground time per app over a window, paired with the charge the battery
/// actually lost over the same window.
///
/// Attribution is proportional: CellMeter measures total charge lost exactly,
/// then divides it by foreground time. It never claims a per-app wattage,
/// because Android gives no way to measure one.
class AppUsageSlices extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The discharge session this slice belongs to.
  IntColumn get sessionId => integer().nullable()();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  TextColumn get packageName => text()();
  TextColumn get appLabel => text()();
  BoolColumn get isSystemApp => boolean().withDefault(const Constant(false))();

  IntColumn get foregroundMs => integer()();

  /// Charge attributed to this app, mAh, by share of foreground time.
  RealColumn get attributedMah => real().nullable()();

  /// Level attributed to this app, percentage points.
  RealColumn get attributedPct => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {startMs, packageName},
      ];
}

/// Key/value store for everything the user can change.
///
/// A table rather than shared preferences so settings sit in the same backup
/// and export as the measurements they affect — a capacity reading means
/// little without the design capacity it was compared against.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
