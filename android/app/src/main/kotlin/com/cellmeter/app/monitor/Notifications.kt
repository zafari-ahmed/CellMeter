package com.cellmeter.app.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.cellmeter.app.MainActivity
import com.cellmeter.app.R
import com.cellmeter.app.battery.BatterySnapshot
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Every notification CellMeter posts, in one place.
 *
 * Alerts are split across channels so a user can silence the ongoing status
 * line without losing the charge alarm, which is the one notification people
 * actually rely on.
 */
object Notifications {

    const val CHANNEL_STATUS = "cellmeter_status"
    const val CHANNEL_ALERTS = "cellmeter_alerts"
    const val CHANNEL_ALARM = "cellmeter_alarm"

    const val ID_STATUS = 1001
    const val ID_CHARGE_ALARM = 1002
    const val ID_HIGH_DRAIN = 1003
    const val ID_LOW_BATTERY = 1004
    const val ID_TEMPERATURE = 1005

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_STATUS,
                "Battery status",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Ongoing live battery readout. Silent by design."
                setShowBadge(false)
                enableVibration(false)
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                "Battery alerts",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "High drain, low battery and temperature warnings."
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALARM,
                "Charge alarm",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Fires when the battery reaches your charge limit."
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
            }
        )
    }

    /**
     * The persistent notification that keeps the sampler in the foreground.
     * Doubles as the at-a-glance readout, so it carries live numbers when the
     * user has that turned on.
     */
    fun buildStatus(
        context: Context,
        snapshot: BatterySnapshot?,
        detailed: Boolean,
    ): Notification {
        val level = snapshot?.levelPct?.roundToInt()
        val title = when {
            snapshot == null -> "CellMeter is measuring"
            snapshot.isCharging -> "Charging · ${level ?: "--"}%"
            else -> "Battery · ${level ?: "--"}%"
        }

        val body = if (detailed && snapshot != null) statusLine(snapshot) else "Monitoring active"

        return NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_stat_cellmeter)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppIntent(context))
            .build()
    }

    private fun statusLine(s: BatterySnapshot): String {
        val parts = mutableListOf<String>()
        s.currentNowUa?.let { parts += "${abs(it / 1000)} mA" }
        s.temperatureC?.let { parts += "${String.format("%.1f", it)} °C" }
        s.voltageMv?.let { parts += "${String.format("%.2f", it / 1000.0)} V" }
        s.powerMw?.let { parts += "${String.format("%.2f", abs(it) / 1000.0)} W" }
        if (parts.isEmpty()) parts += if (s.isCharging) "Charging" else "Discharging"
        return parts.joinToString(" · ")
    }

    fun postChargeAlarm(context: Context, levelPct: Int, targetPct: Int) {
        val text = "Battery reached $levelPct%. Unplug the charger to limit wear " +
            "(your limit is $targetPct%)."
        post(
            context,
            ID_CHARGE_ALARM,
            NotificationCompat.Builder(context, CHANNEL_ALARM)
                .setSmallIcon(R.drawable.ic_stat_cellmeter)
                .setContentTitle("Charge limit reached · $levelPct%")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(openAppIntent(context))
                .build(),
        )
    }

    fun postHighDrain(context: Context, pctPerHour: Double, suspectApp: String?) {
        val rate = String.format("%.1f", pctPerHour)
        val text = buildString {
            append("Battery is draining at $rate% per hour")
            if (suspectApp != null) append(". Most foreground time: $suspectApp")
            append(".")
        }
        post(
            context,
            ID_HIGH_DRAIN,
            alert(context, "High battery drain", text).build(),
        )
    }

    fun postLowBattery(context: Context, levelPct: Int, estimate: String?) {
        val text = buildString {
            append("Battery at $levelPct%")
            if (estimate != null) append(". About $estimate remaining")
            append(".")
        }
        post(context, ID_LOW_BATTERY, alert(context, "Low battery", text).build())
    }

    fun postTemperature(context: Context, celsius: Double) {
        val text = "Battery is at ${String.format("%.1f", celsius)} °C. " +
            "Sustained heat is the fastest way to wear a cell out."
        post(context, ID_TEMPERATURE, alert(context, "Battery running hot", text).build())
    }

    private fun alert(context: Context, title: String, text: String) =
        NotificationCompat.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_cellmeter)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(context))

    private fun post(context: Context, id: Int, notification: Notification) {
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted. Alerts are opt-in; stay quiet.
        }
    }

    fun cancel(context: Context, id: Int) {
        runCatching { NotificationManagerCompat.from(context).cancel(id) }
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
