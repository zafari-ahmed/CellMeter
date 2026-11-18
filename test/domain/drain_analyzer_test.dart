import 'package:cellmeter/domain/analytics/drain_analyzer.dart';
import 'package:cellmeter/domain/analytics/session_segmenter.dart';
import 'package:cellmeter/domain/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

SegmentedSession _discharge({
  required DateTime start,
  required Duration screenOn,
  required Duration screenOff,
  required double screenOnDrop,
  required double screenOffDrop,
  double? chargeMovedMah,
}) {
  final total = screenOn + screenOff;
  return SegmentedSession(
    kind: SessionKind.discharge,
    start: start,
    end: start.add(total),
    startLevelPct: 90,
    endLevelPct: 90 - screenOnDrop - screenOffDrop,
    screenOnMs: screenOn.inMilliseconds,
    screenOffMs: screenOff.inMilliseconds,
    screenOnDropPct: screenOnDrop,
    screenOffDropPct: screenOffDrop,
    chargeMovedMah: chargeMovedMah,
    chargeMethod:
        chargeMovedMah == null ? ChargeMethod.none : ChargeMethod.coulomb,
  );
}

void main() {
  final now = DateTime(2026, 6, 1, 20);
  const analyzer = DrainAnalyzer();

  group('drain profile', () {
    test('reports screen-on and standby rates separately', () {
      final sessions = [
        _discharge(
          start: now.subtract(const Duration(days: 1)),
          screenOn: const Duration(hours: 2),
          screenOff: const Duration(hours: 8),
          screenOnDrop: 24,
          screenOffDrop: 4,
        ),
      ];

      final profile = analyzer.profile(sessions, now: now);

      expect(profile.screenOnPctPerHour, closeTo(12, 0.1));
      expect(profile.screenOffPctPerHour, closeTo(0.5, 0.05));
    });

    test('pools time across sessions instead of averaging their rates', () {
      // A six-hour session and a two-minute one. Averaging the two sessions'
      // rates would let the short, noisy one count as much as the long one.
      final sessions = [
        _discharge(
          start: now.subtract(const Duration(hours: 8)),
          screenOn: const Duration(hours: 6),
          screenOff: Duration.zero,
          screenOnDrop: 60,
          screenOffDrop: 0,
        ),
        _discharge(
          start: now.subtract(const Duration(hours: 1)),
          screenOn: const Duration(minutes: 20),
          screenOff: Duration.zero,
          screenOnDrop: 20,
          screenOffDrop: 0,
        ),
      ];

      final profile = analyzer.profile(sessions, now: now);

      // Pooled: 80% over 6h20m is about 12.6%/h. A per-session mean would give
      // (10 + 60) / 2 = 35%/h, which no phone in this test ever did.
      expect(profile.screenOnPctPerHour, closeTo(12.6, 0.5));
    });

    test('ignores history older than the lookback window', () {
      final sessions = [
        _discharge(
          start: now.subtract(const Duration(days: 60)),
          screenOn: const Duration(hours: 4),
          screenOff: Duration.zero,
          screenOnDrop: 80,
          screenOffDrop: 0,
        ),
      ];

      expect(analyzer.profile(sessions, now: now).hasData, isFalse);
    });

    test('says nothing rather than guessing from a few minutes of data', () {
      final sessions = [
        _discharge(
          start: now.subtract(const Duration(minutes: 30)),
          screenOn: const Duration(minutes: 4),
          screenOff: const Duration(minutes: 5),
          screenOnDrop: 1,
          screenOffDrop: 0,
        ),
      ];

      final profile = analyzer.profile(sessions, now: now);

      expect(profile.screenOnPctPerHour, isNull);
      expect(profile.screenOffPctPerHour, isNull);
    });
  });

  group('runtime forecasts', () {
    test('gives very different answers for use and standby', () {
      final sessions = [
        _discharge(
          start: now.subtract(const Duration(days: 1)),
          screenOn: const Duration(hours: 3),
          screenOff: const Duration(hours: 9),
          screenOnDrop: 36,
          screenOffDrop: 4.5,
        ),
      ];

      final profile = analyzer.profile(sessions, now: now);

      // 50% left: 4 hours of use, or roughly four days asleep.
      expect(profile.screenOnRuntime(50)!.inMinutes, closeTo(240, 15));
      expect(profile.standbyRuntime(50)!.inHours, greaterThan(80));
    });

    test('returns nothing when there is no measured rate', () {
      expect(DrainProfile.empty.screenOnRuntime(50), isNull);
      expect(DrainProfile.empty.mixedRuntime(50), isNull);
    });
  });

  group('live drain', () {
    test('measures the rate over the recent window', () {
      final samples = Fixtures.discharge(
        start: now.subtract(const Duration(minutes: 18)),
        capacityMah: 4000,
        startLevelPct: 60,
        endLevelPct: 57,
        interval: const Duration(seconds: 30),
        currentUa: 1600000,
      );

      final live = analyzer.live(samples, now: now);

      expect(live.hasData, isTrue);
      expect(live.averageMa, closeTo(1600, 1));
      expect(live.pctPerHour, greaterThan(5));
    });

    test('has nothing to say about a charging phone', () {
      final samples = Fixtures.charge(
        start: now.subtract(const Duration(minutes: 15)),
        capacityMah: 4000,
        startLevelPct: 40,
        endLevelPct: 50,
      );

      expect(analyzer.live(samples, now: now).hasData, isFalse);
    });
  });

  group('time to full', () {
    test('allows for the slow tail above 80%', () {
      // Charging from 30%, gaining 30 points per hour. Extrapolating that rate
      // straight to 100% would promise a full charge in 2h20m, which is the
      // error most battery apps make: above roughly 80% a lithium cell moves
      // to constant-voltage charging and the current tapers steeply.
      final samples = Fixtures.charge(
        start: now.subtract(const Duration(hours: 1)),
        capacityMah: 4000,
        startLevelPct: 30,
        endLevelPct: 60,
        interval: const Duration(minutes: 1),
        currentUa: 1200000,
      );

      final estimate = analyzer.timeToFull(samples);

      expect(estimate, isNotNull);
      expect(
        estimate!.inMinutes,
        greaterThan(80),
        reason: 'the tail above 80% must be slower than the bulk charge',
      );
    });

    test('reaching a charge limit of 80% takes only the fast portion', () {
      final samples = Fixtures.charge(
        start: now.subtract(const Duration(hours: 1)),
        capacityMah: 4000,
        startLevelPct: 30,
        endLevelPct: 60,
        interval: const Duration(minutes: 1),
        currentUa: 1200000,
      );

      final toLimit = analyzer.timeToFull(samples, targetPct: 80);
      final toFull = analyzer.timeToFull(samples);

      expect(toLimit!.inMinutes, lessThan(toFull!.inMinutes));
      expect(toLimit.inMinutes, closeTo(40, 10));
    });

    test('has no answer once the battery is already there', () {
      final samples = Fixtures.charge(
        start: now.subtract(const Duration(hours: 1)),
        capacityMah: 4000,
        startLevelPct: 90,
        endLevelPct: 99,
        interval: const Duration(minutes: 1),
      );

      expect(analyzer.timeToFull(samples, targetPct: 80), isNull);
    });
  });
}
