package com.laqta.scanner.scanner

import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import kotlin.math.hypot
import kotlin.math.max

object DocumentDetector {

    /**
     * Finds the 4-corner document quad in a single-channel grayscale Mat.
     * Orders points: [TL, TR, BR, BL] in original source coordinates.
     * Returns null if no valid document quad is detected.
     */
    fun findQuad(gray: Mat): List<Point>? {
        if (gray.empty() || gray.cols() <= 0 || gray.rows() <= 0) return null

        val originalWidth = gray.cols().toDouble()
        val originalHeight = gray.rows().toDouble()
        val longerSide = max(originalWidth, originalHeight)
        val targetLongSide = 500.0
        val scale = if (longerSide > targetLongSide) targetLongSide / longerSide else 1.0

        val downscaled = Mat()
        if (scale < 1.0) {
            Imgproc.resize(
                gray,
                downscaled,
                Size(originalWidth * scale, originalHeight * scale),
                0.0,
                0.0,
                Imgproc.INTER_LINEAR
            )
        } else {
            gray.copyTo(downscaled)
        }

        val blurred = Mat()
        val otsuBinary = Mat()
        val canny = Mat()
        val closed = Mat()
        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        val kernel7 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(7.0, 7.0))

        var bestQuad: List<Point>? = null
        var maxArea = 0.0

        try {
            Imgproc.GaussianBlur(downscaled, blurred, Size(5.0, 5.0), 0.0)

            // Compute Otsu threshold value
            val otsuThreshold = Imgproc.threshold(
                blurred,
                otsuBinary,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY or Imgproc.THRESH_OTSU
            )

            // Pass 1: Canny with (0.5 * otsu, otsu) + dilate 3x3
            Imgproc.Canny(blurred, canny, 0.5 * otsuThreshold, otsuThreshold)
            Imgproc.dilate(canny, canny, kernel3)

            // Pass 2: Otsu binary + MORPH_CLOSE 7x7
            Imgproc.morphologyEx(otsuBinary, closed, Imgproc.MORPH_CLOSE, kernel7)

            val downscaledArea = downscaled.cols() * downscaled.rows()
            val minArea = downscaledArea * 0.15
            val maxAreaAllowed = downscaledArea * 0.97

            // Analyze both passes
            val passes = listOf(canny, closed)
            for (passMat in passes) {
                val contours = ArrayList<MatOfPoint>()
                val hierarchy = Mat()
                Imgproc.findContours(
                    passMat,
                    contours,
                    hierarchy,
                    Imgproc.RETR_LIST,
                    Imgproc.CHAIN_APPROX_SIMPLE
                )
                hierarchy.release()

                // Sort top 5 by area
                contours.sortByDescending { Imgproc.contourArea(it) }
                val candidates = contours.take(5)

                for (contour in candidates) {
                    val area = Imgproc.contourArea(contour)
                    if (area < minArea || area > maxAreaAllowed) continue

                    val c2f = MatOfPoint2f(*contour.toArray())
                    val peri = Imgproc.arcLength(c2f, true)
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(c2f, approx, 0.02 * peri, true)
                    c2f.release()

                    if (approx.total() == 4L) {
                        val approxMat = MatOfPoint(*approx.toArray())
                        val isConvex = Imgproc.isContourConvex(approxMat)
                        approxMat.release()

                        if (isConvex && area > maxArea) {
                            maxArea = area
                            val pts = approx.toArray().toList()
                            bestQuad = pts
                        }
                    }
                    approx.release()
                }

                for (c in contours) {
                    c.release()
                }
            }
        } finally {
            downscaled.release()
            blurred.release()
            otsuBinary.release()
            canny.release()
            closed.release()
            kernel3.release()
            kernel7.release()
        }

        if (bestQuad == null) return null

        // Scale back to original coordinates
        val invScale = 1.0 / scale
        val scaledQuad = bestQuad.map { Point(it.x * invScale, it.y * invScale) }

