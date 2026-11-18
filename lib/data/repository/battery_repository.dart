import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../domain/analytics/app_attributor.dart';
import '../../domain/analytics/capacity_estimator.dart';
import '../../domain/analytics/drain_analyzer.dart';
import '../../domain/analytics/session_segmenter.dart';
import '../../domain/models/session_models.dart';
import '../db/database.dart';
import '../db/retention.dart';
import '../native/battery_channel.dart';
import '../native/native_models.dart';

/// The one place that moves data between the sampler, the database and the
/// analytics.
///
/// Screens never touch drift or the method channel directly. That keeps the
/// analysis pipeline — ingest, segment, estimate — in a single sequence that
/// can be read top to bottom, and means the UI cannot accidentally recompute a
/// month of history while building a widget.
class BatteryRepository {
  BatteryRepository({
    required CellMeterDatabase database,
    required BatteryChannel channel,
    SessionSegmenter? segmenter,
    CapacityEstimator? estimator,
    DrainAnalyzer? drainAnalyzer,
    AppAttributor? attributor,
    RetentionPolicy retention = RetentionPolicy.free,
  })  : _db = database,
        _channel = channel,
        _retention = retention,
        _segmenter = segmenter ?? const SessionSegmenter(),
        _estimator = estimator ?? const CapacityEstimator(),
        _drain = drainAnalyzer ?? const DrainAnalyzer(),
        _attributor = attributor ?? const AppAttributor();

  final CellMeterDatabase _db;
  final BatteryChannel _channel;
  final SessionSegmenter _segmenter;
  final CapacityEstimator _estimator;
  final DrainAnalyzer _drain;
  final AppAttributor _attributor;
  final RetentionPolicy _retention;

  /// Guards the ingest pipeline. Several things can trigger a sync at once —
  /// app resume, a pull to refresh, the periodic timer — and running two
  /// ingests concurrently would double-insert and corrupt the session rebuild.
  Future<void>? _syncInFlight;

  // --------------------------------------------------------------- ingest

  /// Pulls spooled samples into the database and rebuilds the analysis.
  ///
  /// Safe to call as often as the UI likes; overlapping calls join the one
  /// already running rather than starting another.
  Future<SyncResult> sync({bool rebuildSessions = true}) async {
    if (_syncInFlight != null) {
      await _syncInFlight;
      return const SyncResult(ingested: 0, sessionsWritten: 0, joined: true);
    }

    final completer = Completer<void>();
    _syncInFlight = completer.future;
    try {
      final result = await _sync(rebuildSessions: rebuildSessions);
      return result;
    } finally {
      completer.complete();
      _syncInFlight = null;
    }
  }

  Future<SyncResult> _sync({required bool rebuildSessions}) async {
    var ingested = 0;

    // Drain the spool in batches so a long offline stretch does not build one
    // enormous transaction.
    while (true) {
      final batch = await _channel.readSpool(maxLines: _ingestBatchSize);
      if (batch.isEmpty) break;

      await _insertSamples(batch.snapshots);
      // Only now is it safe to drop them from the spool.
      await _channel.consumeSpool(batch.lineCount);
      ingested += batch.snapshots.length;

      if (batch.lineCount < _ingestBatchSize) break;
    }

    var sessionsWritten = 0;
    if (rebuildSessions && ingested > 0) {
      sessionsWritten = await rebuildRecentSessions();
      await _recomputeCapacity();
    }

    await _prune();
    return SyncResult(ingested: ingested, sessionsWritten: sessionsWritten);
  }

