package com.cellmeter.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import com.cellmeter.app.MainActivity
import com.cellmeter.app.R
import com.cellmeter.app.battery.BatterySnapshot
import com.cellmeter.app.monitor.MonitorSettings
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Builds the RemoteViews for every widget size.
 *
 * All four layouts are filled from the same [BatterySnapshot] plus whatever
 * Flutter last pushed into [WidgetDataStore], so a widget can never disagree
 * with the app about the same moment.
 */
object WidgetRenderer {

    /** Which battery layout a given cell size gets. */
    enum class Size(val layout: Int) {
        COMPACT(R.layout.widget_battery_compact),
        ROW(R.layout.widget_battery_row),
        FULL(R.layout.widget_battery_full),
    }

    /**
     * Picks a layout from the space the launcher actually gave the widget.
     *
     * Thresholds are in the launcher's own dp units, where a cell is
     * `70 * n - 30`: 250dp is four columns, 110dp is two rows.
     */
    fun sizeFor(options: Bundle?): Size {
        val width = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0

        return when {
            width >= 250 && height >= 110 -> Size.FULL
            width >= 250 -> Size.ROW
            else -> Size.COMPACT
        }
    }

    fun battery(
        context: Context,
        size: Size,
        snapshot: BatterySnapshot?,
        store: WidgetDataStore,
        settings: MonitorSettings,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, size.layout)
        val level = snapshot?.levelPct
        val charging = snapshot?.isCharging == true
        val limit = chargeLimit(settings)

        views.setTextViewText(R.id.widget_level, level?.roundToInt()?.toString() ?: "--")
        views.setTextViewText(R.id.widget_current, currentLabel(snapshot))
        views.setTextColor(
            R.id.widget_current,
            if (charging) WidgetPalette.primary else WidgetPalette.info,
        )

        // The ring is the app's signature element, so the widget reads as
        // CellMeter rather than as a generic card of numbers. On the small
        // sizes it sits beside a large figure and carries no text of its own:
        // a value inside a 34dp ring would be six points tall.
        views.setImageViewBitmap(
            R.id.widget_gauge,
            GaugeRenderer.level(
                context = context,
                sizeDp = gaugeSizeDp(size),
                levelPct = level,
                isCharging = charging,
                chargeLimitPct = limit,
                statusLabel = if (size == Size.FULL) statusLabel(snapshot) else null,
                showValue = size == Size.FULL,
            ),
        )

        if (size != Size.COMPACT) {
            views.setTextViewText(R.id.widget_temperature, temperatureLabel(snapshot, store))
            applyForecast(views, store, settings, charging, level)
        }

        if (size == Size.ROW) {
            views.setTextViewText(R.id.widget_status, statusLabel(snapshot) ?: "")
            views.setTextColor(
                R.id.widget_status,
                if (charging) WidgetPalette.primary else WidgetPalette.textMuted,
            )
        }

        if (size == Size.FULL) {
            views.setTextViewText(R.id.widget_health, healthLabel(store))
            views.setImageViewBitmap(
                R.id.widget_sparkline,
                WidgetArt.sparkline(
                    context = context,
                    widthDp = 218,
                    heightDp = 30,
                    points = WidgetHistory(context).read(),
                ),
            )
        }

