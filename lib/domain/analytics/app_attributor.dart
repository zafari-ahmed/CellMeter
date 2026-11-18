import '../../data/native/native_models.dart';
import '../models/session_models.dart';
import 'session_segmenter.dart';

/// One app's share of measured battery consumption.
class AppConsumption {
  const AppConsumption({
    required this.packageName,
    required this.label,
    required this.foreground,
    required this.isSystemApp,
    this.attributedMah,
    this.attributedPct,
    this.shareOfForeground = 0,
  });

  final String packageName;
  final String label;
  final Duration foreground;
  final bool isSystemApp;

  /// Charge attributed to this app, mAh.
  final double? attributedMah;

  /// Battery percentage attributed to this app.
  final double? attributedPct;

  /// This app's share of all measured foreground time, 0..1.
  final double shareOfForeground;

  /// Drain rate while this app was in front, percentage points per hour.
  /// This is the comparable figure: total consumption just says what the user
  /// used most, while the rate says what is actually expensive to run.
  double? get pctPerHour {
    final pct = attributedPct;
    final hours = foreground.inMilliseconds / 3600000;
    if (pct == null || hours <= 0) return null;
    return pct / hours;
  }
}

/// Divides measured battery consumption across apps by foreground time.
///
/// ## Why it works this way
///
/// Android has no API that reports how much energy an app consumed. What the
/// system's own battery screen shows is modelled, not measured: it multiplies
/// estimated component usage by a table of nominal costs that the manufacturer
/// supplies in `power_profile.xml`. Those tables are frequently inaccurate, and
/// on some devices they are close to fiction.
///
/// CellMeter does not try to reproduce that model. It measures the one thing it
/// can measure exactly — the charge the battery actually lost, from the coulomb
/// counter — and divides it across apps in proportion to the foreground time
/// each held during the same window.
///
/// ## What that claim means, and what it does not
///
/// The resulting figure is honest about being an attribution, not a
/// measurement of the app itself. It says "the stretch of your day when this
/// app was on screen cost you 340 mAh". It does not isolate the app from the
/// display, radio or anything else running at the time, and the UI says so
/// rather than implying a precision that is not there.
///
/// Background work is deliberately not attributed. An app can drain a battery
/// while it is nowhere near the foreground, but nothing available to a normal
/// app can tell whose wakelock did it. Inventing a split would be worse than
/// leaving it in the unattributed remainder, where it is at least visible.
class AppAttributor {
  const AppAttributor({this.minForeground = const Duration(seconds: 30)});

  /// Slices shorter than this are app switches, not usage worth listing.
  final Duration minForeground;

  /// Attributes a discharge session's consumption across [slices].
  ///
  /// Only screen-on time is used as the divisor, because foreground time only
  /// exists while the screen is on, and dividing by the whole session would
  /// quietly fold standby drain into whichever app happened to be open.
  List<AppConsumption> attribute({
    required SegmentedSession session,
    required List<ForegroundSlice> slices,
  }) {
    if (session.kind != SessionKind.discharge) return const [];

    final relevant = slices
        .where((s) => s.foregroundMs >= minForeground.inMilliseconds)
        .toList();
    if (relevant.isEmpty) return const [];

    final totalForegroundMs =
        relevant.fold<int>(0, (sum, s) => sum + s.foregroundMs);
    if (totalForegroundMs <= 0) return const [];

    // The screen-on portion of the session is what the apps are responsible
    // for. If it was not measured, fall back to the total, and accept that the
    // attribution is coarser.
    final screenOnDrop = session.screenOnDropPct;
    final attributablePct = screenOnDrop ?? session.levelSpanPct;

    final moved = session.chargeMovedMah?.abs();
    final totalDrop =
        (session.screenOnDropPct ?? 0) + (session.screenOffDropPct ?? 0);
    final attributableMah = (moved != null && totalDrop > 0 && screenOnDrop != null)
        ? moved * (screenOnDrop / totalDrop)
        : moved;

    return relevant
        .map((slice) {
          final share = slice.foregroundMs / totalForegroundMs;
          return AppConsumption(
            packageName: slice.packageName,
            label: slice.label,
            foreground: slice.foreground,
            isSystemApp: slice.isSystemApp,
            attributedPct: attributablePct * share,
            attributedMah:
                attributableMah == null ? null : attributableMah * share,
            shareOfForeground: share,
          );
        })
        .toList()
      ..sort((a, b) =>
          (b.attributedPct ?? 0).compareTo(a.attributedPct ?? 0));
  }

  /// Merges per-session attributions into a single ranking over a period.
  List<AppConsumption> merge(List<List<AppConsumption>> perSession) {
    final byPackage = <String, _Accumulator>{};

    for (final list in perSession) {
      for (final item in list) {
        final acc = byPackage.putIfAbsent(
          item.packageName,
          () => _Accumulator(item.label, item.isSystemApp),
        );
        acc.foregroundMs += item.foreground.inMilliseconds;
        acc.mah += item.attributedMah ?? 0;
        acc.pct += item.attributedPct ?? 0;
        acc.hasMah |= item.attributedMah != null;
      }
    }

    final totalForegroundMs =
        byPackage.values.fold<int>(0, (sum, a) => sum + a.foregroundMs);

    final merged = byPackage.entries
        .map((entry) => AppConsumption(
              packageName: entry.key,
              label: entry.value.label,
              foreground: Duration(milliseconds: entry.value.foregroundMs),
              isSystemApp: entry.value.isSystemApp,
              attributedMah: entry.value.hasMah ? entry.value.mah : null,
              attributedPct: entry.value.pct,
              shareOfForeground: totalForegroundMs > 0
                  ? entry.value.foregroundMs / totalForegroundMs
                  : 0,
            ))
        .toList()
      ..sort((a, b) =>
          (b.attributedPct ?? 0).compareTo(a.attributedPct ?? 0));

    return merged;
  }

  /// Battery percentage that no foreground app accounts for.
  ///
  /// Surfaced rather than hidden: this is standby drain plus background work,
  /// and when it is large it is the most important number on the screen.
  double unattributedPct({
    required List<SegmentedSession> sessions,
    required List<AppConsumption> attributed,
  }) {
    final totalDrop = sessions
        .where((s) => s.kind == SessionKind.discharge)
        .fold<double>(0, (sum, s) => sum + s.levelSpanPct);
    final claimed =
        attributed.fold<double>(0, (sum, a) => sum + (a.attributedPct ?? 0));
    return (totalDrop - claimed).clamp(0, double.infinity);
  }
}

class _Accumulator {
  _Accumulator(this.label, this.isSystemApp);

  final String label;
  final bool isSystemApp;
  int foregroundMs = 0;
  double mah = 0;
  double pct = 0;
  bool hasMah = false;
}