  Future<void> _insertSamples(List<BatterySnapshot> snapshots) async {
    if (snapshots.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(
        _db.samples,
        snapshots.map(_toCompanion),
        // A sample is identified by its timestamp. Re-offering one after an
        // interrupted ingest is expected and must be a no-op.
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  SamplesCompanion _toCompanion(BatterySnapshot s) => SamplesCompanion.insert(
        timestampMs: s.timestamp.millisecondsSinceEpoch,
        levelPct: Value(s.levelPct),
        chargeCounterUah: Value(s.chargeCounterUah),
        currentNowUa: Value(s.currentNowUa),
        currentAvgUa: Value(s.currentAvgUa),
        voltageMv: Value(s.voltageMv),
        temperatureC: Value(s.temperatureC),
        energyCounterNwh: Value(s.energyCounterNwh),
        status: s.status.name,
        plugType: s.plugType.name,
        health: s.health.name,
        technology: Value(s.technology),
        screenOn: Value(s.screenOn),
        powerSaveMode: Value(s.powerSaveMode),
        uptimeMs: Value(s.uptimeMs),
        elapsedRealtimeMs: Value(s.elapsedRealtimeMs),
        cycleCount: Value(s.cycleCount),
        stateOfHealthPct: Value(s.stateOfHealthPct),
      );

  // ------------------------------------------------------------- sessions

  /// Re-segments the recent past and writes the sessions back.
  ///
  /// Rebuilds a window rather than only appending, because the newest session
  /// is almost always still open: the charge that was in progress last time is
  /// now longer, or finished. Re-deriving the window and upserting is simpler
  /// and more robust than trying to patch a session in place.
  Future<int> rebuildRecentSessions({Duration? window}) async {
    final span = window ?? const Duration(days: 3);
    final from = DateTime.now().subtract(span);

    final samples = await samplesBetween(from, DateTime.now());
    if (samples.length < 2) return 0;

    final sessions = _segmenter.segment(samples);
    if (sessions.isEmpty) return 0;

    // Replace the window wholesale instead of upserting row by row. The newest
    // session is usually still open — the charge that was in progress last time
    // is now longer or finished — so patching in place would mean reconciling a
    // moving end time against a stored one. Deleting the derived rows for the
    // window and re-inserting what the segmenter just produced keeps the
    // database a pure function of the samples, which is the property the whole
    // rebuild story depends on.
    final windowStartMs = sessions.first.start.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.delete(_db.sessions)
            ..where((t) => t.startMs.isBiggerOrEqualValue(windowStartMs)))
          .go();
      await _db.batch((batch) {
        batch.insertAll(_db.sessions, sessions.map(_sessionCompanion));
      });
    });

    return sessions.length;
  }

  SessionsCompanion _sessionCompanion(SegmentedSession s) =>
      SessionsCompanion.insert(
        kind: s.kind.wire,
        startMs: s.start.millisecondsSinceEpoch,
        endMs: s.end.millisecondsSinceEpoch,
        startLevelPct: s.startLevelPct,
        endLevelPct: s.endLevelPct,
        startChargeUah: Value(s.startChargeUah),
        endChargeUah: Value(s.endChargeUah),
        chargeMovedMah: Value(s.chargeMovedMah),
        chargeMethod: Value(s.chargeMethod.wire),
        avgCurrentMa: Value(s.avgCurrentMa),
        maxCurrentMa: Value(s.maxCurrentMa),
        avgTemperatureC: Value(s.avgTemperatureC),
        maxTemperatureC: Value(s.maxTemperatureC),
        avgVoltageMv: Value(s.avgVoltageMv),
        screenOnMs: Value(s.screenOnMs),
        screenOffMs: Value(s.screenOffMs),
        screenOnDropPct: Value(s.screenOnDropPct),
        screenOffDropPct: Value(s.screenOffDropPct),
        plugType: Value(s.plugType?.name),
        sampleCount: Value(s.sampleCount),
        maxGapMs: Value(s.maxGapMs),
        usableForCapacity: Value(s.usableForCapacity),
        rejectionReason: Value(s.rejectionReason),
        impliedCapacityMah: Value(s.impliedCapacityMah),
        cyclesUsed: Value(s.cyclesUsed),
      );

  /// Rebuilds every session from the full sample history.
  ///
  /// Exists so an improvement to the segmenter can be applied to data the user
  /// already collected, instead of only to whatever they record from now on.
  Future<int> rebuildAllSessions() async {
    final samples = await samplesBetween(
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.now(),
    );
    if (samples.length < 2) return 0;

    final sessions = _segmenter.segment(samples);
    await _db.transaction(() async {
      await _db.delete(_db.sessions).go();
      await _db.batch((batch) {
        batch.insertAll(_db.sessions, sessions.map(_sessionCompanion));
      });
    });
    await _recomputeCapacity();
    return sessions.length;
  }