        views.setOnClickPendingIntent(android.R.id.background, openApp(context))
        return views
    }

    /** Ring diameter per layout. */
    private fun gaugeSizeDp(size: Size): Int = when (size) {
        Size.COMPACT -> 44
        Size.ROW -> 40
        Size.FULL -> 68
    }

    fun health(context: Context, store: WidgetDataStore): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_health)
        val health = store.healthPct
        val measured = store.measuredMah
        val design = store.designMah

        views.setImageViewBitmap(
            R.id.widget_gauge,
            GaugeRenderer.health(context, sizeDp = 74, healthPct = health),
        )

        // Before the first measurement the widget says what it is waiting for
        // rather than repeating that it has nothing. "Measuring" with no
        // instruction leaves the user unable to help it along, and capacity
        // is only measured during a reasonably deep charge.
        if (measured == null) {
            views.setTextViewText(R.id.widget_capacity, "Measuring")
            views.setTextColor(R.id.widget_capacity, WidgetPalette.textMuted)
            views.setTextViewText(R.id.widget_design, "Charge 20% in one go")
        } else {
            views.setTextViewText(
                R.id.widget_capacity,
                "${formatThousands(measured)} mAh",
            )
            views.setTextColor(R.id.widget_capacity, WidgetPalette.text)
            views.setTextViewText(
                R.id.widget_design,
                if (design != null) "of ${formatThousands(design)} when new" else "measured",
            )
        }

        views.setOnClickPendingIntent(android.R.id.background, openApp(context))
        return views
    }

    // ------------------------------------------------------------- labels

    private fun currentLabel(snapshot: BatterySnapshot?): String {
        val microAmps = snapshot?.currentNowUa ?: return "—"
        val milliAmps = (microAmps / 1000.0).roundToInt()
        val sign = if (milliAmps > 0) "+" else ""
        return "$sign${formatThousands(milliAmps)} mA"
    }

    private fun temperatureLabel(
        snapshot: BatterySnapshot?,
        store: WidgetDataStore,
    ): String {
        val celsius = snapshot?.temperatureC ?: return "—"
        return if (store.useFahrenheit) {
            String.format("%.1f °F", celsius * 9 / 5 + 32)
        } else {
            String.format("%.1f °C", celsius)
        }
    }

    private fun healthLabel(store: WidgetDataStore): String {
        val health = store.healthPct ?: return "Health — still measuring"
        val measured = store.measuredMah
        return if (measured != null) {
            "Health ${health.roundToInt()}% · ${formatThousands(measured)} mAh"
        } else {
            "Health ${health.roundToInt()}%"
        }
    }

    private fun statusLabel(snapshot: BatterySnapshot?): String? = when {
        snapshot == null -> null
        snapshot.isCharging -> "Charging"
        snapshot.screenOn -> "In use"
        else -> "Standby"
    }

    /**
     * Fills the time-remaining readout.
     *
     * While charging toward a limit the user set, this counts down to that
     * limit rather than to 100%. A widget sitting next to the setting that
     * says "stop at 80%" should not be answering a question the user
     * deliberately stopped asking.
     *
     * The target is folded into the text itself ("43m to 80%") rather than
     * carried by a separate label, because at widget size a column heading
     * costs more room than it earns.
     */
    private fun applyForecast(
        views: RemoteViews,
        store: WidgetDataStore,
        settings: MonitorSettings,
        charging: Boolean,
        levelPct: Double?,
    ) {
        val minutes = store.forecastMinutes
        val limit = chargeLimit(settings)

        views.setTextColor(
            R.id.widget_forecast,
            if (charging) WidgetPalette.accent else WidgetPalette.textMuted,
        )

        // A forecast is only valid for the direction it was computed in. If
        // the phone has been plugged in since Flutter last pushed, showing the
        // old discharge estimate would be worse than showing nothing.
        if (minutes == null || store.forecastIsCharging != charging) {
            views.setTextViewText(R.id.widget_forecast, "—")
            return
        }

        val duration = formatDuration(minutes)
        val text = when {
            charging && limit != null && (levelPct ?: 0.0) < limit ->
                "$duration to $limit%"
            charging -> "$duration to full"
            else -> "$duration left"
        }
        views.setTextViewText(R.id.widget_forecast, text)
    }

    private fun chargeLimit(settings: MonitorSettings): Int? =
        settings.chargeAlarmPct.takeIf { settings.chargeAlarmEnabled && it in 1..99 }

    // ----------------------------------------------------------- formatting

    private fun formatDuration(minutes: Int): String {
        if (minutes < 1) return "<1 min"
        val hours = minutes / 60
        val remainder = minutes % 60
        return when {
            hours >= 48 -> "${hours / 24}d"
            hours > 0 -> "${hours}h ${remainder}m"
            else -> "${remainder} min"
        }
    }

    private fun formatThousands(value: Int): String {
        val negative = value < 0
        val digits = abs(value).toString().reversed().chunked(3).joinToString(",").reversed()
        return if (negative) "-$digits" else digits
    }

    private fun openApp(context: Context): PendingIntent {
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
