package com.cellmeter.app.widget

import android.content.Context

/**
 * The figures the widgets need that the native side cannot compute.
 *
 * Level, current and temperature come straight off the battery, so the sampler
 * has them. Health, measured capacity and the runtime forecast are the output
 * of the analytics pipeline, which lives in Dart on top of the database — and
 * the widget has to render long after the Dart engine has been torn down.
 *
 * So Flutter pushes those values down here whenever it recomputes them, and
 * the widget reads the last known set. A stale health figure is harmless: it
 * moves over months, and the widget shows when it was last updated.
 */
class WidgetDataStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Battery health as a percentage of design capacity. */
    var healthPct: Double?
        get() = prefs.getFloat(KEY_HEALTH, -1f).takeIf { it >= 0 }?.toDouble()
        set(value) = prefs.edit().apply {
            if (value == null) remove(KEY_HEALTH) else putFloat(KEY_HEALTH, value.toFloat())
        }.apply()

    /** Measured full-charge capacity, mAh. */
    var measuredMah: Int?
        get() = prefs.getInt(KEY_MEASURED, -1).takeIf { it > 0 }
        set(value) = prefs.edit().apply {
            if (value == null) remove(KEY_MEASURED) else putInt(KEY_MEASURED, value)
        }.apply()

    /** Factory design capacity, mAh. */
    var designMah: Int?
        get() = prefs.getInt(KEY_DESIGN, -1).takeIf { it > 0 }
        set(value) = prefs.edit().apply {
            if (value == null) remove(KEY_DESIGN) else putInt(KEY_DESIGN, value)
        }.apply()

    /**
     * Minutes of runtime left at the user's own measured drain rate, or
     * minutes to the charge target while charging. Null when there is not
     * enough history to say, which the widget shows as a dash rather than a
     * guess.
     */
    var forecastMinutes: Int?
        get() = prefs.getInt(KEY_FORECAST, -1).takeIf { it >= 0 }
        set(value) = prefs.edit().apply {
            if (value == null) remove(KEY_FORECAST) else putInt(KEY_FORECAST, value)
        }.apply()

    /** True when [forecastMinutes] counts toward a charge target. */
    var forecastIsCharging: Boolean
        get() = prefs.getBoolean(KEY_FORECAST_CHARGING, false)
        set(value) = prefs.edit().putBoolean(KEY_FORECAST_CHARGING, value).apply()

    /** The charge target the forecast counts to, for the widget's label. */
    var forecastTargetPct: Int?
        get() = prefs.getInt(KEY_FORECAST_TARGET, -1).takeIf { it in 1..100 }
        set(value) = prefs.edit().apply {
            if (value == null) {
                remove(KEY_FORECAST_TARGET)
            } else {
                putInt(KEY_FORECAST_TARGET, value)
            }
        }.apply()

    /** Whether the temperature readout should be shown in Fahrenheit. */
    var useFahrenheit: Boolean
        get() = prefs.getBoolean(KEY_FAHRENHEIT, false)
        set(value) = prefs.edit().putBoolean(KEY_FAHRENHEIT, value).apply()

    fun applyFromMap(map: Map<*, *>) {
        if (map.containsKey("healthPct")) {
            healthPct = (map["healthPct"] as? Number)?.toDouble()
        }
        if (map.containsKey("measuredMah")) {
            measuredMah = (map["measuredMah"] as? Number)?.toInt()
        }
        if (map.containsKey("designMah")) {
            designMah = (map["designMah"] as? Number)?.toInt()
        }
        if (map.containsKey("forecastMinutes")) {
            forecastMinutes = (map["forecastMinutes"] as? Number)?.toInt()
        }
        if (map.containsKey("forecastTargetPct")) {
            forecastTargetPct = (map["forecastTargetPct"] as? Number)?.toInt()
        }
        (map["forecastIsCharging"] as? Boolean)?.let { forecastIsCharging = it }
        (map["useFahrenheit"] as? Boolean)?.let { useFahrenheit = it }
    }

    private companion object {
        const val PREFS = "cellmeter_widget"
        const val KEY_HEALTH = "health_pct"
        const val KEY_MEASURED = "measured_mah"
        const val KEY_DESIGN = "design_mah"
        const val KEY_FORECAST = "forecast_minutes"
        const val KEY_FORECAST_CHARGING = "forecast_is_charging"
        const val KEY_FORECAST_TARGET = "forecast_target_pct"
        const val KEY_FAHRENHEIT = "use_fahrenheit"
    }
}
