package com.cellmeter.app.widget

import android.content.Context

/**
 * A short ring buffer of recent battery levels, for the widget's sparkline.
 *
 * The sparkline is the one thing a CellMeter widget can show that a stock
 * battery widget cannot: the shape of the last few hours, so a user sees at a
 * glance whether the battery is falling off a cliff or coasting. It only
 * exists because the sampler is already running.
 *
 * Kept natively, in preferences, rather than read from the database: the
 * widget has to redraw long after the Dart engine is gone, and going through
 * Flutter for a handful of numbers the service already has in hand would make
 * the sparkline freeze exactly when the app is closed — which is when a widget
 * matters.
 *
 * Stored as a compact string rather than as structured data because it is
 * rewritten on every sample and a few dozen points never justify a table.
 */
class WidgetHistory(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    data class Point(val timestampMs: Long, val levelPct: Double, val charging: Boolean)

    /**
     * Records a reading, keeping at most [MAX_POINTS].
     *
     * A point is kept when the level or charging state changes, and otherwise
     * at most once per [MIN_SPACING_MS] so a flat battery does not fill the
     * buffer with identical values.
     *
     * The obvious version of this — "if it is too soon, overwrite the last
     * point instead" — is wrong, and was the first implementation: overwriting
     * also moves the last point's timestamp to now, so the spacing clock
     * restarts on every sample and the buffer can never reach two points. The
     * sampler runs every ten seconds while charging, so it never did.
     */
    fun append(timestampMs: Long, levelPct: Double?, charging: Boolean) {
        if (levelPct == null) return

        val points = read().toMutableList()
        val last = points.lastOrNull()

        if (last != null) {
            val unchanged = last.levelPct == levelPct && last.charging == charging
            if (unchanged && timestampMs - last.timestampMs < MIN_SPACING_MS) return
        }

        points.add(Point(timestampMs, levelPct, charging))
        while (points.size > MAX_POINTS) points.removeAt(0)
        write(points)
    }

    /** Points oldest first, with anything older than [WINDOW_MS] dropped. */
    fun read(): List<Point> {
        val raw = prefs.getString(KEY_POINTS, null) ?: return emptyList()
        val cutoff = System.currentTimeMillis() - WINDOW_MS

        return raw.split(';')
            .mapNotNull { entry ->
                val parts = entry.split(',')
                if (parts.size != 3) return@mapNotNull null
                val timestamp = parts[0].toLongOrNull() ?: return@mapNotNull null
                val level = parts[1].toDoubleOrNull() ?: return@mapNotNull null
                if (timestamp < cutoff) return@mapNotNull null
                Point(timestamp, level, parts[2] == "1")
            }
    }

    fun clear() = prefs.edit().remove(KEY_POINTS).apply()

    private fun write(points: List<Point>) {
        val encoded = points.joinToString(";") {
            "${it.timestampMs},${it.levelPct},${if (it.charging) 1 else 0}"
        }
        prefs.edit().putString(KEY_POINTS, encoded).apply()
    }

    private companion object {
        const val PREFS = "cellmeter_widget_history"
        const val KEY_POINTS = "points"

        /** Enough resolution to show a shape, small enough to rewrite often. */
        const val MAX_POINTS = 64

        /** How far back the sparkline reaches. */
        const val WINDOW_MS = 6 * 60 * 60 * 1000L

        /** 6h over 64 points is roughly one point every five minutes. */
        const val MIN_SPACING_MS = 5 * 60 * 1000L
    }
}
