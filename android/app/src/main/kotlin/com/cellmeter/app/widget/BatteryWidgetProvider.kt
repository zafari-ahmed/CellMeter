package com.cellmeter.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import com.cellmeter.app.monitor.MonitorService
import com.cellmeter.app.monitor.MonitorSettings

/**
 * The resizable battery widget, 2x1 through 4x2.
 *
 * One provider covering three layouts rather than three providers, so the
 * widget picker shows a single CellMeter entry the user resizes, instead of
 * three near-identical ones they have to choose between before seeing any of
 * them.
 */
class BatteryWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // A direct read, not a wait for the next sampler tick: a widget that
        // sits blank for thirty seconds after being placed looks broken.
        WidgetUpdater.update(context, force = true)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        // The user resized it, so a different layout may now apply.
        WidgetUpdater.update(context, force = true)
    }

    override fun onEnabled(context: Context) {
        // The first widget was placed. It is only worth anything if the
        // sampler is running, and the user may have added it without ever
        // opening the app since a reboot.
        if (MonitorSettings(context).monitoringEnabled) {
            MonitorService.start(context)
        }
    }
}
