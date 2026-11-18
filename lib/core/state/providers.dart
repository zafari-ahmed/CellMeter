import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/database.dart';
import '../../data/native/battery_channel.dart';
import '../../data/native/native_models.dart';
import '../../data/repository/battery_repository.dart';
import '../../domain/analytics/capacity_estimator.dart';
import '../../domain/analytics/drain_analyzer.dart';
import '../../domain/models/session_models.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------- plumbing

final databaseProvider = Provider<CellMeterDatabase>((ref) {
  final db = CellMeterDatabase();
  ref.onDispose(db.close);
  return db;
});

final batteryChannelProvider = Provider<BatteryChannel>((ref) => BatteryChannel());

final batteryRepositoryProvider = Provider<BatteryRepository>((ref) {
  return BatteryRepository(
    database: ref.watch(databaseProvider),
    channel: ref.watch(batteryChannelProvider),
  );
});

final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

// ------------------------------------------------------------ live reading

/// The battery as it is right now, polled while a screen is watching.
///
/// A poll rather than a platform event stream for a deliberate reason: the
/// values that move fastest — current, voltage, temperature — have no
/// broadcast at all. Android only notifies on whole-percent level changes,
/// which at low drain can be half an hour apart, and a live readout that
/// updates twice an hour is not a live readout.
///
/// Riverpod tears the stream down when nothing is listening, so the poll stops
/// as soon as the user leaves the screen. Long-term recording is the sampler's
/// job, and it runs regardless.
final liveSnapshotProvider = StreamProvider.autoDispose<BatterySnapshot?>((ref) {
  final channel = ref.watch(batteryChannelProvider);
  final controller = StreamController<BatterySnapshot?>();

  Future<void> poll() async {
    if (controller.isClosed) return;
    try {
      controller.add(await channel.readSnapshot());
    } catch (_) {
      // A failed read is not worth tearing the stream down for; the next tick
      // will very likely succeed.
    }
  }

  unawaited(poll());
  final timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

final designCapacityProvider = FutureProvider<DesignCapacityInfo>(
  (ref) => ref.watch(batteryChannelProvider).designCapacity(),
);

final deviceInfoProvider = FutureProvider<NativeDeviceInfo>(
  (ref) => ref.watch(batteryChannelProvider).deviceInfo(),
);

final usageAccessProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(batteryChannelProvider).hasUsageAccess(),
);

final batteryOptimizationProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(batteryChannelProvider).isIgnoringBatteryOptimizations(),
);

// ------------------------------------------------------------------- sync

/// Drives spool ingestion.
///
/// Every analysis provider watches this, so one sync refreshes all of them and
/// none of them can trigger a second one while it runs.
class SyncController extends AsyncNotifier<SyncResult> {
  Timer? _timer;

  @override
  Future<SyncResult> build() async {
    final repository = ref.watch(batteryRepositoryProvider);

    // Keep pulling while the app is open; the sampler spools continuously and
    // the UI should not go stale behind it.
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(refresh()),
    );
    ref.onDispose(() => _timer?.cancel());