  // ---------------------------------------------------------------- reads

  Future<List<BatterySnapshot>> samplesBetween(
    DateTime from,
    DateTime to,
  ) async {
    final query = _db.select(_db.samples)
      ..where((t) =>
          t.timestampMs.isBiggerOrEqualValue(from.millisecondsSinceEpoch) &
          t.timestampMs.isSmallerOrEqualValue(to.millisecondsSinceEpoch))
      ..orderBy([(t) => OrderingTerm.asc(t.timestampMs)]);

    final rows = await query.get();
    return rows.map(_fromRow).toList(growable: false);
  }

  /// The most recent samples, newest last. Used by the live drain reading.
  Future<List<BatterySnapshot>> recentSamples({
    Duration window = const Duration(hours: 2),
  }) =>
      samplesBetween(DateTime.now().subtract(window), DateTime.now());

  Stream<List<BatterySession>> watchSessions({
    SessionKind? kind,
    int limit = 100,
  }) {
    final query = _db.select(_db.sessions)
      ..orderBy([(t) => OrderingTerm.desc(t.startMs)])
      ..limit(limit);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind.wire));
    }
    return query.watch().map((rows) => rows.map(_toSession).toList());
  }

  Future<List<BatterySession>> sessions({
    SessionKind? kind,
    DateTime? since,
    int limit = 200,
  }) async {
    final query = _db.select(_db.sessions)
      ..orderBy([(t) => OrderingTerm.desc(t.startMs)])
      ..limit(limit);
    if (kind != null) query.where((t) => t.kind.equals(kind.wire));
    if (since != null) {
      query.where(
        (t) => t.startMs.isBiggerOrEqualValue(since.millisecondsSinceEpoch),
      );
    }
    final rows = await query.get();
    return rows.map(_toSession).toList(growable: false);
  }

  Future<List<SegmentedSession>> _segmentedSessions({
    DateTime? since,
    int limit = 400,
  }) async {
    final list = await sessions(since: since, limit: limit);
    return list.map(_toSegmented).toList(growable: false);
  }

  // ------------------------------------------------------------- analysis

  /// Current capacity and health.
  Future<CapacityEstimate> capacityEstimate() async {
    final design = await _channel.designCapacity();
    final segmented = await _segmentedSessions();
    final oemHealth = await _latestOemStateOfHealth();

    return _estimator.estimate(
      sessions: segmented,
      designMah: design.mah,
      oemStateOfHealthPct: oemHealth,
    );
  }

  Future<int?> _latestOemStateOfHealth() async {
    final query = _db.select(_db.samples)
      ..where((t) => t.stateOfHealthPct.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.timestampMs)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.stateOfHealthPct;
  }

  Future<void> _recomputeCapacity() async {
    final estimate = await capacityEstimate();
    if (estimate.isEmpty) return;

    await _db.into(_db.capacityLogs).insert(
          CapacityLogsCompanion.insert(
            computedAtMs: DateTime.now().millisecondsSinceEpoch,
            estimatedMah: estimate.estimatedMah,
            designMah: Value(estimate.designMah),
            healthPct: Value(estimate.healthPct),
            sessionCount: estimate.sessionCount,
            totalLevelSpanPct: estimate.totalLevelSpanPct,
            spreadMah: Value(estimate.spreadMah),
            confidence: Value(estimate.confidence.wire),
          ),
        );
  }

  /// The trend of the capacity estimate itself, which is how a user sees that
  /// measurement has settled — or that a battery was replaced.
  Future<List<CapacityLog>> capacityHistory({int limit = 120}) async {
    final query = _db.select(_db.capacityLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.computedAtMs)])
      ..limit(limit);
    final rows = await query.get();
    return rows.reversed.toList(growable: false);
  }

  Future<DrainProfile> drainProfile() async {
    final segmented = await _segmentedSessions(
      since: DateTime.now().subtract(const Duration(days: 14)),
    );
    return _drain.profile(segmented);
  }

  Future<LiveDrain> liveDrain() async {
    final samples = await recentSamples(window: const Duration(hours: 1));
    return _drain.live(samples);
  }

  /// Time until the in-progress charge reaches [targetPct], or null if the
  /// device is not charging.
  Future<Duration?> timeToFull({double targetPct = 100}) async {
    final samples = await recentSamples(window: const Duration(hours: 6));
    final charging = <BatterySnapshot>[];
    // Walk back from the newest sample and keep the trailing charging run.
    for (final sample in samples.reversed) {
      if (!sample.isCharging) break;
      charging.insert(0, sample);
    }
    if (charging.length < 2) return null;
    return _drain.timeToFull(charging, targetPct: targetPct);
  }

  /// Per-app consumption over the recent discharge sessions.
  ///
  /// Returns an empty list when Usage Access has not been granted; the UI
  /// checks that separately and explains how to turn it on rather than showing
  /// an empty chart.
  Future<AppUsageReport> appUsage({
    Duration window = const Duration(days: 1),
  }) async {
    if (!await _channel.hasUsageAccess()) {
      return const AppUsageReport(
        apps: [],
        unattributedPct: 0,
        hasAccess: false,
        hasDischargeData: false,
        isAttributed: false,
      );
    }

    final since = DateTime.now().subtract(window);
    final discharges = (await _segmentedSessions(since: since))
        .where((s) => s.kind == SessionKind.discharge)
        .toList();

    // Include the discharge that is still running.
    //
    // Stored sessions only ever cover completed runs, because a session that
    // is still growing has no final totals. On its own that leaves this screen
    // blank for the whole of a day's use until the user next plugs in — which
    // is exactly backwards, since the moment people ask where the battery went
    // is while it is going.
    final live = await _openDischargeSession();
    if (live != null) discharges.add(live);

    final perSession = <List<AppConsumption>>[];
    for (final session in discharges) {
      final slices = await _channel.foregroundSlices(
        start: session.start,
        end: session.end,
      );
      if (slices.isEmpty) continue;
      perSession.add(
        _attributor.attribute(session: session, slices: slices),
      );
    }

    final merged = _attributor.merge(perSession);
    if (merged.isNotEmpty) {
      return AppUsageReport(
        apps: merged,
        unattributedPct: _attributor.unattributedPct(
          sessions: discharges,
          attributed: merged,
        ),
        hasAccess: true,
        hasDischargeData: true,
        isAttributed: true,
      );
    }

    // Nothing could be attributed — the only discharges were short, or spent
    // with the screen off. Rather than show an empty screen, fall back to
    // plain foreground time across the whole window.
    //
    // This is a weaker claim and the UI says so, but it is the honest one: a
    // phone that is plugged in most of the day has almost no discharge to
    // divide up, and "here is what you actually used" is far more use than
    // "come back later". It also degrades the right way — as soon as there is
    // a real discharge to measure, the stronger attribution takes over.
    final slices = await _channel.foregroundSlices(
      start: since,
      end: DateTime.now(),
    );

    return AppUsageReport(
      apps: _attributor.fromForegroundOnly(slices),
      unattributedPct: 0,
      hasAccess: true,
      hasDischargeData: discharges.isNotEmpty,
      isAttributed: false,
    );
  }

  /// The discharge in progress, or null if the device is charging.
  ///
  /// Derived from the raw samples with an open-ended segment rather than read
  /// from the sessions table, which by design holds only finished runs.
  Future<SegmentedSession?> _openDischargeSession() async {
    final samples = await recentSamples(window: const Duration(hours: 12));
    if (samples.length < 2) return null;

    final sessions = _segmenter.segment(samples, openEnded: true);
    if (sessions.isEmpty) return null;

    // Only the trailing run is still open; everything before it is already
    // stored and would be counted twice.
    final open = sessions.last;
    return open.kind == SessionKind.discharge ? open : null;
  }

  /// Charge cycles consumed, counted as battery moved divided by 100.
  ///
  /// This is the meaningful definition: ten 10% top-ups wear a cell about as
  /// much as one full cycle, which is why partial charging is gentler and why
  /// counting "times plugged in" would be misleading.
  Future<double> cyclesUsed({DateTime? since}) async {
    final list = await sessions(kind: SessionKind.charge, since: since, limit: 5000);
    return list.fold<double>(0, (sum, s) => sum + s.cyclesUsed);
  }

  // ----------------------------------------------------------- maintenance

  /// Ages out data past the retention policy.
  ///
  /// Raw samples go first and hardest: they are the bulk of the database and
  /// the sessions derived from them survive, so the user keeps their history
  /// without the app growing without bound.
  Future<void> _prune() async {
    final now = DateTime.now();
    int cutoff(Duration d) =>
        now.subtract(d).millisecondsSinceEpoch;

    await (_db.delete(_db.samples)
          ..where((t) =>
              t.timestampMs.isSmallerThanValue(cutoff(_retention.rawSamples))))
        .go();

    await (_db.delete(_db.sessions)
          ..where((t) =>
              t.startMs.isSmallerThanValue(cutoff(_retention.sessions))))
        .go();

    await (_db.delete(_db.appUsageSlices)
          ..where((t) =>
              t.startMs.isSmallerThanValue(cutoff(_retention.appUsage))))
        .go();

    await (_db.delete(_db.capacityLogs)
          ..where((t) => t.computedAtMs
              .isSmallerThanValue(cutoff(_retention.capacityEstimates))))
        .go();
  }

  /// Wipes measurement history, for when the battery has been replaced.
  ///
  /// A replaced cell makes every previous capacity reading describe a
  /// different battery, and without this the median would keep the old value
  /// alive for months. Competing apps make users clear app data for this;
  /// having it as a first-class action is the difference between a tool that
  /// handles a real event and one that does not.
  Future<void> resetForNewBattery() async {
    await _db.transaction(() async {
      await _db.delete(_db.capacityLogs).go();
      await _db.delete(_db.sessions).go();
      await _db.delete(_db.samples).go();
      await _db.delete(_db.appUsageSlices).go();
    });
    await _channel.clearSpool();
    debugPrint('CellMeter: measurement history reset for a new battery');
  }

  /// Database size in bytes, approximated from row counts for the diagnostics
  /// screen.
  Future<DatabaseStats> stats() async {
    Future<int> countOf(TableInfo table) async {
      final row = await _db
          .customSelect('SELECT COUNT(*) AS c FROM ${table.actualTableName}')
          .getSingle();
      return row.read<int>('c');
    }

    return DatabaseStats(
      sampleCount: await countOf(_db.samples),
      sessionCount: await countOf(_db.sessions),
      estimateCount: await countOf(_db.capacityLogs),
      spoolBytes: await _channel.spoolSizeBytes(),
    );
  }

  // -------------------------------------------------------------- mapping

  BatterySnapshot _fromRow(Sample row) => BatterySnapshot(
        timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestampMs),
        levelPct: row.levelPct,
        chargeCounterUah: row.chargeCounterUah,
        currentNowUa: row.currentNowUa,
        currentAvgUa: row.currentAvgUa,
        voltageMv: row.voltageMv,
        temperatureC: row.temperatureC,
        energyCounterNwh: row.energyCounterNwh,
        status: ChargingStatus.parse(row.status),
        plugType: PlugType.parse(row.plugType),
        health: BatteryHealthFlag.parse(row.health),
        technology: row.technology,
        screenOn: row.screenOn,
        powerSaveMode: row.powerSaveMode,
        uptimeMs: row.uptimeMs,
        elapsedRealtimeMs: row.elapsedRealtimeMs,
        cycleCount: row.cycleCount,
        stateOfHealthPct: row.stateOfHealthPct,
      );

  BatterySession _toSession(Session row) => BatterySession(
        id: row.id,
        kind: SessionKind.parse(row.kind),
        start: DateTime.fromMillisecondsSinceEpoch(row.startMs),
        end: DateTime.fromMillisecondsSinceEpoch(row.endMs),
        startLevelPct: row.startLevelPct,
        endLevelPct: row.endLevelPct,
        startChargeUah: row.startChargeUah,
        endChargeUah: row.endChargeUah,
        chargeMovedMah: row.chargeMovedMah,
        chargeMethod: ChargeMethod.parse(row.chargeMethod),
        avgCurrentMa: row.avgCurrentMa,
        maxCurrentMa: row.maxCurrentMa,
        avgTemperatureC: row.avgTemperatureC,
        maxTemperatureC: row.maxTemperatureC,
        avgVoltageMv: row.avgVoltageMv,
        screenOnMs: row.screenOnMs,
        screenOffMs: row.screenOffMs,
        screenOnDropPct: row.screenOnDropPct,
        screenOffDropPct: row.screenOffDropPct,
        plugType: row.plugType == null ? null : PlugType.parse(row.plugType),
        sampleCount: row.sampleCount,
        maxGapMs: row.maxGapMs,
        usableForCapacity: row.usableForCapacity,
        rejectionReason: row.rejectionReason,
        impliedCapacityMah: row.impliedCapacityMah,
        cyclesUsed: row.cyclesUsed,
      );

  SegmentedSession _toSegmented(BatterySession s) => SegmentedSession(
        kind: s.kind,
        start: s.start,
        end: s.end,
        startLevelPct: s.startLevelPct,
        endLevelPct: s.endLevelPct,
        startChargeUah: s.startChargeUah,
        endChargeUah: s.endChargeUah,
        chargeMovedMah: s.chargeMovedMah,
        chargeMethod: s.chargeMethod,
        avgCurrentMa: s.avgCurrentMa,
        maxCurrentMa: s.maxCurrentMa,
        avgTemperatureC: s.avgTemperatureC,
        maxTemperatureC: s.maxTemperatureC,
        avgVoltageMv: s.avgVoltageMv,
        screenOnMs: s.screenOnMs,
        screenOffMs: s.screenOffMs,
        screenOnDropPct: s.screenOnDropPct,
        screenOffDropPct: s.screenOffDropPct,
        plugType: s.plugType,
        sampleCount: s.sampleCount,
        maxGapMs: s.maxGapMs,
        usableForCapacity: s.usableForCapacity,
        rejectionReason: s.rejectionReason,
        impliedCapacityMah: s.impliedCapacityMah,
        cyclesUsed: s.cyclesUsed,
      );

  /// Batch size for draining the spool. Large enough that a normal sync is one
  /// pass, small enough that a month of backlog does not blow up memory.
  static const int _ingestBatchSize = 5000;
}

