package com.cellmeter.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The in-app "add to home screen" path.
 *
 * Android never lets an app place a widget by itself. What
 * `requestPinAppWidget` does is ask the launcher to show a *system* dialog
 * with a preview and an add button — the user still decides, in one tap
 * instead of five.
 *
 * Not every launcher implements pinning. Where it is unsupported,
 * [canPin] returns false and the app falls back to telling the user how to add
 * it from the widget picker, which always works.
 */
object WidgetPinner {

    enum class Kind { BATTERY, HEALTH }

    fun canPin(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            AppWidgetManager.getInstance(context)?.isRequestPinAppWidgetSupported == true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Shows the system add-widget dialog. Returns false when the request could
     * not even be made, so the caller can show the manual instructions
     * instead. A `true` means the dialog was shown, not that the user accepted
     * it — only the launcher knows that, and it tells us by calling the
     * provider's `onUpdate` if they do.
     */
    fun requestPin(context: Context, kind: Kind): Boolean {
        if (!canPin(context)) return false

        val provider = when (kind) {
            Kind.BATTERY -> BatteryWidgetProvider::class.java
            Kind.HEALTH -> HealthWidgetProvider::class.java
        }

        return try {
            val manager = AppWidgetManager.getInstance(context) ?: return false
            manager.requestPinAppWidget(
                ComponentName(context, provider),
                null,
                successCallback(context),
            )
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Fired by the launcher once the widget is actually placed, so the first
     * thing the user sees on their home screen is real data rather than the
     * placeholder layout.
     */
    private fun successCallback(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, WidgetPinnedReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
