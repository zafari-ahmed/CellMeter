package com.cellmeter.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.cellmeter.app.battery.AppActions
import com.cellmeter.app.battery.AppUsageReader
import com.cellmeter.app.battery.BatteryReader
import com.cellmeter.app.battery.DesignCapacity
import com.cellmeter.app.monitor.MonitorService
import com.cellmeter.app.monitor.MonitorSettings
import com.cellmeter.app.monitor.Notifications
import com.cellmeter.app.monitor.SampleSink
import com.cellmeter.app.widget.WidgetDataStore
import com.cellmeter.app.widget.WidgetPinner
import com.cellmeter.app.widget.WidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The single bridge between Flutter and everything Android-specific.
 *
 * Deliberately thin: it routes calls, it does not compute. All measurement
 * lives in [BatteryReader] and the sampler service, all analysis lives in Dart.
 */
class MainActivity : FlutterActivity() {

    private val reader by lazy { BatteryReader(applicationContext) }
    private val usage by lazy { AppUsageReader(applicationContext) }
    private val appActions by lazy { AppActions(applicationContext) }
    private val sink by lazy { SampleSink(applicationContext) }
    private val settings by lazy { MonitorSettings(applicationContext) }
    private val widgetData by lazy { WidgetDataStore(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notifications.ensureChannels(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                // ----------------------------------------------- live reading
                "readSnapshot" -> result.success(reader.read().toMap())

                "designCapacity" ->
                    result.success(DesignCapacity.resolve(applicationContext).toMap())

                "setDesignCapacityOverride" -> {
                    val mah = (call.argument<Number>("mah"))?.toInt()
                    DesignCapacity.setOverride(applicationContext, mah)
                    result.success(DesignCapacity.resolve(applicationContext).toMap())
                }

                "deviceInfo" -> result.success(deviceInfo())

                // ------------------------------------------------- sampler
                "startMonitoring" -> {
                    settings.monitoringEnabled = true
                    MonitorService.start(applicationContext)
                    result.success(true)
                }

                "stopMonitoring" -> {
                    settings.monitoringEnabled = false
                    MonitorService.stop(applicationContext)
                    result.success(true)
                }

                "sampleNow" -> {
                    MonitorService.sampleNow(applicationContext)
                    result.success(true)
                }

                // --------------------------------------------- sample spool
                "readSpool" -> {
                    val max = (call.argument<Number>("maxLines"))?.toInt() ?: 20_000
                    result.success(readSpool(max))
                }

                "consumeSpool" -> {
                    val lines = (call.argument<Number>("lineCount"))?.toInt() ?: 0
                    result.success(sink.consumeThrough(lines))
                }

                "spoolSize" -> result.success(sink.sizeBytes())

                "clearSpool" -> {
                    sink.clear()
                    result.success(true)
                }

                // ------------------------------------------------- settings
                "getMonitorSettings" -> result.success(settings.toMap())

                "setMonitorSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.arguments as? Map<String, Any?> ?: emptyMap()
                    settings.applyFromMap(map)
                    if (settings.monitoringEnabled) {
                        MonitorService.start(applicationContext)
                    } else {
                        MonitorService.stop(applicationContext)
                    }
                    result.success(settings.toMap())
                }

                // ---------------------------------------------- app usage
                "hasUsageAccess" -> result.success(usage.hasUsageAccess())

                "openUsageAccessSettings" -> {
                    startActivity(usage.usageAccessSettingsIntent())
                    result.success(true)
                }

                "foregroundSlices" -> {
                    val start = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                    val end = (call.argument<Number>("endMs"))?.toLong()
                        ?: System.currentTimeMillis()
                    result.success(usage.foregroundSlices(start, end).map { it.toMap() })
                }

                // ------------------------------------------- battery saver
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }

                // ------------------------------------------ app actions
                //
                // No "force stop" here. That needs a signature permission, and
                // the one public alternative only drops processes the system
                // restarts, so it would look like it worked and do nothing.
                // These open the system screens that genuinely can.
                "openAppSettings" -> result.success(
                    appActions.openAppSettings(call.argument<String>("package") ?: "")
                )

                "launchApp" -> result.success(
                    appActions.launchApp(call.argument<String>("package") ?: "")
                )

                "requestUninstall" -> result.success(
                    appActions.requestUninstall(call.argument<String>("package") ?: "")
                )

                "appCapabilities" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    result.success(
                        mapOf(
                            "canUninstall" to appActions.canUninstall(pkg),
                            "canLaunch" to appActions.hasLaunchIntent(pkg),
                        )
                    )
                }

                "appIcons" -> {
                    val packages = call.argument<List<String>>("packages").orEmpty()
                    result.success(
                        packages.associateWith { appActions.iconPng(it) }
                            .filterValues { it != null },
                    )
                }

                // ------------------------------------------- home widgets
                "widgetStatus" -> result.success(
                    mapOf(
                        "canPin" to WidgetPinner.canPin(applicationContext),
                        "hasPlacedWidgets" to
                            WidgetUpdater.hasPlacedWidgets(applicationContext),
                    )
                )

                "requestPinWidget" -> {
                    val kind = if (call.argument<String>("kind") == "health") {
                        WidgetPinner.Kind.HEALTH
                    } else {
                        WidgetPinner.Kind.BATTERY
                    }
                    result.success(WidgetPinner.requestPin(applicationContext, kind))
                }

                // Pushes the figures only the analytics layer can produce —
                // health, measured capacity, the runtime forecast — down to
                // where the widget can read them with no Dart engine alive.
                "setWidgetData" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.arguments as? Map<String, Any?> ?: emptyMap()
                    widgetData.applyFromMap(map)
                    WidgetUpdater.update(applicationContext, force = true)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("native_error", t.message, t.stackTraceToString())
        }
    }

    /**
     * Returns up to [maxLines] spooled samples as raw JSON strings, oldest
     * first, plus how many lines were returned. Dart parses and inserts them,
     * then calls `consumeSpool` with that count — never before, so a crash
     * mid-ingest costs a repeat rather than a loss.
     *
     * A trailing partial line (process killed mid-append) is dropped.
     */
    private fun readSpool(maxLines: Int): Map<String, Any?> {
        val file: File = sink.spoolFile
        if (!file.exists()) return mapOf("lines" to emptyList<String>(), "count" to 0)

        val lines = ArrayList<String>(minOf(maxLines, 4096))
        file.useLines { sequence ->
            for (line in sequence) {
                if (lines.size >= maxLines) break
                val trimmed = line.trim()
                if (trimmed.isEmpty()) continue
                // Guard against the final write having been cut short.
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) continue
                lines.add(trimmed)
            }
        }
        return mapOf("lines" to lines, "count" to lines.size)
    }

    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "device" to Build.DEVICE,
        "sdkInt" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "hasUsageAccess" to usage.hasUsageAccess(),
        "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
    )

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Opens the system prompt that exempts CellMeter from battery
     * optimisation. The app works without it, but Doze can otherwise suspend
     * the sampler for long stretches and leave holes in overnight charges.
     */
    private fun requestIgnoreBatteryOptimizations() {
        runCatching {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName"))
            )
        }.onFailure {
            runCatching {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
    }

    private fun openNotificationSettings() {
        runCatching {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            )
        }
    }

    private companion object {
        const val CHANNEL = "com.cellmeter.app/battery"
    }
}
