package com.cellmeter.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

/**
 * The 2x2 health widget.
 *
 * Reads only from [WidgetDataStore], which Flutter keeps up to date. Measured
 * capacity changes over months, so there is nothing here that needs a live
 * battery reading.
 */
class HealthWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val store = WidgetDataStore(context)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, WidgetRenderer.health(context, store))
        }
    }
}
