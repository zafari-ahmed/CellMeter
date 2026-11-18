package com.cellmeter.app.monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Plug and unplug are the boundaries of a charge session, so they are the two
 * moments where a missing sample costs the most. This receiver makes sure one
 * is taken right at the transition even if the sampler was just killed and the
 * timed tick has not come round yet.
 */
class PowerEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!MonitorSettings(context).monitoringEnabled) return
        MonitorService.sampleNow(context)
    }
}
