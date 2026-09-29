package com.example.cam_scanner.scanner

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import org.opencv.core.Point

/**
 * Overlay view that draws a dynamic translucent quadrilateral, corner circles,
 * and Auto-Shutter progress indicator over the detected document in real time.
 */
class QuadOverlayView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.parseColor("#3300E676")
    }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FF00E676")
        strokeWidth = 3f * density
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val cornerFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.parseColor("#FF00E676")
    }

    private val cornerStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.WHITE
        strokeWidth = 2.5f * density
    }

    private val progressBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#55FFFFFF")
        strokeWidth = 4f * density
    }

    private val progressArcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FF00E676")
        strokeWidth = 4.5f * density
        strokeCap = Paint.Cap.ROUND
    }

    private var normalizedPoints: List<Point>? = null
    private var autoShutterProgress: Float = 0f
    private val path = Path()
    private val arcRect = RectF()

    fun setPolygon(pts: List<Point>?) {
        normalizedPoints = pts
        if (pts == null) {
            autoShutterProgress = 0f
        }
        invalidate()
    }

    fun setAutoShutterProgress(progress: Float) {
        autoShutterProgress = progress.coerceIn(0f, 1f)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val pts = normalizedPoints ?: return
        if (pts.size != 4) return

        val w = width.toFloat()
        val h = height.toFloat()

        val p0x = (pts[0].x * w).toFloat()
        val p0y = (pts[0].y * h).toFloat()
        val p1x = (pts[1].x * w).toFloat()
        val p1y = (pts[1].y * h).toFloat()
        val p2x = (pts[2].x * w).toFloat()
        val p2y = (pts[2].y * h).toFloat()
        val p3x = (pts[3].x * w).toFloat()
        val p3y = (pts[3].y * h).toFloat()

        path.reset()
        path.moveTo(p0x, p0y)
        path.lineTo(p1x, p1y)
        path.lineTo(p2x, p2y)
        path.lineTo(p3x, p3y)
        path.close()

        canvas.drawPath(path, fillPaint)
        canvas.drawPath(path, strokePaint)

        val cornerRadius = 6f * density
        val xs = floatArrayOf(p0x, p1x, p2x, p3x)
        val ys = floatArrayOf(p0y, p1y, p2y, p3y)
        for (i in 0..3) {
            canvas.drawCircle(xs[i], ys[i], cornerRadius, cornerFillPaint)
            canvas.drawCircle(xs[i], ys[i], cornerRadius, cornerStrokePaint)
        }

        // Draw Auto-Shutter progress ring at the document center when locking onto paper
        if (autoShutterProgress > 0.05f) {
            val cx = (p0x + p1x + p2x + p3x) / 4f
            val cy = (p0y + p1y + p2y + p3y) / 4f
            val ringRadius = 24f * density
            arcRect.set(cx - ringRadius, cy - ringRadius, cx + ringRadius, cy + ringRadius)
            canvas.drawOval(arcRect, progressBgPaint)
            canvas.drawArc(arcRect, -90f, 360f * autoShutterProgress, false, progressArcPaint)
        }
    }
}

typealias PolygonOverlayView = QuadOverlayView
