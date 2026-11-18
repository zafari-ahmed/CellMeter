package com.cellmeter.app.battery

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log

/**
 * Resolves the battery's design (factory) capacity in mAh.
 *
 * Android has never offered a public API for this, so three sources are tried
 * in descending order of trust:
 *
 *  1. `charge_full_design` from sysfs — the gauge's own factory value. Exact
 *     when readable, which on modern devices it usually is not.
 *  2. `com.android.internal.os.PowerProfile#getBatteryCapacity()` via
 *     reflection — the value the OEM compiled into `power_profile.xml`, which
 *     is what the system itself uses for its own battery estimates. Available
 *     on the large majority of devices and accurate to the spec sheet.
 *  3. A user-entered value, stored by the app, for devices where neither works
 *     or where the battery has been replaced with a different cell.
 *
 * The result is cached for the process lifetime; these values never change
 * while the app is running.
 */
object DesignCapacity {

    private const val TAG = "CellMeter/DesignCap"
    private const val POWER_PROFILE_CLASS = "com.android.internal.os.PowerProfile"

    /** Where a user-supplied override is kept. Mirrored into Flutter settings. */
    private const val PREFS = "cellmeter_native"
    private const val KEY_OVERRIDE = "design_capacity_override_mah"

    @Volatile
    private var cached: Result? = null

    data class Result(
        val mah: Int?,
        /** "sysfs", "powerProfile", "userOverride" or "unknown". */
        val source: String,
    ) {
        fun toMap(): Map<String, Any?> = mapOf("mah" to mah, "source" to source)
    }

    fun resolve(context: Context): Result {
        cached?.let { return it }
        val result = compute(context)
        cached = result
        return result
    }

    fun setOverride(context: Context, mah: Int?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            if (mah == null) remove(KEY_OVERRIDE) else putInt(KEY_OVERRIDE, mah)
        }.apply()
        cached = null
    }

    private fun compute(context: Context): Result {
        readOverride(context)?.let { return Result(it, "userOverride") }
        SysfsBattery.chargeFullDesignMah()?.let { return Result(it, "sysfs") }
        readPowerProfile(context)?.let { return Result(it, "powerProfile") }
        return Result(null, "unknown")
    }

    private fun readOverride(context: Context): Int? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val value = prefs.getInt(KEY_OVERRIDE, -1)
        return if (value in 300..30_000) value else null
    }

    /**
     * Instantiates the hidden PowerProfile and asks it for the battery
     * capacity. Guarded in every direction: the class may be absent, the
     * constructor signature differs across releases, and on API 28+ the call
     * may be blocked by the hidden-API denylist.
     */
    @SuppressLint("PrivateApi")
    private fun readPowerProfile(context: Context): Int? = try {
        val clazz = Class.forName(POWER_PROFILE_CLASS)
        val instance = clazz
            .getConstructor(Context::class.java)
            .newInstance(context)
        val capacity = clazz
            .getMethod("getBatteryCapacity")
            .invoke(instance) as? Double
        val mah = capacity?.toInt()
        if (mah != null && mah in 300..30_000) mah else null
    } catch (t: Throwable) {
        Log.d(TAG, "PowerProfile unavailable: ${t.javaClass.simpleName}")
        null
    }
}
