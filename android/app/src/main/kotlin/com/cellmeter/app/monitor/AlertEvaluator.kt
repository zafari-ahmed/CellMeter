package com.cellmeter.app.monitor

import android.content.Context
import com.cellmeter.app.battery.BatterySnapshot
import kotlin.math.roundToInt

/**
 * Decides when an alert is worth interrupting the user.
 *
 * Lives on the native side so alerts still fire with no Flutter engine running,
 * which is almost always the case while a phone charges overnight.
 *
 * Each rule is debounced by state rather than by a timer: an alert fires on the
 * transition into its condition and re-arms only once the condition clears.
 * That keeps a battery hovering on the threshold from producing a stream of
 * identical notifications.
 */
class AlertEvaluator(
    context: Context,
    private val settings: MonitorSettings,
) {
    private val appContext = context.applicationContext

    private var chargeAlarmArmed = true
    private var lowBatteryArmed = true
    private var temperatureArmed = true
    private var drainAlertArmed = true

    /** Start of the current run of above-threshold drain, or 0 when not in one. */
    private var drainRunStartMs = 0L
    private var drainRunStartLevel = 0.0

    fun evaluate(current: BatterySnapshot, previous: BatterySnapshot?) {
        evaluateChargeAlarm(current)
        evaluateLowBattery(current)
        evaluateTemperature(current)
        evaluateDrain(current)
    }

    // ---------------------------------------------------------- charge alarm

    /**
     * Fires once when a charging battery first reaches the user's limit.
     * Re-arms on unplug, so the next charge session gets its own alarm.
     */
    private fun evaluateChargeAlarm(s: BatterySnapshot) {
        val level = s.levelPct ?: return
        val target = settings.chargeAlarmPct

        if (!s.isCharging) {
            chargeAlarmArmed = true
            Notifications.cancel(appContext, Notifications.ID_CHARGE_ALARM)
            return
        }
        if (!settings.chargeAlarmEnabled || target <= 0) return

        if (chargeAlarmArmed && level >= target) {
            chargeAlarmArmed = false
            Notifications.postChargeAlarm(appContext, level.roundToInt(), target)
        }
    }

    // ----------------------------------------------------------- low battery

    private fun evaluateLowBattery(s: BatterySnapshot) {
        val level = s.levelPct ?: return
        val threshold = settings.lowBatteryPct

        if (s.isCharging || level > threshold + REARM_MARGIN_PCT) {
            lowBatteryArmed = true
            return
        }
        if (!settings.lowBatteryEnabled || threshold <= 0) return

        if (lowBatteryArmed && level <= threshold) {
            lowBatteryArmed = false
            Notifications.postLowBattery(appContext, level.roundToInt(), estimateRemaining(s))
        }
    }

    /**
     * A rough time-to-empty from the instantaneous current, used only in the
     * low-battery notification. The app's own screens use the far better
     * estimate computed from session history on the Dart side.
     */
    private fun estimateRemaining(s: BatterySnapshot): String? {
        val uah = s.chargeCounterUah ?: return null
        val ua = s.currentNowUa ?: return null
        if (ua >= 0) return null
        val hours = uah.toDouble() / (-ua).toDouble()
        if (hours <= 0 || hours > 400) return null
        val totalMinutes = (hours * 60).roundToInt()
        val h = totalMinutes / 60
        val m = totalMinutes % 60
        return if (h > 0) "${h}h ${m}m" else "${m}m"
    }

    // ----------------------------------------------------------- temperature

    private fun evaluateTemperature(s: BatterySnapshot) {
        val temp = s.temperatureC ?: return
        val threshold = settings.temperatureAlertC

        if (temp < threshold - REARM_MARGIN_C) {
            temperatureArmed = true
            return
        }
        if (!settings.temperatureAlertEnabled) return

        if (temperatureArmed && temp >= threshold) {
            temperatureArmed = false
            Notifications.postTemperature(appContext, temp)
        }
    }

    // ----------------------------------------------------------- high drain

    /**
     * The drain alert deliberately measures over a window instead of reacting
     * to an instantaneous current reading. A camera shutter or a map redraw can
     * pull 2 A for a second; that is not a problem worth a notification. What
     * matters is a rate the battery sustains, so the rule only fires after the
     * level has actually fallen fast enough for long enough.
     */
    private fun evaluateDrain(s: BatterySnapshot) {
        val level = s.levelPct

        if (s.isCharging || level == null) {
            resetDrainRun()
            return
        }
        if (!settings.highDrainEnabled) return

        val now = s.timestampMs

        if (drainRunStartMs == 0L) {
            drainRunStartMs = now
            drainRunStartLevel = level
            return
        }

        val elapsedMs = now - drainRunStartMs
        val elapsedHours = elapsedMs / 3_600_000.0
        if (elapsedHours <= 0) return

        val dropped = drainRunStartLevel - level
        if (dropped < 0) {
            // Level went up without a charging flag (gauge recalibration).
            resetDrainRun()
            return
        }

        val ratePctPerHour = dropped / elapsedHours
        val threshold = settings.highDrainPctPerHour
        val sustainMs = settings.highDrainSustainMinutes * 60_000L

        when {
            // Window long enough and the rate held: alert, then stand down
            // until the drain drops back under the threshold.
            elapsedMs >= sustainMs && ratePctPerHour >= threshold -> {
                if (drainAlertArmed) {
                    drainAlertArmed = false
                    Notifications.postHighDrain(appContext, ratePctPerHour, null)
                }
                resetDrainRun()
            }
            // Window long enough but the rate is fine: re-arm and start over.
            elapsedMs >= sustainMs -> {
                drainAlertArmed = true
                resetDrainRun()
            }
        }
    }

    private fun resetDrainRun() {
        drainRunStartMs = 0L
        drainRunStartLevel = 0.0
    }

    private companion object {
        /** Hysteresis so a battery sitting on the threshold alerts only once. */
        const val REARM_MARGIN_PCT = 3
        const val REARM_MARGIN_C = 2.0
    }
}
