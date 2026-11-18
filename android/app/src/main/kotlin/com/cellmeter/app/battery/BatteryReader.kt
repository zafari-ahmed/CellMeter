package com.cellmeter.app.battery

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import kotlin.math.abs

/**
 * Reads every battery metric this device is willing to expose.
 *
 * Two independent sources are merged:
 *  1. The sticky [Intent.ACTION_BATTERY_CHANGED] broadcast — level, scale,
 *     voltage, temperature, health, plug type, technology. Present on every
 *     device since API 1.
 *  2. [BatteryManager] integer properties — coulomb counter, instantaneous and
 *     average current, energy counter, and on newer releases state-of-health
 *     and battery dates. These come straight off the fuel gauge and are the
 *     only trustworthy basis for capacity measurement, but OEMs are free to
 *     return garbage and many do.
 *
 * Every property read is defensive: unsupported properties come back as
 * [Int.MIN_VALUE], [Long.MIN_VALUE] or 0 depending on the OEM, so each getter
 * screens the value against a plausible range before returning it.
 */
class BatteryReader(private val context: Context) {

    private val batteryManager: BatteryManager? =
        context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager

    private val powerManager: PowerManager? =
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager

    /**
     * Some OEMs report discharge as a positive current and charge as negative,
     * the opposite of the documented convention. Detected once per process by
     * comparing the sign of CURRENT_NOW against the known charging state, then
     * cached so the sign stays stable across a session.
     */
    @Volatile
    private var currentSignInverted: Boolean? = null

    fun read(): BatterySnapshot {
        val intent = stickyBatteryIntent()
        val status = mapStatus(intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1)
        val charging = status == BatterySnapshot.Status.CHARGING ||
            status == BatterySnapshot.Status.FULL

        val rawCurrentNow = intProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        val rawCurrentAvg = intProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE)

        calibrateCurrentSign(rawCurrentNow, status)