class SyncResult {
  const SyncResult({
    required this.ingested,
    required this.sessionsWritten,
    this.joined = false,
  });

  final int ingested;
  final int sessionsWritten;

  /// True when this call waited on an in-flight sync instead of running one.
  final bool joined;
}

class AppUsageReport {
  const AppUsageReport({
    required this.apps,
    required this.unattributedPct,
    required this.hasAccess,
    required this.hasDischargeData,
    required this.isAttributed,
  });

  final List<AppConsumption> apps;

  /// Battery percentage that no foreground app accounts for: standby plus
  /// background work.
  final double unattributedPct;

  final bool hasAccess;

  /// Whether any discharge has been observed at all.
  ///
  /// Separated from [isEmpty] so the screen can tell "you have been plugged
  /// in the whole time" apart from "you used the phone but no single app
  /// accounts for it", which call for completely different explanations.
  final bool hasDischargeData;

  /// Whether the figures are measured battery attribution, or only foreground
  /// time. The screen must say which, because they are very different claims.
  final bool isAttributed;

  bool get isEmpty => apps.isEmpty;
}

class DatabaseStats {
  const DatabaseStats({
    required this.sampleCount,
    required this.sessionCount,
    required this.estimateCount,
    required this.spoolBytes,
  });

  final int sampleCount;
  final int sessionCount;
  final int estimateCount;
  final int spoolBytes;
}
