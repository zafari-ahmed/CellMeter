import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_models.dart';

/// The Dart half of the platform bridge.
///
/// Every call is wrapped so a missing implementation degrades to a null or an
/// empty list rather than throwing into the widget tree. The app is expected to
/// run on devices that do not implement half of what it asks for, so a failed
/// platform call is an ordinary outcome, not an error condition.
class BatteryChannel {
  BatteryChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_name);

  static const String _name = 'com.cellmeter.app/battery';

  final MethodChannel _channel;

  /// Only Android exposes the fuel-gauge properties this app is built on.
  /// iOS reports a rounded level and a charging flag and nothing else, so the
  /// UI degrades to a basic readout rather than inventing numbers.
  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  // --------------------------------------------------------- live readings

  Future<BatterySnapshot?> readSnapshot() async {
    final map = await _invokeMap('readSnapshot');
    return map == null ? null : BatterySnapshot.fromMap(map);
  }

  Future<DesignCapacityInfo> designCapacity() async {
    final map = await _invokeMap('designCapacity');
    return map == null
        ? const DesignCapacityInfo()
        : DesignCapacityInfo.fromMap(map);
  }

  /// Sets the design capacity by hand, for devices that report none and for
  /// batteries that have been replaced with a cell of a different size.
  Future<DesignCapacityInfo> setDesignCapacityOverride(int? mah) async {
    final map = await _invokeMap(
      'setDesignCapacityOverride',
      {'mah': mah},
    );
    return map == null
        ? const DesignCapacityInfo()
        : DesignCapacityInfo.fromMap(map);
  }

  Future<NativeDeviceInfo> deviceInfo() async {
    final map = await _invokeMap('deviceInfo');
    return map == null
        ? NativeDeviceInfo.empty
        : NativeDeviceInfo.fromMap(map);
  }

  // ---------------------------------------------------------------- sampler

  Future<bool> startMonitoring() async =>
      await _invoke<bool>('startMonitoring') ?? false;

  Future<bool> stopMonitoring() async =>
      await _invoke<bool>('stopMonitoring') ?? false;

  /// Asks the sampler for an immediate reading, used when the user pulls to
  /// refresh so the screen does not wait for the next tick.
  Future<void> sampleNow() => _invoke<bool>('sampleNow');

  // ------------------------------------------------------------ sample spool

  /// Reads spooled samples without removing them.
  ///
  /// Deletion is a separate call on purpose: the samples are only dropped once
  /// Dart has committed them to the database, so a crash between the two costs
  /// a repeated insert rather than a lost measurement.
  Future<SpoolBatch> readSpool({int maxLines = 20000}) async {
    final map = await _invokeMap('readSpool', {'maxLines': maxLines});
    if (map == null) return const SpoolBatch(snapshots: [], lineCount: 0);

    final rawLines = (map['lines'] as List?) ?? const [];
    final snapshots = <BatterySnapshot>[];
    var parsed = 0;

    for (final line in rawLines) {
      parsed++;
      try {
        final decoded = jsonDecode(line as String);
        if (decoded is Map<String, dynamic>) {
          snapshots.add(BatterySnapshot.fromSpoolJson(decoded));
        }
      } catch (_) {
        // A malformed line is skipped but still counted, so it gets consumed
        // and cannot wedge the ingest loop on every run.
      }
    }

    return SpoolBatch(snapshots: snapshots, lineCount: parsed);
  }

  /// Drops the first [lineCount] spooled lines. Call only after a successful
  /// database commit.
  Future<int> consumeSpool(int lineCount) async =>
      await _invoke<int>('consumeSpool', {'lineCount': lineCount}) ?? 0;

  Future<int> spoolSizeBytes() async =>
      (await _invoke<num>('spoolSize'))?.toInt() ?? 0;

  Future<void> clearSpool() => _invoke<bool>('clearSpool');

  // --------------------------------------------------------------- settings

  Future<MonitorSettings> getMonitorSettings() async {
    final map = await _invokeMap('getMonitorSettings');
    return map == null ? const MonitorSettings() : MonitorSettings.fromMap(map);
  }

  Future<MonitorSettings> setMonitorSettings(MonitorSettings settings) async {
    final map = await _invokeMap('setMonitorSettings', settings.toMap());
    return map == null ? settings : MonitorSettings.fromMap(map);
  }

  // -------------------------------------------------------------- app usage

  Future<bool> hasUsageAccess() async =>
      await _invoke<bool>('hasUsageAccess') ?? false;

  /// Opens the system Usage Access screen. There is no runtime dialog for this
  /// permission, so sending the user to settings is the only way to ask.
  Future<void> openUsageAccessSettings() =>
      _invoke<bool>('openUsageAccessSettings');

  Future<List<ForegroundSlice>> foregroundSlices({
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await _invoke<List<dynamic>>('foregroundSlices', {
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
    });
    if (result == null) return const [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(ForegroundSlice.fromMap)
        .toList(growable: false);
  }

  // --------------------------------------------------------- system dialogs

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke<bool>('requestIgnoreBatteryOptimizations');

  Future<void> openNotificationSettings() =>
      _invoke<bool>('openNotificationSettings');

  // ----------------------------------------------------- home screen widgets

  Future<WidgetStatus> widgetStatus() async {
    final map = await _invokeMap('widgetStatus');
    return map == null ? const WidgetStatus() : WidgetStatus.fromMap(map);
  }

  /// Asks the launcher to show its own add-widget dialog.
  ///
  /// Android never lets an app place a widget by itself; this only opens the
  /// system prompt, and the user still taps to confirm. Returns false when the
  /// launcher does not support pinning at all, which is the caller's cue to
  /// show the manual instructions instead.
  Future<bool> requestPinWidget({WidgetKind kind = WidgetKind.battery}) async =>
      await _invoke<bool>('requestPinWidget', {'kind': kind.name}) ?? false;

  /// Pushes the analytics figures a widget cannot compute for itself.
  ///
  /// Level and current come off the battery, so the native sampler has them.
  /// Health, measured capacity and the runtime forecast are the output of the
  /// Dart pipeline, and the widget has to render long after this engine is
  /// gone — so they are mirrored natively whenever they change.
  Future<void> setWidgetData(WidgetData data) =>
      _invoke<bool>('setWidgetData', data.toMap());

  // -------------------------------------------------------------- internals

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupportedPlatform) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, stack) {
      debugPrint('BatteryChannel.$method failed: ${e.message}');
      assert(() {
        debugPrintStack(stackTrace: stack);
        return true;
      }());
      return null;
    }
  }

  Future<Map<dynamic, dynamic>?> _invokeMap(
    String method, [
    Map<String, dynamic>? args,
  ]) =>
      _invoke<Map<dynamic, dynamic>>(method, args);
}