    return repository.sync();
  }

  /// Ingests anything new and refreshes the derived views.
  Future<void> refresh() async {
    final repository = ref.read(batteryRepositoryProvider);
    try {
      final result = await repository.sync();
      state = AsyncValue.data(result);
      // Refreshed after every sync, not only when new samples arrived.
      // Gating on `ingested > 0` meant a pull-to-refresh with nothing to
      // ingest did nothing at all, and a screen that had computed an empty
      // result earlier — Apps before the first discharge, say — kept serving
      // it from cache long after the data existed.
      _invalidateDerived();
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// A pull-to-refresh: ask the sampler for a reading first so the newest
  /// moment is included, then ingest.
  Future<void> refreshNow() async {
    await ref.read(batteryChannelProvider).sampleNow();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await refresh();
  }

  /// Re-derives every session from the raw samples.
  Future<void> rebuildEverything() async {
    final repository = ref.read(batteryRepositoryProvider);
    try {
      final count = await repository.rebuildAllSessions();
      state = AsyncValue.data(
        SyncResult(ingested: 0, sessionsWritten: count),
      );
      _invalidateDerived();
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _invalidateDerived() {
    ref.invalidate(capacityEstimateProvider);
    ref.invalidate(drainProfileProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(appUsageProvider);
    ref.invalidate(capacityHistoryProvider);
    ref.invalidate(cyclesUsedProvider);
    ref.invalidate(databaseStatsProvider);
  }
}

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncResult>(SyncController.new);

// --------------------------------------------------------------- analysis

// The analysis providers deliberately do NOT watch [syncControllerProvider].
//
// Awaiting the sync future from here reads as the obvious way to guarantee
// fresh data, but it points the dependency the wrong way: the sync controller
// invalidates these same providers when it finishes, so each one ended up
// depending on something that depends on it, and Riverpod rejected the graph
// with a CircularDependencyError.
//
// The edge now runs one way only. [SyncController] owns ingestion and
// invalidates these when it has pulled something new; they simply read the
// database. The shell watches the controller so a sync is always running.

final capacityEstimateProvider = FutureProvider<CapacityEstimate>(
  (ref) => ref.watch(batteryRepositoryProvider).capacityEstimate(),
);

final capacityHistoryProvider = FutureProvider<List<CapacityLog>>(
  (ref) => ref.watch(batteryRepositoryProvider).capacityHistory(),
);

final drainProfileProvider = FutureProvider<DrainProfile>(
  (ref) => ref.watch(batteryRepositoryProvider).drainProfile(),
);

final liveDrainProvider = FutureProvider.autoDispose<LiveDrain>((ref) async {
  // Re-runs on every live reading so the figure tracks what is happening now.
  ref.watch(liveSnapshotProvider);
  return ref.watch(batteryRepositoryProvider).liveDrain();
});

final timeToFullProvider = FutureProvider.autoDispose<Duration?>((ref) async {
  ref.watch(liveSnapshotProvider);
  return ref.watch(batteryRepositoryProvider).timeToFull();
});

/// Time until the user's own charge limit, which is what they actually care
/// about when they have set one.
final timeToChargeLimitProvider =
    FutureProvider.autoDispose<Duration?>((ref) async {
  ref.watch(liveSnapshotProvider);
  final settings = ref.watch(monitorSettingsProvider).value;
  final target = settings?.chargeAlarmPct;
  if (settings == null || !settings.chargeAlarmEnabled || target == null) {
    return null;
  }
  return ref
      .watch(batteryRepositoryProvider)
      .timeToFull(targetPct: target.toDouble());
});

final recentSessionsProvider = FutureProvider<List<BatterySession>>(
  (ref) => ref.watch(batteryRepositoryProvider).sessions(limit: 200),
);

final sessionsOfKindProvider =
    FutureProvider.family<List<BatterySession>, SessionKind>((ref, kind) async {
  final all = await ref.watch(recentSessionsProvider.future);
  return all.where((s) => s.kind == kind).toList();
});

final appUsageProvider = FutureProvider<AppUsageReport>(
  (ref) => ref.watch(batteryRepositoryProvider).appUsage(),
);

final cyclesUsedProvider = FutureProvider<double>(
  (ref) => ref.watch(batteryRepositoryProvider).cyclesUsed(),
);

final databaseStatsProvider = FutureProvider<DatabaseStats>((ref) async {
  return ref.watch(batteryRepositoryProvider).stats();
});

// --------------------------------------------------------------- settings

/// The alert and sampler settings, kept in step with their native mirror.
///
/// The native side is the authority because it is the copy that is live when
/// the Dart engine is gone, which is most of the time. Writes therefore go
/// down and the result comes back up, rather than being applied optimistically
/// here and pushed down afterwards.
class MonitorSettingsController extends AsyncNotifier<MonitorSettings> {
  @override
  Future<MonitorSettings> build() =>
      ref.watch(batteryChannelProvider).getMonitorSettings();

  /// Applies a change to the settings.
  ///
  /// Named `edit` rather than `update` because [AsyncNotifier] already defines
  /// an `update` with different semantics, and silently overriding it would be
  /// a trap for anyone reading this later.
  Future<void> edit(
    MonitorSettings Function(MonitorSettings current) change,
  ) async {
    final current = state.value ?? const MonitorSettings();
    final next = change(current);
    state = AsyncValue.data(next);
    final applied =
        await ref.read(batteryChannelProvider).setMonitorSettings(next);
    state = AsyncValue.data(applied);
  }

  Future<void> setMonitoring(bool enabled) async {
    final channel = ref.read(batteryChannelProvider);
    if (enabled) {
      await channel.startMonitoring();
    } else {
      await channel.stopMonitoring();
    }
    state = AsyncValue.data(await channel.getMonitorSettings());
  }
}

final monitorSettingsProvider =
    AsyncNotifierProvider<MonitorSettingsController, MonitorSettings>(
  MonitorSettingsController.new,
);

/// Preferences that only the UI cares about, kept out of the native mirror.
class AppPreferences {
  const AppPreferences({
    this.themeMode = AppThemeMode.system,
    this.useFahrenheit = false,
    this.onboardingComplete = false,
  });

  final AppThemeMode themeMode;
  final bool useFahrenheit;
  final bool onboardingComplete;

  AppPreferences copyWith({
    AppThemeMode? themeMode,
    bool? useFahrenheit,
    bool? onboardingComplete,
  }) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        useFahrenheit: useFahrenheit ?? this.useFahrenheit,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );
}

class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  static const _themeKey = 'theme_mode';
  static const _fahrenheitKey = 'use_fahrenheit';
  static const _onboardingKey = 'onboarding_complete';

  @override
  Future<AppPreferences> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return AppPreferences(
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_themeKey),
        orElse: () => AppThemeMode.system,
      ),
      useFahrenheit: prefs.getBool(_fahrenheitKey) ?? false,
      onboardingComplete: prefs.getBool(_onboardingKey) ?? false,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_themeKey, mode.name);
    state = AsyncValue.data(
      (state.value ?? const AppPreferences()).copyWith(themeMode: mode),
    );
  }

  Future<void> setUseFahrenheit(bool value) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_fahrenheitKey, value);
    state = AsyncValue.data(
      (state.value ?? const AppPreferences())
          .copyWith(useFahrenheit: value),
    );
  }

  Future<void> completeOnboarding() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_onboardingKey, true);
    state = AsyncValue.data(
      (state.value ?? const AppPreferences())
          .copyWith(onboardingComplete: true),
    );
  }
}

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
  AppPreferencesController.new,
);

