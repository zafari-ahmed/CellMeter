package com.cellmeter.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.TypedValue
import kotlin.math.cos
import kotlin.math.sin

/**
 * Paints the level and health arcs to bitmaps.
 *
 * A widget cannot host a custom View — RemoteViews only supports a fixed set of
 * framework widgets — so anything drawn has to arrive as a bitmap through
 * `setImageViewBitmap`. The shapes mirror `BatteryGauge` in the Flutter app so
 * the two readouts are recognisably the same control.
 *
 * Bitmaps sent through RemoteViews cross a Binder transaction with a hard size
 * limit, so these are kept small and are only regenerated when the value they
 * draw has actually changed.
 */
object GaugeRenderer {

    /** The open arc leaves a gap at the bottom, as the in-app gauge does. */
    private const val START_ANGLE = 135f
    private const val SWEEP_ANGLE = 270f

    /**
     * The level gauge: an open arc with the reading in the middle, and a tick
     * marking the user's charge limit when one is set.
     */
    fun level(
        context: Context,
        sizeDp: Int,
        levelPct: Double?,
        isCharging: Boolean,
        chargeLimitPct: Int?,
        statusLabel: String?,
    ): Bitmap {
        val size = dpToPx(context, sizeDp)
        val bitmap = createBitmap(size)
        val canvas = Canvas(bitmap)

        val stroke = size * 0.077f
        val inset = stroke / 2f + dpToPx(context, 2).toFloat()
        val rect = RectF(inset, inset, size - inset, size - inset)

        val arcColor = when {
            isCharging -> WidgetPalette.primary
            levelPct != null -> WidgetPalette.forLevel(levelPct)
            else -> WidgetPalette.textMuted
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }

        paint.color = WidgetPalette.track
        canvas.drawArc(rect, START_ANGLE, SWEEP_ANGLE, false, paint)

        val progress = ((levelPct ?: 0.0) / 100.0).coerceIn(0.0, 1.0)
        if (progress > 0) {
            paint.color = arcColor
            canvas.drawArc(
                rect,
                START_ANGLE,
                (SWEEP_ANGLE * progress).toFloat(),
                false,
                paint,
            )
        }

        if (chargeLimitPct != null && chargeLimitPct in 1..99) {
            drawLimitTick(canvas, rect, stroke, chargeLimitPct / 100f)
        }

        drawLevelText(canvas, size, levelPct, statusLabel, arcColor)
        return bitmap
    }

    /**
     * The health ring: a closed circle rather than an open arc, so the two
     * widgets are not mistaken for each other at a glance.
     */
    fun health(
        context: Context,
        sizeDp: Int,
        healthPct: Double?,
    ): Bitmap {
        val size = dpToPx(context, sizeDp)
        val bitmap = createBitmap(size)
        val canvas = Canvas(bitmap)

        val stroke = size * 0.09f
        val inset = stroke / 2f + dpToPx(context, 1).toFloat()
        val rect = RectF(inset, inset, size - inset, size - inset)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }

        paint.color = WidgetPalette.track
        canvas.drawArc(rect, 0f, 360f, false, paint)

        if (healthPct != null && healthPct > 0) {
            paint.color = WidgetPalette.forScore(healthPct)
            canvas.drawArc(
                rect,
                -90f,
                (360.0 * (healthPct / 100.0).coerceIn(0.0, 1.0)).toFloat(),
                false,
                paint,
            )
        }

        val label = healthPct?.let { "${it.toInt()}" } ?: "--"
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WidgetPalette.text
            textAlign = Paint.Align.CENTER
            textSize = size * 0.28f
            isFakeBoldText = true
        }
        canvas.drawText(label, size / 2f, size / 2f + textPaint.textSize * 0.35f, textPaint)

        return bitmap
    }

    private fun drawLimitTick(
        canvas: Canvas,
        rect: RectF,
        stroke: Float,
        fraction: Float,
    ) {
        val angleDeg = START_ANGLE + SWEEP_ANGLE * fraction
        val angleRad = Math.toRadians(angleDeg.toDouble())
        val radius = rect.width() / 2f
        val cx = rect.centerX()
        val cy = rect.centerY()

        val innerRadius = radius - stroke * 0.62f
        val outerRadius = radius + stroke * 0.62f

        canvas.drawLine(
            cx + (cos(angleRad) * innerRadius).toFloat(),
            cy + (sin(angleRad) * innerRadius).toFloat(),
            cx + (cos(angleRad) * outerRadius).toFloat(),
            cy + (sin(angleRad) * outerRadius).toFloat(),
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = WidgetPalette.accent
                strokeWidth = stroke * 0.36f
                strokeCap = Paint.Cap.ROUND
            },
        )
    }

    private fun drawLevelText(
        canvas: Canvas,
        size: Int,
        levelPct: Double?,
        statusLabel: String?,
        arcColor: Int,
    ) {
        val centreX = size / 2f
        val hasStatus = !statusLabel.isNullOrEmpty()

        val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WidgetPalette.text
            textAlign = Paint.Align.CENTER
            textSize = size * 0.26f
            isFakeBoldText = true
        }

        // Nudged up when a status line sits underneath, so the pair reads as
        // centred rather than the number alone.
        val valueBaseline = if (hasStatus) {
            size * 0.50f
        } else {
            size / 2f + valuePaint.textSize * 0.35f
        }

        canvas.drawText(
            levelPct?.let { "${it.toInt()}" } ?: "--",
            centreX,
            valueBaseline,
            valuePaint,
        )

        if (hasStatus) {
            canvas.drawText(
                statusLabel,
                centreX,
                size * 0.655f,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = arcColor
                    textAlign = Paint.Align.CENTER
                    textSize = size * 0.11f
                },
            )
        }
    }

    private fun createBitmap(size: Int): Bitmap =
        Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)

    private fun dpToPx(context: Context, dp: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            context.resources.displayMetrics,
        ).toInt()
}