        return orderPoints(scaledQuad)
    }

    /**
     * Orders 4 points to [TL, TR, BR, BL] using the sum and (y - x) coordinate projection method.
     */
    fun orderPoints(pts: List<Point>): List<Point> {
        require(pts.size == 4) { "orderPoints requires exactly 4 points" }

        // TL: min(x + y), BR: max(x + y)
        val tl = pts.minByOrNull { it.x + it.y } ?: pts[0]
        val br = pts.maxByOrNull { it.x + it.y } ?: pts[2]

        // TR: min(y - x), BL: max(y - x)
        val remaining = pts.filter { it !== tl && it !== br }
        val tr: Point
        val bl: Point
        if (remaining.size == 2) {
            tr = remaining.minByOrNull { it.y - it.x } ?: remaining[0]
            bl = remaining.maxByOrNull { it.y - it.x } ?: remaining[1]
        } else {
            // Fallback in degenerate coordinate cases
            tr = pts.minByOrNull { it.y - it.x } ?: pts[1]
            bl = pts.maxByOrNull { it.y - it.x } ?: pts[3]
        }

        return listOf(tl, tr, br, bl)
    }

    /**
     * Warps the quadrilateral region in [src] into a rectified rectangular Mat.
     * Quad points must be [TL, TR, BR, BL].
     * Insets the quad by 0.5% toward its centroid to eliminate residual dark border slivers.
     */
    fun warp(src: Mat, quad: List<Point>, maxSide: Int = 0): Mat {
        require(quad.size == 4) { "warp requires 4 points (TL, TR, BR, BL)" }

        val tl = quad[0]
        val tr = quad[1]
        val br = quad[2]
        val bl = quad[3]

        val widthA = hypot(br.x - bl.x, br.y - bl.y)
        val widthB = hypot(tr.x - tl.x, tr.y - tl.y)
        var maxWidth = max(widthA, widthB).toInt().coerceAtLeast(100)

        val heightA = hypot(tr.x - br.x, tr.y - br.y)
        val heightB = hypot(tl.x - bl.x, tl.y - bl.y)
        var maxHeight = max(heightA, heightB).toInt().coerceAtLeast(100)

        if (maxSide > 0) {
            val longer = max(maxWidth, maxHeight)
            if (longer > maxSide) {
                val scale = maxSide.toDouble() / longer.toDouble()
                maxWidth = (maxWidth * scale).toInt().coerceAtLeast(50)
                maxHeight = (maxHeight * scale).toInt().coerceAtLeast(50)
            }
        }

        // Centroid calculation
        val cx = (tl.x + tr.x + br.x + bl.x) / 4.0
        val cy = (tl.y + tr.y + br.y + bl.y) / 4.0

        // Inset ~0.5% toward centroid to remove dark edge slivers
        val insetFactor = 0.005
        fun shrink(p: Point): Point {
            return Point(
                p.x + insetFactor * (cx - p.x),
                p.y + insetFactor * (cy - p.y)
            )
        }

        val shTl = shrink(tl)
        val shTr = shrink(tr)
        val shBr = shrink(br)
        val shBl = shrink(bl)

        val srcPoints = MatOfPoint2f(shTl, shTr, shBr, shBl)
        val dstPoints = MatOfPoint2f(
            Point(0.0, 0.0),
            Point((maxWidth - 1).toDouble(), 0.0),
            Point((maxWidth - 1).toDouble(), (maxHeight - 1).toDouble()),
            Point(0.0, (maxHeight - 1).toDouble())
        )

        val transformMatrix = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
        val destination = Mat()
        Imgproc.warpPerspective(
            src,
            destination,
            transformMatrix,
            Size(maxWidth.toDouble(), maxHeight.toDouble()),
            Imgproc.INTER_LINEAR,
            Core.BORDER_REPLICATE
        )

        srcPoints.release()
        dstPoints.release()
        transformMatrix.release()

        return destination
    }
}