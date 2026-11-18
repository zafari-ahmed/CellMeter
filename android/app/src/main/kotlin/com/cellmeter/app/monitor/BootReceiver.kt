package com.cellmeter.app.monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Brings the sampler back after a reboot or an app update.
 *
 * Without this, every reboot would open a hole in the record and any charge
 * session spanning it would be unusable for capacity measurement.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        if (!MonitorSettings(context).monitoringEnabled) return

        Log.i("CellMeter/Boot", "Restarting sampler after $action")
        MonitorService.start(context)
    }
}
