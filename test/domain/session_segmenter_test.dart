import 'package:cellmeter/data/native/native_models.dart';
import 'package:cellmeter/domain/analytics/session_segmenter.dart';
import 'package:cellmeter/domain/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  final epoch = DateTime(2026, 1, 1, 8);
  const segmenter = SessionSegmenter();

  group('segmentation', () {
    test('splits where charging flips to discharging', () {
      final samples = [
        ...Fixtures.charge(
          start: epoch,
          capacityMah: 4000,
          startLevelPct: 30,
          endLevelPct: 60,
        ),
        ...Fixtures.discharge(
          start: epoch.add(const Duration(hours: 2)),
          capacityMah: 4000,
          startLevelPct: 60,
          endLevelPct: 40,
        ),
      ];

      final sessions = segmenter.segment(samples, openEnded: true);

      expect(sessions, hasLength(2));
      expect(sessions.first.kind, SessionKind.charge);
      expect(sessions.last.kind, SessionKind.discharge);
    });

    test('ends a session where the sampler went missing', () {
      // Two hours with no samples: the service was killed or the device was in
      // deep doze. Averaging across the hole would invent data.
      final samples = [
        ...Fixtures.charge(
          start: epoch,
          capacityMah: 4000,
          startLevelPct: 30,
          endLevelPct: 40,
        ),
        ...Fixtures.charge(
          start: epoch.add(const Duration(hours: 3)),
          capacityMah: 4000,
          startLevelPct: 50,
          endLevelPct: 60,
        ),
      ];

      final sessions = segmenter.segment(samples, openEnded: true);

      expect(sessions, hasLength(2));
      expect(sessions.every((s) => s.kind == SessionKind.charge), isTrue);
    });

    test('ignores plug jitter too short to be a session', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 50,
        endLevelPct: 50.5,
        interval: const Duration(seconds: 5),
      );

      expect(segmenter.segment(samples, openEnded: true), isEmpty);
    });

    test('keeps the in-progress session only when asked', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 40,
        endLevelPct: 70,
      );

      // A history rebuild must not record a charge that has not finished.
      expect(segmenter.segment(samples), isEmpty);
      // The live dashboard needs exactly that session.
      expect(segmenter.segment(samples, openEnded: true), hasLength(1));
    });
  });

  group('capacity measurement', () {
    test('recovers the true capacity from the coulomb counter', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 25,
        endLevelPct: 85,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.usableForCapacity, isTrue, reason: session.rejectionReason);
      expect(session.chargeMethod, ChargeMethod.coulomb);
      // The only error is the one percent the device quantises the level to.
      expect(session.impliedCapacityMah, closeTo(4000, 120));
      expect(session.cyclesUsed, closeTo(0.6, 0.02));
    });

    test('reports a worn battery as worn', () {
      // Same phone, same design capacity, a cell that now holds 3 100 mAh.
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 3100,
        startLevelPct: 20,
        endLevelPct: 90,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.usableForCapacity, isTrue, reason: session.rejectionReason);
      expect(session.impliedCapacityMah, closeTo(3100, 100));
    });

    test('rejects a charge too narrow to measure accurately', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 70,
        endLevelPct: 78,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.usableForCapacity, isFalse);
      expect(session.rejectionReason, contains('at least 20%'));
    });

    test('rejects a session the sampler slept through', () {
      final first = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 20,
        endLevelPct: 35,
      );
      // A 15-minute hole: long enough to ruin the measurement, short enough
      // that the session is not split in two.
      final second = Fixtures.charge(
        start: first.last.timestamp.add(const Duration(minutes: 15)),
        capacityMah: 4000,
        startLevelPct: 35,
        endLevelPct: 60,
      );

      final session =
          segmenter.segment([...first, ...second], openEnded: true).single;

      expect(session.usableForCapacity, isFalse);
      expect(session.rejectionReason, contains('interrupted'));
    });

    test('rejects a charge that ran hot', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 25,
        endLevelPct: 85,
        temperatureC: 48,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.usableForCapacity, isFalse);
      expect(session.rejectionReason, contains('°C'));
    });

    test('catches a charge counter that is really just the level', () {
      final samples = Fixtures.chargeWithDerivedCounter(
        start: epoch,
        designMah: 4000,
        startLevelPct: 20,
        endLevelPct: 90,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(
        session.usableForCapacity,
        isFalse,
        reason: 'A derived counter always returns the design capacity, so it '
            'would report a worn battery as perfect.',
      );
      expect(session.rejectionReason, contains('derived from the battery'));
    });

    test('does not mistake a real counter for a derived one', () {
      // The regression guard for the check above: a genuine gauge must keep
      // working on devices whose sampling cadence happens to line up with the
      // level steps.
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 30,
        endLevelPct: 80,
        interval: const Duration(minutes: 1),
        currentUa: 2400000,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.usableForCapacity, isTrue, reason: session.rejectionReason);
      expect(session.chargeMethod, ChargeMethod.coulomb);
    });

    test('falls back to integrating current when there is no counter', () {
      final samples = Fixtures.chargeWithoutCounter(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 25,
        endLevelPct: 80,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.chargeMethod, ChargeMethod.integrated);
      expect(session.usableForCapacity, isTrue, reason: session.rejectionReason);
      expect(session.impliedCapacityMah, closeTo(4000, 200));
    });
  });

  group('screen attribution', () {
    test('keeps screen-on and screen-off drain apart', () {
      // An hour of use at 1.2 A, then four hours asleep at 60 mA.
      final awake = Fixtures.withScreen(
        Fixtures.discharge(
          start: epoch,
          capacityMah: 4000,
          startLevelPct: 80,
          endLevelPct: 50,
          currentUa: 1200000,
        ),
        screenOn: true,
      );
      final asleep = Fixtures.withScreen(
        Fixtures.discharge(
          start: awake.last.timestamp.add(const Duration(minutes: 1)),
          capacityMah: 4000,
          startLevelPct: 50,
          endLevelPct: 44,
          currentUa: 60000,
        ),
        screenOn: false,
      );

      final session =
          segmenter.segment([...awake, ...asleep], openEnded: true).single;

      expect(session.kind, SessionKind.discharge);
      expect(session.screenOnDropPct, closeTo(30, 2));
      expect(session.screenOffDropPct, closeTo(6, 2));

      final onRate = session.screenOnDropPct! / (session.screenOnMs / 3600000);
      final offRate =
          session.screenOffDropPct! / (session.screenOffMs / 3600000);

      // Collapsing these into one average is the error the split exists to
      // prevent: it would make both runtime estimates wrong.
      expect(onRate, greaterThan(offRate * 5));
    });
  });

  group('aggregates', () {
    test('records the charger and the current it delivered', () {
      final samples = Fixtures.charge(
        start: epoch,
        capacityMah: 4000,
        startLevelPct: 30,
        endLevelPct: 70,
        currentUa: 2100000,
        voltageMv: 4200,
      );

      final session = segmenter.segment(samples, openEnded: true).single;

      expect(session.plugType, PlugType.ac);
      expect(session.avgCurrentMa, closeTo(2100, 1));
      expect(session.avgVoltageMv, closeTo(4200, 1));
      expect(session.sampleCount, greaterThan(50));
    });
  });
}
