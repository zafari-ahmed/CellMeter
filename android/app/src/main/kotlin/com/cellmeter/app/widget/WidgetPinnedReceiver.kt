package com.cellmeter.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.cellmeter.app.monitor.MonitorService
import com.cellmeter.app.monitor.MonitorSettings

/**
 * Runs the moment a pinned widget lands on the home screen, so it is populated
 * immediately rather than on the next sampler tick.
 */
class WidgetPinnedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (MonitorSettings(context).monitoringEnabled) {
            MonitorService.start(context)
        }
        WidgetUpdater.update(context, force = true)
    }
}
