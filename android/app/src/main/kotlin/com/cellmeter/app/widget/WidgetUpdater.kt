package com.cellmeter.app.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import com.cellmeter.app.battery.BatteryReader
import com.cellmeter.app.battery.BatterySnapshot
import com.cellmeter.app.monitor.MonitorSettings

/**
 * Pushes fresh content into every placed widget.
 *
 * Android's own `updatePeriodMillis` has a 30-minute floor, which is useless
 * for a live battery readout. CellMeter already runs a sampler service, so the
 * widgets are driven from that instead: whenever a reading changes meaningfully
 * the service calls [update], and the widget is as current as the app is.
 *
 * The periodic update declared in the provider XML remains as a safety net for
 * the case where the service has been killed and not yet restarted.
 */
object WidgetUpdater {

    private const val TAG = "CellMeter/Widget"

    /**
     * Minimum spacing between pushes.
     *
     * Each update crosses a Binder transaction carrying a freshly rendered
     * bitmap, so pushing on every single sample while charging would be real
     * work for no visible gain — the numbers do not move fast enough to tell.
     */
    private const val MIN_INTERVAL_MS = 5_000L

    @Volatile
    private var lastUpdateMs = 0L

    /**
     * Updates every widget from [snapshot].
     *
     * [force] bypasses the rate limit, for the cases where a push is a
     * response to something rather than a tick: the widget was just placed,
     * the app changed a setting, or Flutter recomputed health.
     */
    fun update(
        context: Context,
        snapshot: BatterySnapshot? = null,
        force: Boolean = false,
    ) {
        val now = System.currentTimeMillis()
        if (!force && now - lastUpdateMs < MIN_INTERVAL_MS) return

        val manager = AppWidgetManager.getInstance(context) ?: return
        val batteryIds = idsFor(context, manager, BatteryWidgetProvider::class.java)
        val healthIds = idsFor(context, manager, HealthWidgetProvider::class.java)
        if (batteryIds.isEmpty() && healthIds.isEmpty()) return

        lastUpdateMs = now

        // Only read the battery if a widget is actually placed and the caller
        // did not already have a reading in hand.
        val reading = snapshot ?: runCatching { BatteryReader(context).read() }.getOrNull()
        val store = WidgetDataStore(context)
        val settings = MonitorSettings(context)

        for (id in batteryIds) {
            try {
                val size = WidgetRenderer.sizeFor(manager.getAppWidgetOptions(id))
                manager.updateAppWidget(
                    id,
                    WidgetRenderer.battery(context, size, reading, store, settings),
                )
            } catch (t: Throwable) {
                Log.w(TAG, "Battery widget $id failed to update", t)
            }
        }

        for (id in healthIds) {
            try {
                manager.updateAppWidget(id, WidgetRenderer.health(context, store))
            } catch (t: Throwable) {
                Log.w(TAG, "Health widget $id failed to update", t)
            }
        }
    }

    /** True when at least one widget is on a home screen. */
    fun hasPlacedWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context) ?: return false
        return idsFor(context, manager, BatteryWidgetProvider::class.java).isNotEmpty() ||
            idsFor(context, manager, HealthWidgetProvider::class.java).isNotEmpty()
    }

    private fun idsFor(
        context: Context,
        manager: AppWidgetManager,
        provider: Class<*>,
    ): IntArray = try {
        manager.getAppWidgetIds(ComponentName(context, provider))
    } catch (_: Throwable) {
        IntArray(0)
    }
}
