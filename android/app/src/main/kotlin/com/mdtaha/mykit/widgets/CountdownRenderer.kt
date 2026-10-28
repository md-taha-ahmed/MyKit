package com.mdtaha.mykit.widgets

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface

/**
 * Draws the countdown ring into a bitmap.
 * Geometry mirrors `countdown_ring.dart` so the widget matches the in-app preview.
 */
object CountdownRenderer {
    private const val STROKE_RATIO = 0.075f

    fun render(c: CountdownData, sizePx: Int): Bitmap {
        val snap = CountdownMath.snapshot(c)
        return draw(
            sizePx = sizePx,
            progress = snap.progress,
            ringColor = c.ringColor,
            trackColor = c.trackColor,
            backgroundColor = c.backgroundColor,
            textColor = c.textColor,
            valueText = snap.valueText,
            label = if (c.showLabel) snap.label else null,
            typeface = typefaceFor(c.font),
            clockwise = c.clockwise,
            shadow = c.dropShadow,
        )
    }

    /** Shown by widgets that aren't linked to a countdown yet. */
    fun renderPlaceholder(sizePx: Int): Bitmap = draw(
        sizePx = sizePx,
        progress = 1f,
        ringColor = Color.parseColor("#5F6368"),
        trackColor = Color.BLACK,
        backgroundColor = Color.BLACK,
        textColor = Color.WHITE,
        valueText = "+",
        label = "Set up",
        typeface = Typeface.DEFAULT_BOLD,
        clockwise = true,
        shadow = false,
    )

    private fun draw(
        sizePx: Int,
        progress: Float,
        ringColor: Int,
        trackColor: Int,
        backgroundColor: Int,
        textColor: Int,
        valueText: String,
        label: String?,
        typeface: Typeface,
        clockwise: Boolean,
        shadow: Boolean,
    ): Bitmap {
        val s = sizePx.toFloat()
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val cx = s / 2
        val cy = s / 2
        val stroke = s * STROKE_RATIO
        val outer = s / 2 - s * 0.03f
        val ringRadius = outer - stroke / 2

        if (shadow) {
            val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(128, 0, 0, 0)
                maskFilter = BlurMaskFilter(s * 0.025f, BlurMaskFilter.Blur.NORMAL)
            }
            canvas.drawCircle(cx, cy + s * 0.015f, outer, shadowPaint)
        }

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = backgroundColor }
        canvas.drawCircle(cx, cy, outer, fill)

        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = trackColor
        }
        canvas.drawCircle(cx, cy, ringRadius, ring)

        if (progress > 0f) {
            ring.color = ringColor
            val sweep = 360f * progress * if (clockwise) 1 else -1
            val oval = RectF(cx - ringRadius, cy - ringRadius, cx + ringRadius, cy + ringRadius)
            canvas.drawArc(oval, -90f, sweep, false, ring)
        }

        // Text block: value (height .3s) + optional label (height .12s), centered.
        val innerWidth = s * (1 - 2 * STROKE_RATIO) * 0.78f
        val valueBoxH = s * 0.3f
        val labelBoxH = if (label != null) s * 0.12f else 0f
        var top = cy - (valueBoxH + labelBoxH) / 2

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            this.typeface = typeface
            textAlign = Paint.Align.CENTER
            if (shadow) setShadowLayer(s * 0.03f, 0f, s * 0.012f, Color.argb(153, 0, 0, 0))
        }

        drawFitted(canvas, textPaint, valueText, cx, top, innerWidth, valueBoxH)
        top += valueBoxH
        if (label != null) {
            drawFitted(canvas, textPaint, label, cx, top, innerWidth, labelBoxH / 1.1f)
        }
        return bitmap
    }

    /** Draws [text] scaled down (never up past [boxH]) to fit the box, centered. */
    private fun drawFitted(
        canvas: Canvas,
        paint: Paint,
        text: String,
        cx: Float,
        top: Float,
        maxWidth: Float,
        boxH: Float,
    ) {
        paint.textSize = boxH
        val width = paint.measureText(text)
        if (width > maxWidth) paint.textSize = boxH * maxWidth / width
        val fm = paint.fontMetrics
        val baseline = top + boxH / 2 - (fm.ascent + fm.descent) / 2
        canvas.drawText(text, cx, baseline, paint)
    }

    private fun typefaceFor(font: String): Typeface = when (font) {
        "serif" -> Typeface.create(Typeface.SERIF, Typeface.BOLD)
        "monospace" -> Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        "condensed" -> Typeface.create("sans-serif-condensed", Typeface.BOLD)
        else -> Typeface.DEFAULT_BOLD
    }
}
