package com.cellmeter.app.monitor

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.Log
import com.cellmeter.app.battery.BatteryReader
import com.cellmeter.app.battery.BatterySnapshot
import com.cellmeter.app.widget.WidgetUpdater
import kotlin.math.abs

/**
 * The sampler. Everything CellMeter knows about a battery starts here.
 *
 * Runs as a foreground service for one reason: a capacity measurement is a
 * difference between two coulomb-counter readings taken tens of minutes apart,
 * and a gap in the middle invalidates the whole session. Background execution
 * limits would otherwise drop the samples exactly when they matter — during a
 * long screen-off charge — which is the single most common complaint about
 * apps in this category.
 *
 * Two trigger sources are combined:
 *  - [Intent.ACTION_BATTERY_CHANGED], which the system sends on every whole
 *    percent change and on plug events. Free, and catches level transitions
 *    precisely.
 *  - A timed tick on a background [HandlerThread], because current, voltage and
 *    temperature move continuously and the broadcast can be minutes apart at
 *    low drain. The interval adapts to what is happening ([intervalMs]).
 *
 * Samples are appended to [SampleSink]; nothing here touches the database.
 */
class MonitorService : Service() {

    private lateinit var reader: BatteryReader
    private lateinit var sink: SampleSink
    private lateinit var settings: MonitorSettings
    private lateinit var alerts: AlertEvaluator

    private var thread: HandlerThread? = null
    private var handler: Handler? = null

    @Volatile
    private var lastSnapshot: BatterySnapshot? = null

