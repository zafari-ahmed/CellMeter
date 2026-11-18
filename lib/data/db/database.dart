import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// CellMeter's local store. Nothing leaves the device.
///
/// The design keeps one immutable fact table ([Samples]) and treats everything
/// else as a cache of analysis over it. That costs disk, and buys the ability
/// to correct the analytics in an update and recompute a user's whole history
/// instead of discarding it.
@DriftDatabase(
  tables: [Samples, Sessions, CapacityLogs, AppUsageSlices, AppSettings],
)
class CellMeterDatabase extends _$CellMeterDatabase {
  CellMeterDatabase() : super(_open());

  CellMeterDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        beforeOpen: (details) async {
          // Sampling writes continuously while the UI reads; WAL lets both
          // proceed without blocking each other.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA busy_timeout = 5000');
          if (details.wasCreated) return;
          await _createIndexes();
        },
      );

  /// Every heavy query in the app is "rows between two timestamps", so the
  /// time columns are indexed explicitly rather than relying on the primary
  /// key, which orders by insertion.
  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples (timestamp_ms)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_start '
      'ON sessions (start_ms DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_kind_start '
      'ON sessions (kind, start_ms DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_usage_session '
      'ON app_usage_slices (session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_usage_start '
      'ON app_usage_slices (start_ms DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_capacity_computed '
      'ON capacity_logs (computed_at_ms DESC)',
    );
  }

  static QueryExecutor _open() => driftDatabase(name: 'cellmeter');
}
