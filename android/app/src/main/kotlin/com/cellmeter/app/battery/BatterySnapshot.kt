package com.cellmeter.app.battery

import org.json.JSONObject

/**
 * One instantaneous reading of every battery metric the device exposes.
 *
 * Every numeric field is nullable on purpose: Android guarantees almost none of
 * them. [BatteryReader] writes `null` rather than a sentinel when a value is
 * missing or obviously bogus, so the analytics layer can tell "unsupported on
 * this device" apart from "genuinely zero".
 *
 * Units are normalised here once, at the edge, so nothing downstream has to
 * remember that Android reports temperature in tenths of a degree and current
 * in microamps:
 *  - [levelPct]        percent, 0..100
 *  - [chargeCounterUah] microamp-hours remaining (coulomb counter)
 *  - [currentNowUa]     microamps, sign-corrected so discharge is negative
 *  - [currentAvgUa]     microamps, sign-corrected
 *  - [voltageMv]        millivolts
 *  - [temperatureC]     degrees Celsius
 *  - [energyCounterNwh] nanowatt-hours remaining
 */
data class BatterySnapshot(
    val timestampMs: Long,
    val levelPct: Double?,
    val chargeCounterUah: Long?,
    val currentNowUa: Long?,
    val currentAvgUa: Long?,
    val voltageMv: Int?,
    val temperatureC: Double?,
    val energyCounterNwh: Long?,
    /** One of [Status]. */
    val status: String,
    /** One of [PlugType]. */
    val plugType: String,
    /** One of [Health]. */
    val health: String,
    val technology: String?,
    val present: Boolean,
    /** True while the screen is interactive — splits screen-on from screen-off drain. */
    val screenOn: Boolean,
    /** Milliseconds the device has been awake since boot (uptimeMillis). */
    val uptimeMs: Long,
    /** Milliseconds of wall-clock since boot (elapsedRealtime), includes deep sleep. */
    val elapsedRealtimeMs: Long,
    /** OEM-reported state of health, percent. Android 14+ only, often absent. */
    val stateOfHealthPct: Int?,
    /** Battery manufacturing date, epoch seconds. Android 15+ only. */
    val manufacturingDateSec: Long?,
    /** Date of first use, epoch seconds. Android 15+ only. */
    val firstUsageDateSec: Long?,
    /** Charging cycle count as reported by the OEM, if exposed. */
    val cycleCount: Int?,
    /** Whether the device reports it is currently power-saving. */
    val powerSaveMode: Boolean,
) {
    object Status {
        const val CHARGING = "charging"
        const val DISCHARGING = "discharging"
        const val FULL = "full"
        const val NOT_CHARGING = "notCharging"
        const val UNKNOWN = "unknown"
    }

    object PlugType {
        const val NONE = "none"
        const val AC = "ac"
        const val USB = "usb"
        const val WIRELESS = "wireless"
        const val DOCK = "dock"
        const val UNKNOWN = "unknown"
    }

    object Health {
        const val GOOD = "good"
        const val OVERHEAT = "overheat"
        const val DEAD = "dead"
        const val OVER_VOLTAGE = "overVoltage"
        const val COLD = "cold"
        const val UNSPECIFIED_FAILURE = "unspecifiedFailure"
        const val UNKNOWN = "unknown"
    }

    val isCharging: Boolean
        get() = status == Status.CHARGING || status == Status.FULL

    /** Instantaneous power draw in milliwatts, when both current and voltage are known. */
    val powerMw: Double?
        get() {
            val ua = currentNowUa ?: return null
            val mv = voltageMv ?: return null
            // uA * mV = nW; /1_000_000 -> mW
            return (ua.toDouble() * mv.toDouble()) / 1_000_000.0
        }

    fun toJson(): JSONObject = JSONObject().apply {
        put("t", timestampMs)
        putOrNull("lvl", levelPct)
        putOrNull("cc", chargeCounterUah)
        putOrNull("cur", currentNowUa)
        putOrNull("cavg", currentAvgUa)
        putOrNull("mv", voltageMv)
        putOrNull("temp", temperatureC)
        putOrNull("nwh", energyCounterNwh)
        put("st", status)
        put("plug", plugType)
        put("hlth", health)
        putOrNull("tech", technology)
        put("pres", present)
        put("scr", screenOn)
        put("up", uptimeMs)
        put("ert", elapsedRealtimeMs)
        putOrNull("soh", stateOfHealthPct)
        putOrNull("mfg", manufacturingDateSec)
        putOrNull("fu", firstUsageDateSec)
        putOrNull("cyc", cycleCount)
        put("psm", powerSaveMode)
    }

    /** Map form used by the MethodChannel for the live-reading stream. */
    fun toMap(): Map<String, Any?> = mapOf(
        "timestampMs" to timestampMs,
        "levelPct" to levelPct,
        "chargeCounterUah" to chargeCounterUah,
        "currentNowUa" to currentNowUa,
        "currentAvgUa" to currentAvgUa,
        "voltageMv" to voltageMv,
        "temperatureC" to temperatureC,
        "energyCounterNwh" to energyCounterNwh,
        "status" to status,
        "plugType" to plugType,
        "health" to health,
        "technology" to technology,
        "present" to present,
        "screenOn" to screenOn,
        "uptimeMs" to uptimeMs,
        "elapsedRealtimeMs" to elapsedRealtimeMs,
        "stateOfHealthPct" to stateOfHealthPct,
        "manufacturingDateSec" to manufacturingDateSec,
        "firstUsageDateSec" to firstUsageDateSec,
        "cycleCount" to cycleCount,
        "powerSaveMode" to powerSaveMode,
    )

    private fun JSONObject.putOrNull(key: String, value: Any?) {
        if (value != null) put(key, value)
    }
}