        return BatterySnapshot(
            timestampMs = System.currentTimeMillis(),
            levelPct = readLevelPct(intent),
            chargeCounterUah = readChargeCounter(),
            currentNowUa = normaliseCurrent(rawCurrentNow, charging),
            currentAvgUa = normaliseCurrent(rawCurrentAvg, charging),
            voltageMv = readVoltageMv(intent),
            temperatureC = readTemperatureC(intent),
            energyCounterNwh = readEnergyCounter(),
            status = status,
            plugType = mapPlugType(intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0),
            health = mapHealth(intent?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1),
            technology = intent?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            present = intent?.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true) ?: true,
            screenOn = isScreenOn(),
            uptimeMs = SystemClock.uptimeMillis(),
            elapsedRealtimeMs = SystemClock.elapsedRealtime(),
            stateOfHealthPct = readStateOfHealth(),
            manufacturingDateSec = readDateProperty(PROP_MANUFACTURING_DATE),
            firstUsageDateSec = readDateProperty(PROP_FIRST_USAGE_DATE),
            cycleCount = readCycleCount(intent),
            powerSaveMode = powerManager?.isPowerSaveMode == true,
        )
    }

    fun stickyBatteryIntent(): Intent? = try {
        context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    } catch (_: Exception) {
        null
    }

    fun isScreenOn(): Boolean = powerManager?.isInteractive == true

    // ---------------------------------------------------------------- level

    /**
     * Level as a percentage. Prefers the broadcast's level/scale pair because a
     * handful of devices report a scale other than 100; falls back to the
     * BatteryManager property.
     */
    private fun readLevelPct(intent: Intent?): Double? {
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level >= 0 && scale > 0) {
            return (level.toDouble() / scale.toDouble()) * 100.0
        }
        val prop = intProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (prop != null && prop in 0..100) prop.toDouble() else null
    }

    // ------------------------------------------------------------- counters

    /**
     * Remaining charge in microamp-hours. This is the single most important
     * value in the app: capacity measurement is a difference of two of these
     * divided by the level change between them.
     *
     * Rejected when it is non-positive or implausibly large (> 100 Ah), which is
     * what devices without a real coulomb counter tend to return.
     */
    private fun readChargeCounter(): Long? {
        val raw = longProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER) ?: return null
        if (raw <= 0L) return null
        if (raw > 100_000_000L) return null // > 100 Ah is not a phone battery
        return raw
    }

    private fun readEnergyCounter(): Long? {
        val raw = longProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER) ?: return null
        return if (raw <= 0L) null else raw
    }

    // -------------------------------------------------------------- current

    /**
     * Learns this device's current-sign convention. The documented contract is
     * negative while discharging, but a significant minority of OEMs invert it.
     * We only trust a sample that is clearly non-zero and taken while the
     * charging state is unambiguous.
     */
    private fun calibrateCurrentSign(raw: Int?, status: String) {
        if (currentSignInverted != null) return
        val value = raw ?: return
        if (abs(value) < 20_000) return // below 20 mA the sign is noise
        when (status) {
            BatterySnapshot.Status.CHARGING ->
                currentSignInverted = value < 0
            BatterySnapshot.Status.DISCHARGING ->
                currentSignInverted = value > 0
        }
    }

    /**
     * Returns current in microamps with the documented sign convention:
     * positive while charging, negative while discharging.
     */
    private fun normaliseCurrent(raw: Int?, charging: Boolean): Long? {
        val value = raw ?: return null
        if (value == 0) return 0L
        // Some devices report milliamps in this field. A phone never pulls more
        // than ~20 A, so anything past that is a unit mismatch, not a reading.
        if (abs(value.toLong()) > 20_000_000L) return null

        val corrected = if (currentSignInverted == true) -value.toLong() else value.toLong()
        // Final guard: once we know the charging state, force the sign to match.
        return when {
            charging && corrected < 0 -> -corrected
            !charging && corrected > 0 -> -corrected
            else -> corrected
        }
    }

    // ---------------------------------------------------------- voltage/temp

    private fun readVoltageMv(intent: Intent?): Int? {
        val raw = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
        if (raw <= 0) return null
        // A few devices report microvolts here.
        val mv = if (raw > 100_000) raw / 1000 else raw
        return if (mv in 1000..20_000) mv else null
    }

    private fun readTemperatureC(intent: Intent?): Double? {
        val raw = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            ?: Int.MIN_VALUE
        if (raw == Int.MIN_VALUE) return null
        val celsius = raw / 10.0
        return if (celsius in -40.0..150.0) celsius else null
    }

    // ----------------------------------------------------------- newer APIs

    /** OEM state of health, percent. [BatteryManager.BATTERY_PROPERTY_STATE_OF_HEALTH], API 34+. */
    private fun readStateOfHealth(): Int? {
        if (Build.VERSION.SDK_INT < 34) return null
        val raw = intProperty(PROP_STATE_OF_HEALTH) ?: return null
        return if (raw in 1..100) raw else null
    }

    /** Battery manufacturing / first-usage dates, epoch seconds. API 35+. */
    private fun readDateProperty(property: Int): Long? {
        if (Build.VERSION.SDK_INT < 35) return null
        val raw = longProperty(property) ?: return null
        // Sanity: between 2005 and 20 years from now.
        val now = System.currentTimeMillis() / 1000
        return if (raw in 1_100_000_000L..(now + 630_000_000L)) raw else null
    }

    /**
     * Cycle count. Exposed as a broadcast extra on API 34+, and on many older
     * devices only through sysfs (usually unreadable without root).
     */
    private fun readCycleCount(intent: Intent?): Int? {
        if (Build.VERSION.SDK_INT >= 34) {
            val raw = intent?.getIntExtra(EXTRA_CYCLE_COUNT, -1) ?: -1
            if (raw in 1..10_000) return raw
        }
        return SysfsBattery.cycleCount()
    }

    // ------------------------------------------------------- property reads

    private fun intProperty(property: Int): Int? {
        val bm = batteryManager ?: return null
        return try {
            val value = bm.getIntProperty(property)
            if (value == Int.MIN_VALUE) null else value
        } catch (_: Exception) {
            null
        }
    }

    private fun longProperty(property: Int): Long? {
        val bm = batteryManager ?: return null
        return try {
            val value = bm.getLongProperty(property)
            if (value == Long.MIN_VALUE || value == Long.MAX_VALUE) null else value
        } catch (_: Exception) {
            null
        }
    }

    // --------------------------------------------------------------- mapping

    private fun mapStatus(value: Int): String = when (value) {
        BatteryManager.BATTERY_STATUS_CHARGING -> BatterySnapshot.Status.CHARGING
        BatteryManager.BATTERY_STATUS_DISCHARGING -> BatterySnapshot.Status.DISCHARGING
        BatteryManager.BATTERY_STATUS_FULL -> BatterySnapshot.Status.FULL
        BatteryManager.BATTERY_STATUS_NOT_CHARGING -> BatterySnapshot.Status.NOT_CHARGING
        else -> BatterySnapshot.Status.UNKNOWN
    }

    private fun mapPlugType(value: Int): String = when (value) {
        0 -> BatterySnapshot.PlugType.NONE
        BatteryManager.BATTERY_PLUGGED_AC -> BatterySnapshot.PlugType.AC
        BatteryManager.BATTERY_PLUGGED_USB -> BatterySnapshot.PlugType.USB
        BatteryManager.BATTERY_PLUGGED_WIRELESS -> BatterySnapshot.PlugType.WIRELESS
        PLUGGED_DOCK -> BatterySnapshot.PlugType.DOCK
        else -> BatterySnapshot.PlugType.UNKNOWN
    }

    private fun mapHealth(value: Int): String = when (value) {
        BatteryManager.BATTERY_HEALTH_GOOD -> BatterySnapshot.Health.GOOD
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> BatterySnapshot.Health.OVERHEAT
        BatteryManager.BATTERY_HEALTH_DEAD -> BatterySnapshot.Health.DEAD
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> BatterySnapshot.Health.OVER_VOLTAGE
        BatteryManager.BATTERY_HEALTH_COLD -> BatterySnapshot.Health.COLD
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE ->
            BatterySnapshot.Health.UNSPECIFIED_FAILURE
        else -> BatterySnapshot.Health.UNKNOWN
    }

    private companion object {
        /** BatteryManager.BATTERY_PROPERTY_STATE_OF_HEALTH, API 34. */
        const val PROP_STATE_OF_HEALTH = 9

        /** BatteryManager.BATTERY_PROPERTY_MANUFACTURING_DATE, API 35. */
        const val PROP_MANUFACTURING_DATE = 10

        /** BatteryManager.BATTERY_PROPERTY_FIRST_USAGE_DATE, API 35. */
        const val PROP_FIRST_USAGE_DATE = 11

        /** BatteryManager.EXTRA_CYCLE_COUNT, API 34. */
        const val EXTRA_CYCLE_COUNT = "android.os.extra.CYCLE_COUNT"

        /** BatteryManager.BATTERY_PLUGGED_DOCK, API 34. */
        const val PLUGGED_DOCK = 8
    }
}
