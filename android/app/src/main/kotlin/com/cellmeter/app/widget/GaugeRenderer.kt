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
        showValue: Boolean = true,
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

        // On the small sizes the arc is an indicator beside a large number,
        // not a dial with a number in it: at 32dp the text would be six
        // points tall and unreadable.
        if (showValue) drawLevelText(canvas, size, levelPct, statusLabel, arcColor)
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

/**
 * The widget's distinctive elements: a battery silhouette that fills, and a
 * sparkline of the last few hours.
 *
 * Both are bitmaps for the same reason the gauges are — RemoteViews cannot
 * host a custom View — and both are kept in one place so the widget and the
 * app stay visually related.
 */
object WidgetArt {

    /**
     * A horizontal battery silhouette filled to [levelPct].
     *
     * A recognisable battery shape rather than a plain progress bar: at a
     * glance on a home screen full of other widgets, the outline is what makes
     * this one legible as a battery before any text is read.
     */
    fun batteryBar(
        context: android.content.Context,
        widthDp: Int,
        heightDp: Int,
        levelPct: Double?,
        isCharging: Boolean,
        chargeLimitPct: Int? = null,
    ): android.graphics.Bitmap {
        val width = dp(context, widthDp)
        val height = dp(context, heightDp)
        val bitmap = android.graphics.Bitmap.createBitmap(
            width,
            height,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = android.graphics.Canvas(bitmap)

        // The cap on the right-hand end, as on a battery icon.
        val capWidth = height * 0.22f
        val capHeight = height * 0.42f
        val bodyWidth = width - capWidth - dp(context, 2)
        val radius = height * 0.3f

        val bodyRect = android.graphics.RectF(0f, 0f, bodyWidth, height.toFloat())

        val fillColor = when {
            isCharging -> WidgetPalette.primary
            levelPct != null -> WidgetPalette.forLevel(levelPct)
            else -> WidgetPalette.textMuted
        }

        // Track
        canvas.drawRoundRect(
            bodyRect,
            radius,
            radius,
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = WidgetPalette.track
            },
        )

        // Fill, clipped to the body so the rounded ends stay clean.
        val fraction = ((levelPct ?: 0.0) / 100.0).coerceIn(0.0, 1.0)
        if (fraction > 0) {
            canvas.save()
            val clip = android.graphics.Path().apply {
                addRoundRect(bodyRect, radius, radius, android.graphics.Path.Direction.CW)
            }
            canvas.clipPath(clip)
            canvas.drawRect(
                0f,
                0f,
                (bodyWidth * fraction).toFloat(),
                height.toFloat(),
                android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = fillColor
                },
            )
            canvas.restore()
        }

        // The user's charge limit, as a notch in the track.
        if (chargeLimitPct != null && chargeLimitPct in 1..99) {
            val x = bodyWidth * (chargeLimitPct / 100f)
            canvas.drawRect(
                x - dp(context, 1) / 2f,
                height * 0.12f,
                x + dp(context, 1) / 2f,
                height * 0.88f,
                android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = WidgetPalette.accent
                },
            )
        }

        // Cap
        canvas.drawRoundRect(
            android.graphics.RectF(
                width - capWidth,
                (height - capHeight) / 2f,
                width.toFloat(),
                (height + capHeight) / 2f,
            ),
            capWidth / 2.5f,
            capWidth / 2.5f,
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = fillColor
            },
        )

        return bitmap
    }

    /**
     * The battery level over the last few hours.
     *
     * Charging stretches are drawn green and discharging stretches blue, so
     * the rhythm of a day — a long slow fall, a sharp climb — is readable
     * without a legend or an axis. There are no labels at all: at widget size
     * the shape is the information, and anything else is clutter.
     */
    fun sparkline(
        context: android.content.Context,
        widthDp: Int,
        heightDp: Int,
        points: List<WidgetHistory.Point>,
    ): android.graphics.Bitmap {
        val width = dp(context, widthDp)
        val height = dp(context, heightDp)
        val bitmap = android.graphics.Bitmap.createBitmap(
            width,
            height,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = android.graphics.Canvas(bitmap)

        if (points.size < 2) return bitmap

        val firstTime = points.first().timestampMs
        val lastTime = points.last().timestampMs
        val span = (lastTime - firstTime).coerceAtLeast(1L)

        val padding = dp(context, 3).toFloat()
        val usableHeight = height - padding * 2

        // Fixed 0..100 rather than fitting to the data: a sparkline that
        // rescales would make a 2% dip look identical to a 60% drain, which is
        // the opposite of what a glance should convey.
        fun xFor(point: WidgetHistory.Point) =
            ((point.timestampMs - firstTime).toDouble() / span * width).toFloat()

        fun yFor(point: WidgetHistory.Point) =
            padding + (usableHeight * (1 - point.levelPct / 100.0)).toFloat()

        // Filled area under the whole trace, so the widget reads as a solid
        // shape at a distance rather than a thin wandering line.
        val areaPath = android.graphics.Path().apply {
            moveTo(xFor(points.first()), height.toFloat())
            for (point in points) lineTo(xFor(point), yFor(point))
            lineTo(xFor(points.last()), height.toFloat())
            close()
        }

        canvas.drawPath(
            areaPath,
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                shader = android.graphics.LinearGradient(
                    0f,
                    padding,
                    0f,
                    height.toFloat(),
                    android.graphics.Color.argb(70, 57, 231, 95),
                    android.graphics.Color.argb(0, 57, 231, 95),
                    android.graphics.Shader.TileMode.CLAMP,
                )
            },
        )

        // The trace itself, segment by segment so charge and discharge can be
        // coloured differently.
        val linePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = dp(context, 2).toFloat()
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }

        for (i in 1 until points.size) {
            val from = points[i - 1]
            val to = points[i]
            linePaint.color =
                if (to.charging) WidgetPalette.primary else WidgetPalette.info
            canvas.drawLine(xFor(from), yFor(from), xFor(to), yFor(to), linePaint)
        }

        // A dot on the newest reading, so "now" is unambiguous.
        val last = points.last()
        canvas.drawCircle(
            xFor(last).coerceAtMost(width - dp(context, 3).toFloat()),
            yFor(last),
            dp(context, 3).toFloat(),
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = if (last.charging) WidgetPalette.primary else WidgetPalette.info
            },
        )

        return bitmap
    }

    private fun dp(context: android.content.Context, value: Int): Int =
        android.util.TypedValue.applyDimension(
            android.util.TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics,
        ).toInt()
}