    @Volatile
    private var lastNotificationUpdateMs = 0L

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // A level or plug change is exactly the moment a sample is worth
            // the most, so take one immediately rather than waiting for a tick.
            handler?.post { sampleOnce(force = true) }
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // The screen-on/off boundary splits drain attribution, so both
            // sides of it need a sample.
            handler?.post { sampleOnce(force = true) }
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            sampleOnce(force = false)
            handler?.postDelayed(this, intervalMs())
        }
    }

    override fun onCreate() {
        super.onCreate()
        reader = BatteryReader(this)
        sink = SampleSink(this)
        settings = MonitorSettings(this)
        alerts = AlertEvaluator(this, settings)

        Notifications.ensureChannels(this)
        startForegroundCompat(Notifications.buildStatus(this, null, false))

        thread = HandlerThread("cellmeter-sampler").also { it.start() }
        handler = Handler(thread!!.looper)

        registerReceivers()
        handler?.post(tick)
        Log.i(TAG, "Sampler started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SAMPLE_NOW -> handler?.post { sampleOnce(force = true) }
        }
        // START_STICKY so the system brings the sampler back after a low-memory
        // kill. Losing samples is the one failure this app cannot absorb.
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(batteryReceiver) }
        runCatching { unregisterReceiver(screenReceiver) }
        handler?.removeCallbacksAndMessages(null)
        thread?.quitSafely()
        thread = null
        handler = null
        Log.i(TAG, "Sampler stopped")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app away must not stop monitoring; that is the whole
        // point of the service. Ask to be restarted if the system takes us.
        super.onTaskRemoved(rootIntent)
    }

    // ------------------------------------------------------------- sampling

    private fun sampleOnce(force: Boolean) {
        if (!settings.monitoringEnabled) return
        try {
            val snapshot = reader.read()
            val previous = lastSnapshot

            if (!force && previous != null && isRedundant(previous, snapshot)) {
                // Nothing moved. Skip the write so idle screen-off hours do not
                // fill the spool with identical rows.
                updateStatusNotification(snapshot)
                return
            }

            sink.append(snapshot)
            lastSnapshot = snapshot
            alerts.evaluate(snapshot, previous)
            updateStatusNotification(snapshot)

            // Home screen widgets are driven from here rather than from
            // Android's own widget refresh, whose 30-minute floor is useless
            // for a live readout. WidgetUpdater returns immediately when no
            // widget is placed, and rate-limits itself when one is.
            WidgetUpdater.update(this, snapshot, force = force)
        } catch (t: Throwable) {
            Log.w(TAG, "Sample failed", t)
        }
    }

    /**
     * A sample earns its place only if something measurable changed. Level and
     * charging state always count; current, voltage and temperature need to
     * move past a small threshold so sensor jitter does not defeat the check.
     */
    private fun isRedundant(a: BatterySnapshot, b: BatterySnapshot): Boolean {
        if (a.status != b.status || a.plugType != b.plugType) return false
        if (a.screenOn != b.screenOn) return false
        if (a.levelPct != b.levelPct) return false
        if (a.powerSaveMode != b.powerSaveMode) return false

        val currentMoved = diff(a.currentNowUa, b.currentNowUa) > 30_000      // 30 mA
        val voltageMoved = diff(a.voltageMv?.toLong(), b.voltageMv?.toLong()) > 20 // 20 mV
        val tempMoved = abs((a.temperatureC ?: 0.0) - (b.temperatureC ?: 0.0)) > 0.5
        val chargeMoved = diff(a.chargeCounterUah, b.chargeCounterUah) > 5_000 // 5 mAh

        if (currentMoved || voltageMoved || tempMoved || chargeMoved) return false

        // Even when nothing moves, keep a heartbeat so gaps in the record mean
        // "the sampler was dead", not "nothing happened".
        return (b.timestampMs - a.timestampMs) < HEARTBEAT_MS
    }

    private fun diff(a: Long?, b: Long?): Long {
        if (a == null || b == null) return Long.MAX_VALUE
        return abs(a - b)
    }

    /**
     * Sampling cadence, chosen for the situation rather than fixed:
     *  - charging moves fast and is when capacity is measured, so sample often
     *  - screen-on discharge varies with what the user is doing
     *  - screen-off discharge is slow and flat, and this is where a tight loop
     *    would itself become a meaningful drain
     */
    private fun intervalMs(): Long {
        val s = lastSnapshot ?: return INTERVAL_ACTIVE_MS
        return when {
            s.isCharging -> INTERVAL_CHARGING_MS
            s.screenOn -> INTERVAL_ACTIVE_MS
            else -> INTERVAL_IDLE_MS
        }
    }

    private fun updateStatusNotification(snapshot: BatterySnapshot) {
        val now = System.currentTimeMillis()
        if (now - lastNotificationUpdateMs < NOTIFICATION_MIN_INTERVAL_MS) return
        lastNotificationUpdateMs = now
        runCatching {
            val notification = Notifications.buildStatus(
                this,
                snapshot,
                settings.showStatsInNotification,
            )
            startForegroundCompat(notification)
        }
    }

    // -------------------------------------------------------------- plumbing

    private fun registerReceivers() {
        runCatching {
            registerReceiver(
                batteryReceiver,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
        }
        runCatching {
            registerReceiver(
                screenReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_SCREEN_OFF)
                },
            )
        }
    }

    private fun startForegroundCompat(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                Notifications.ID_STATUS,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(Notifications.ID_STATUS, notification)
        }
    }

    companion object {
        private const val TAG = "CellMeter/Service"

        const val ACTION_STOP = "com.cellmeter.app.STOP_MONITOR"
        const val ACTION_SAMPLE_NOW = "com.cellmeter.app.SAMPLE_NOW"

        private const val INTERVAL_CHARGING_MS = 10_000L
        private const val INTERVAL_ACTIVE_MS = 30_000L
        private const val INTERVAL_IDLE_MS = 120_000L

        /** Write a sample at least this often, even if nothing changed. */
        private const val HEARTBEAT_MS = 10 * 60_000L

        private const val NOTIFICATION_MIN_INTERVAL_MS = 5_000L

        fun start(context: Context) {
            val intent = Intent(context, MonitorService::class.java)
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, MonitorService::class.java).setAction(ACTION_STOP)
                )
            }
            runCatching { context.stopService(Intent(context, MonitorService::class.java)) }
        }

        fun sampleNow(context: Context) {
            runCatching {
                val intent = Intent(context, MonitorService::class.java)
                    .setAction(ACTION_SAMPLE_NOW)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }
    }
}