/// Which of the two widgets an action refers to.
enum WidgetKind {
  /// The resizable live readout, 2x1 through 4x2.
  battery,

  /// The 2x2 health ring.
  health;

  String get label => switch (this) {
        WidgetKind.battery => 'Battery widget',
        WidgetKind.health => 'Health widget',
      };
}

/// What the launcher supports, and whether any widget is already placed.
class WidgetStatus {
  const WidgetStatus({this.canPin = false, this.hasPlacedWidgets = false});

  /// Whether the launcher implements `requestPinAppWidget`. Most do; a few
  /// OEM and third-party launchers do not, and there the user adds the widget
  /// from the picker instead.
  final bool canPin;

  final bool hasPlacedWidgets;

  static WidgetStatus fromMap(Map<dynamic, dynamic> map) => WidgetStatus(
        canPin: map['canPin'] as bool? ?? false,
        hasPlacedWidgets: map['hasPlacedWidgets'] as bool? ?? false,
      );
}

/// The figures mirrored down to the widgets.
class WidgetData {
  const WidgetData({
    this.healthPct,
    this.measuredMah,
    this.designMah,
    this.forecastMinutes,
    this.forecastIsCharging = false,
    this.forecastTargetPct,
    this.useFahrenheit = false,
  });

  final double? healthPct;
  final int? measuredMah;
  final int? designMah;

  /// Minutes of runtime left, or minutes to the charge target while charging.
  final int? forecastMinutes;

  /// Which direction [forecastMinutes] was computed in. The widget discards
  /// the forecast when this no longer matches the live charging state, rather
  /// than showing a discharge estimate to someone who has just plugged in.
  final bool forecastIsCharging;

  final int? forecastTargetPct;
  final bool useFahrenheit;

  Map<String, dynamic> toMap() => {
        'healthPct': healthPct,
        'measuredMah': measuredMah,
        'designMah': designMah,
        'forecastMinutes': forecastMinutes,
        'forecastIsCharging': forecastIsCharging,
        'forecastTargetPct': forecastTargetPct,
        'useFahrenheit': useFahrenheit,
      };
}

/// A batch of spooled samples plus how many raw lines produced it.
///
/// [lineCount] counts lines read, including any that failed to parse, because
/// that is the number the native side needs in order to drop exactly what was
/// handed over.
class SpoolBatch {
  const SpoolBatch({required this.snapshots, required this.lineCount});

  final List<BatterySnapshot> snapshots;
  final int lineCount;

  bool get isEmpty => lineCount == 0;
}
