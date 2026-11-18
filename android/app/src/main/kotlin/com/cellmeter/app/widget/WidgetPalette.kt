package com.cellmeter.app.widget

import android.graphics.Color

/**
 * The widget palette, as literal values.
 *
 * Deliberately not read from the app's theme and deliberately not opted into
 * Material You wallpaper tinting. Colour carries meaning here — green is
 * healthy or charging, yellow is the user's charge limit, the ramp drives
 * temperature — and a widget recoloured to someone's wallpaper would stay
 * legible while ceasing to mean anything. A glance at the widget has to mean
 * the same thing as a glance at the app.
 */
object WidgetPalette {
    val surface = Color.parseColor("#18263E")
    val track = Color.parseColor("#2A3B5C")

    val primary = Color.parseColor("#39E75F")
    val accent = Color.parseColor("#FFC928")
    val info = Color.parseColor("#3DAEFF")

    val text = Color.parseColor("#EDF2F9")
    val textMuted = Color.parseColor("#94A7C4")

    private val good = Color.parseColor("#9CE640")
    private val fair = Color.parseColor("#FFC928")
    private val poor = Color.parseColor("#FF8A3D")
    private val critical = Color.parseColor("#FF4D4D")

    /** Mirrors `AppColors.forLevel` on the Dart side. */
    fun forLevel(levelPct: Double): Int = when {
        levelPct >= 60 -> primary
        levelPct >= 35 -> good
        levelPct >= 20 -> fair
        levelPct >= 10 -> poor
        else -> critical
    }

    /** Mirrors `AppColors.forScore`: higher is better. */
    fun forScore(score: Double): Int = when {
        score >= 85 -> primary
        score >= 70 -> good
        score >= 55 -> fair
        score >= 40 -> poor
        else -> critical
    }
}
