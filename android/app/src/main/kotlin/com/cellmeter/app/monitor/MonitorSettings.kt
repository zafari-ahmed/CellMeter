package com.cellmeter.app.monitor

import android.content.Context

/**
 * Settings the native sampler needs while Flutter is not running.
 *
 * Flutter owns the user-facing copy of these values; it pushes them down
 * through the method channel whenever they change, and the service reads them
 * from here on every tick. Keeping a native mirror means the charge alarm and
 * the drain alert still fire when the Dart engine has been torn down, which is
 * the common case for a monitoring app.
 */
class MonitorSettings(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var monitoringEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** Notify when charge reaches this percentage. 0 disables the alarm. */
    var chargeAlarmPct: Int
        get() = prefs.getInt(KEY_CHARGE_ALARM, 80)
        set(value) = prefs.edit().putInt(KEY_CHARGE_ALARM, value.coerceIn(0, 100)).apply()

    var chargeAlarmEnabled: Boolean
        get() = prefs.getBoolean(KEY_CHARGE_ALARM_ON, true)
        set(value) = prefs.edit().putBoolean(KEY_CHARGE_ALARM_ON, value).apply()

    /** Notify when the battery falls to this percentage. 0 disables. */
    var lowBatteryPct: Int
        get() = prefs.getInt(KEY_LOW_BATTERY, 15)
        set(value) = prefs.edit().putInt(KEY_LOW_BATTERY, value.coerceIn(0, 100)).apply()

    var lowBatteryEnabled: Boolean
        get() = prefs.getBoolean(KEY_LOW_BATTERY_ON, true)
        set(value) = prefs.edit().putBoolean(KEY_LOW_BATTERY_ON, value).apply()

    var highDrainEnabled: Boolean
        get() = prefs.getBoolean(KEY_DRAIN_ON, true)
        set(value) = prefs.edit().putBoolean(KEY_DRAIN_ON, value).apply()

    /** Drain alert threshold, percent of battery per hour. */
    var highDrainPctPerHour: Double
        get() = prefs.getFloat(KEY_DRAIN_THRESHOLD, 18f).toDouble()
        set(value) = prefs.edit()
            .putFloat(KEY_DRAIN_THRESHOLD, value.coerceIn(1.0, 100.0).toFloat()).apply()

    /** Sustained minutes above the threshold before the drain alert fires. */
    var highDrainSustainMinutes: Int
        get() = prefs.getInt(KEY_DRAIN_SUSTAIN, 10)
        set(value) = prefs.edit().putInt(KEY_DRAIN_SUSTAIN, value.coerceIn(1, 120)).apply()

    var temperatureAlertEnabled: Boolean
        get() = prefs.getBoolean(KEY_TEMP_ON, true)
        set(value) = prefs.edit().putBoolean(KEY_TEMP_ON, value).apply()

    var temperatureAlertC: Double
        get() = prefs.getFloat(KEY_TEMP_THRESHOLD, 42f).toDouble()
        set(value) = prefs.edit()
            .putFloat(KEY_TEMP_THRESHOLD, value.coerceIn(30.0, 70.0).toFloat()).apply()

    /** Whether the persistent status notification shows live statistics. */
    var showStatsInNotification: Boolean
        get() = prefs.getBoolean(KEY_STATS_NOTIF, true)
        set(value) = prefs.edit().putBoolean(KEY_STATS_NOTIF, value).apply()

    fun applyFromMap(map: Map<*, *>) {
        (map["monitoringEnabled"] as? Boolean)?.let { monitoringEnabled = it }
        (map["chargeAlarmEnabled"] as? Boolean)?.let { chargeAlarmEnabled = it }
        (map["chargeAlarmPct"] as? Number)?.let { chargeAlarmPct = it.toInt() }
        (map["lowBatteryEnabled"] as? Boolean)?.let { lowBatteryEnabled = it }
        (map["lowBatteryPct"] as? Number)?.let { lowBatteryPct = it.toInt() }
        (map["highDrainEnabled"] as? Boolean)?.let { highDrainEnabled = it }
        (map["highDrainPctPerHour"] as? Number)?.let { highDrainPctPerHour = it.toDouble() }
        (map["highDrainSustainMinutes"] as? Number)?.let {
            highDrainSustainMinutes = it.toInt()
        }
        (map["temperatureAlertEnabled"] as? Boolean)?.let { temperatureAlertEnabled = it }
        (map["temperatureAlertC"] as? Number)?.let { temperatureAlertC = it.toDouble() }
        (map["showStatsInNotification"] as? Boolean)?.let { showStatsInNotification = it }
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "monitoringEnabled" to monitoringEnabled,
        "chargeAlarmEnabled" to chargeAlarmEnabled,
        "chargeAlarmPct" to chargeAlarmPct,
        "lowBatteryEnabled" to lowBatteryEnabled,
        "lowBatteryPct" to lowBatteryPct,
        "highDrainEnabled" to highDrainEnabled,
        "highDrainPctPerHour" to highDrainPctPerHour,
        "highDrainSustainMinutes" to highDrainSustainMinutes,
        "temperatureAlertEnabled" to temperatureAlertEnabled,
        "temperatureAlertC" to temperatureAlertC,
        "showStatsInNotification" to showStatsInNotification,
    )

    private companion object {
        const val PREFS = "cellmeter_monitor"
        const val KEY_ENABLED = "monitoring_enabled"
        const val KEY_CHARGE_ALARM = "charge_alarm_pct"
        const val KEY_CHARGE_ALARM_ON = "charge_alarm_enabled"
        const val KEY_LOW_BATTERY = "low_battery_pct"
        const val KEY_LOW_BATTERY_ON = "low_battery_enabled"
        const val KEY_DRAIN_ON = "drain_enabled"
        const val KEY_DRAIN_THRESHOLD = "drain_threshold"
        const val KEY_DRAIN_SUSTAIN = "drain_sustain_minutes"
        const val KEY_TEMP_ON = "temp_enabled"
        const val KEY_TEMP_THRESHOLD = "temp_threshold"
        const val KEY_STATS_NOTIF = "stats_notification"
    }
}
