import 'package:cellmeter/domain/analytics/capacity_estimator.dart';
import 'package:cellmeter/domain/analytics/session_segmenter.dart';
import 'package:cellmeter/domain/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A qualifying charge session that implies [impliedMah].
SegmentedSession _session({
  required DateTime start,
  required double impliedMah,
  double levelSpanPct = 50,
  ChargeMethod method = ChargeMethod.coulomb,
  bool usable = true,
}) {
  return SegmentedSession(
    kind: SessionKind.charge,
    start: start,
    end: start.add(const Duration(hours: 2)),
    startLevelPct: 20,
    endLevelPct: 20 + levelSpanPct,
    chargeMovedMah: impliedMah * (levelSpanPct / 100),
    chargeMethod: method,
    usableForCapacity: usable,
    impliedCapacityMah: impliedMah,
    cyclesUsed: levelSpanPct / 100,
    sampleCount: 200,
  );
}

void main() {
  final now = DateTime(2026, 6, 1, 12);
  const estimator = CapacityEstimator();

  group('with no usable data', () {
    test('returns an empty estimate rather than guessing', () {
      final result = estimator.estimate(sessions: const [], designMah: 4000);

      expect(result.isEmpty, isTrue);
      expect(result.confidence, Confidence.low);
      expect(result.healthPct, isNull);
    });

    test('ignores sessions the segmenter rejected', () {
      final result = estimator.estimate(
        sessions: [
          _session(start: now, impliedMah: 2000, usable: false),
          _session(
            start: now.subtract(const Duration(days: 1)),
            impliedMah: 9999,
            usable: false,
          ),
        ],
        designMah: 4000,
        now: now,
      );

      expect(result.isEmpty, isTrue);
    });
  });

  group('combining sessions', () {
    test('settles near the consistent value', () {
      final sessions = List.generate(
        8,
        (i) => _session(
          start: now.subtract(Duration(days: i * 3)),
          impliedMah: 3600 + (i.isEven ? 40 : -40),
        ),
      );

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.estimatedMah, closeTo(3600, 60));
      expect(result.healthPct, closeTo(90, 2));
      expect(result.sessionCount, 8);
    });

    test('a gauge recalibration does not move the headline figure', () {
      // Seven consistent sessions and one wild reading, which is what a fuel
      // gauge re-calibrating mid-charge looks like. A mean would be dragged
      // several hundred mAh by it; the weighted median should not move.
      final sessions = [
        ...List.generate(
          7,
          (i) => _session(
            start: now.subtract(Duration(days: i * 2)),
            impliedMah: 3500 + i * 10,
          ),
        ),
        _session(
          start: now.subtract(const Duration(days: 3)),
          impliedMah: 7400,
        ),
      ];

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.estimatedMah, closeTo(3530, 80));
      expect(
        result.sessionCount,
        lessThan(8),
        reason: 'the outlier should have been discarded outright',
      );
    });

    test('weights wide charges above narrow ones', () {
      // Three narrow sessions disagree with two wide ones. The wide sessions
      // carry far more information and should win.
      final sessions = [
        _session(start: now, impliedMah: 3000, levelSpanPct: 22),
        _session(
          start: now.subtract(const Duration(days: 1)),
          impliedMah: 3000,
          levelSpanPct: 22,
        ),
        _session(
          start: now.subtract(const Duration(days: 2)),
          impliedMah: 3000,
          levelSpanPct: 22,
        ),
        _session(
          start: now.subtract(const Duration(days: 3)),
          impliedMah: 3900,
          levelSpanPct: 85,
        ),
        _session(
          start: now.subtract(const Duration(days: 4)),
          impliedMah: 3900,
          levelSpanPct: 85,
        ),
      ];

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.estimatedMah, greaterThan(3400));
    });

    test('follows a battery that genuinely degrades', () {
      // Old sessions say 3 800, recent ones say 3 200. The half-life decay
      // should pull the estimate toward the recent truth.
      final sessions = [
        ...List.generate(
          6,
          (i) => _session(
            start: now.subtract(Duration(days: i * 2)),
            impliedMah: 3200,
          ),
        ),
        ...List.generate(
          6,
          (i) => _session(
            start: now.subtract(Duration(days: 150 + i * 2)),
            impliedMah: 3800,
          ),
        ),
      ];

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.estimatedMah, closeTo(3200, 60));
    });

    test('discounts sessions measured by integrating current', () {
      // Equal numbers of each, disagreeing. The coulomb-counter sessions are
      // the more trustworthy measurement and should dominate.
      final sessions = [
        ...List.generate(
          4,
          (i) => _session(
            start: now.subtract(Duration(days: i)),
            impliedMah: 3500,
          ),
        ),
        ...List.generate(
          4,
          (i) => _session(
            start: now.subtract(Duration(days: i)),
            impliedMah: 4200,
            method: ChargeMethod.integrated,
          ),
        ),
      ];

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.estimatedMah, closeTo(3500, 100));
    });
  });

  group('confidence', () {
    test('stays low while there is barely any evidence', () {
      final result = estimator.estimate(
        sessions: [_session(start: now, impliedMah: 3600, levelSpanPct: 25)],
        designMah: 4000,
        now: now,
      );

      expect(result.confidence, Confidence.low);
    });

    test('reaches high once many wide sessions agree', () {
      final sessions = List.generate(
        10,
        (i) => _session(
          start: now.subtract(Duration(days: i * 2)),
          impliedMah: 3600 + (i.isEven ? 15 : -15),
          levelSpanPct: 60,
        ),
      );

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.confidence, Confidence.high);
    });

    test('drops back to low when sessions disagree badly', () {
      // Plenty of sessions, no agreement: saying "still measuring" is more
      // honest than publishing a precise-looking number.
      final values = [2800.0, 4300.0, 3100.0, 4000.0, 3300.0, 4400.0, 2900.0, 4200.0];
      final sessions = [
        for (var i = 0; i < values.length; i++)
          _session(
            start: now.subtract(Duration(days: i * 2)),
            impliedMah: values[i],
            levelSpanPct: 60,
          ),
      ];

      final result = estimator.estimate(
        sessions: sessions,
        designMah: 4000,
        now: now,
      );

      expect(result.confidence, Confidence.low);
    });
  });

  group('health', () {
    test('expresses capacity as a share of design', () {
      final result = estimator.estimate(
        sessions: List.generate(
          6,
          (i) => _session(
            start: now.subtract(Duration(days: i)),
            impliedMah: 3000,
          ),
        ),
        designMah: 4000,
        now: now,
      );

      expect(result.healthPct, closeTo(75, 0.5));
      expect(result.wearPct, closeTo(25, 0.5));
    });

    test('leaves health unknown when the design capacity is not', () {
      final result = estimator.estimate(
        sessions: [_session(start: now, impliedMah: 3000)],
        now: now,
      );

      expect(result.estimatedMah, closeTo(3000, 1));
      expect(result.healthPct, isNull);
      expect(result.wearPct, isNull);
    });

    test('caps a better-than-new reading instead of reporting 140%', () {
      final result = estimator.estimate(
        sessions: List.generate(
          6,
          (i) => _session(
            start: now.subtract(Duration(days: i)),
            impliedMah: 5600,
          ),
        ),
        designMah: 4000,
        now: now,
      );

      expect(result.healthPct, lessThanOrEqualTo(110));
    });

    test('carries the manufacturer figure alongside its own', () {
      final result = estimator.estimate(
        sessions: [_session(start: now, impliedMah: 3400)],
        designMah: 4000,
        oemStateOfHealthPct: 88,
        now: now,
      );

      // Reported side by side, never averaged: they are different
      // measurements with different failure modes.
      expect(result.oemStateOfHealthPct, 88);
      expect(result.healthPct, closeTo(85, 1));
    });
  });
}