// ------------------------------------------------------------ app actions

/// Launcher icons for the apps currently listed, keyed by package.
///
/// Fetched for the whole list in one call rather than per row: each icon
/// crosses a method-channel reply, and a dozen separate round trips while the
/// list builds shows up as a stutter.
final appIconsProvider = FutureProvider<Map<String, Uint8List>>((ref) async {
  final report = await ref.watch(appUsageProvider.future);
  if (report.apps.isEmpty) return const {};
  return ref.watch(batteryChannelProvider).appIcons(
        report.apps.take(20).map((a) => a.packageName).toList(),
      );
});

/// What the system will allow for one app: whether it can be launched, and
/// whether it can be uninstalled at all.
final appCapabilitiesProvider =
    FutureProvider.family<AppCapabilitiesState, String>((ref, package) async {
  final caps = await ref.watch(batteryChannelProvider).appCapabilities(package);
  return AppCapabilitiesState(
    canLaunch: caps.canLaunch,
    canUninstall: caps.canUninstall,
  );
});

/// Riverpod-side view of [AppCapabilities].
class AppCapabilitiesState {
  const AppCapabilitiesState({
    required this.canLaunch,
    required this.canUninstall,
  });

  final bool canLaunch;
  final bool canUninstall;
}

// ---------------------------------------------------- home screen widgets

final widgetStatusProvider = FutureProvider.autoDispose<WidgetStatus>(
  (ref) => ref.watch(batteryChannelProvider).widgetStatus(),
);

/// Keeps the home screen widgets supplied with the figures only the analytics
/// layer can produce.
///
/// Watches the same providers the Health and Now screens do, so a widget can
/// never disagree with the app about the same moment. The push itself is cheap
/// and the native side ignores it when no widget is placed, so there is no
/// need to gate this on whether the user has one.
final widgetFeedProvider = Provider<void>((ref) {
  final estimate = ref.watch(capacityEstimateProvider).value;
  final drain = ref.watch(drainProfileProvider).value;
  final snapshot = ref.watch(liveSnapshotProvider).value;
  final settings = ref.watch(monitorSettingsProvider).value;
  final prefs = ref.watch(appPreferencesProvider).value;

  final charging = snapshot?.isCharging ?? false;
  final level = snapshot?.levelPct;

  int? forecastMinutes;
  int? target;

  if (charging) {
    // While charging toward a limit the user set, count down to that limit
    // rather than to full: the widget should not answer a question they
    // deliberately stopped asking.
    final limit = (settings?.chargeAlarmEnabled ?? false)
        ? settings?.chargeAlarmPct
        : null;
    final toLimit = ref.watch(timeToChargeLimitProvider).value;
    final toFull = ref.watch(timeToFullProvider).value;

    if (limit != null && toLimit != null && (level ?? 0) < limit) {
      forecastMinutes = toLimit.inMinutes;
      target = limit;
    } else {
      forecastMinutes = toFull?.inMinutes;
      target = 100;
    }
  } else if (level != null && drain != null) {
    final runtime = (snapshot?.screenOn ?? false)
        ? drain.screenOnRuntime(level)
        : drain.mixedRuntime(level);
    forecastMinutes = runtime?.inMinutes;
  }

  unawaited(
    ref.read(batteryChannelProvider).setWidgetData(
          WidgetData(
            healthPct: estimate?.healthPct,
            measuredMah: (estimate != null && !estimate.isEmpty)
                ? estimate.estimatedMah.round()
                : null,
            designMah: estimate?.designMah,
            forecastMinutes: forecastMinutes,
            forecastIsCharging: charging,
            forecastTargetPct: target,
            useFahrenheit: prefs?.useFahrenheit ?? false,
          ),
        ),
  );
});

final themeProvider = Provider<ThemeData>((ref) {
  final mode = ref.watch(appPreferencesProvider).value?.themeMode ??
      AppThemeMode.system;
  final brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return AppTheme.of(mode, brightness);
});
