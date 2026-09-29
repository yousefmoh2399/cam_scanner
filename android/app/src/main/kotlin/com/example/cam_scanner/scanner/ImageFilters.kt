package com.example.cam_scanner.scanner

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

object ImageFilters {

    private const val TAG = "DocScan"

    /**
     * Executes the requested filter on [inPath] and saves the result to [outPath].
     * @param maxSide If > 0, downsamples image so max(width, height) <= maxSide before filtering.
     */
    fun runFile(inPath: String, outPath: String, filter: String, maxSide: Int = 0): Boolean {
        val startTime = System.currentTimeMillis()
        val inFile = File(inPath)
        if (!inFile.exists()) {
            Log.e(TAG, "Input file does not exist: $inPath")
            return false
        }

        val src = Imgcodecs.imread(inPath, Imgcodecs.IMREAD_COLOR)
        if (src.empty()) {
            Log.e(TAG, "Failed to read image at: $inPath")
            return false
        }

        var processingMat = src
        var didResize = false

        if (maxSide > 0) {
            val longer = max(src.cols(), src.rows())
            if (longer > maxSide) {
                val scale = maxSide.toDouble() / longer.toDouble()
                val resized = Mat()
                Imgproc.resize(
                    src,
                    resized,
                    Size(src.cols() * scale, src.rows() * scale),
                    0.0,
                    0.0,
                    Imgproc.INTER_AREA
                )
                processingMat = resized
                didResize = true
            }
        }

        var result: Mat? = null
        try {
            val normalizedFilter = when (filter.lowercase()) {
                "document", "enhance" -> "enhance"
                "color", "lighten" -> "lighten"
                "grayscale", "gray" -> "gray"
                "blackwhite", "eco" -> "eco"
                "no_handwriting", "nohandwriting" -> "no_handwriting"
                "original" -> "original"
                else -> "enhance"
            }

            result = when (normalizedFilter) {
                "original" -> processingMat.clone()
                "lighten" -> applyLighten(processingMat)
                "enhance" -> applyEnhance(processingMat)
                "gray" -> applyGray(processingMat)
                "eco" -> applyEco(processingMat)
                "no_handwriting" -> applyNoHandwriting(processingMat)
                else -> applyEnhance(processingMat)
            }

            val outFile = File(outPath)
            outFile.parentFile?.mkdirs()

            val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 90)
            val success = Imgcodecs.imwrite(outPath, result, writeParams)
            writeParams.release()

            val elapsed = System.currentTimeMillis() - startTime
            Log.d(TAG, "Filter '$normalizedFilter' runFile completed in ${elapsed}ms -> $outPath (success=$success)")
            return success
        } catch (e: Exception) {
            Log.e(TAG, "Error applying filter '$filter'", e)
            return false
        } finally {
            src.release()
            if (didResize) {
                processingMat.release()
            }
            result?.release()
        }
    }

    /**
     * Estimates background illumination by downscaling, morphological dilation,
     * and median blur, then divides source by background map scaled by 255.
     */
    fun flatten(src: Mat): Mat {
        val originalW = src.cols().toDouble()
        val originalH = src.rows().toDouble()
        val longerSide = max(originalW, originalH)
        val targetLongSide = 400.0
        val scale = if (longerSide > targetLongSide) targetLongSide / longerSide else 1.0

        val downscaled = Mat()
        if (scale < 1.0) {
            Imgproc.resize(
                src,
                downscaled,
                Size(originalW * scale, originalH * scale),
                0.0,
                0.0,
                Imgproc.INTER_AREA
            )
        } else {
            src.copyTo(downscaled)
        }

        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(7.0, 7.0))
        val dilated = Mat()
        val blurredBg = Mat()
        val fullBg = Mat()
        val flattened = Mat()

        try {
            Imgproc.dilate(downscaled, dilated, kernel)
            Imgproc.medianBlur(dilated, blurredBg, 21)

            Imgproc.resize(
                blurredBg,
                fullBg,
                Size(originalW, originalH),
                0.0,
                0.0,
                Imgproc.INTER_LINEAR
            )

            // Direct channel division: result = (src / fullBg) * 255.0
            Core.divide(src, fullBg, flattened, 255.0)
            return flattened
        } finally {
            downscaled.release()
            kernel.release()
            dilated.release()
            blurredBg.release()
            fullBg.release()
        }
    }

    /**
     * Lighten: Gamma ~0.7 with slight contrast boost.
     */
    private fun applyLighten(src: Mat): Mat {
        val lut = Mat(1, 256, CvType.CV_8UC1)
        val lutData = ByteArray(256)
        val gamma = 0.7
        val contrastFactor = 1.08

        for (i in 0..255) {
            val normalized = i / 255.0
            val gammaCorrected = normalized.pow(gamma)
            val boosted = ((gammaCorrected - 0.5) * contrastFactor + 0.5) * 255.0
            lutData[i] = boosted.toInt().coerceIn(0, 255).toByte()
        }
        lut.put(0, 0, lutData)

        val result = Mat()
        Core.LUT(src, lut, result)
        lut.release()
        return result
    }

    /**
     * Enhance: Flatten -> Levels LUT (black 35, white 225, gamma 1.1) -> Unsharp mask.
     */
    private fun applyEnhance(src: Mat): Mat {
        val flattened = flatten(src)

        // Build Levels LUT (black=35, white=225, gamma=1.1)
        val lut = Mat(1, 256, CvType.CV_8UC1)
        val lutData = ByteArray(256)
        val black = 35.0
        val white = 225.0
        val gamma = 1.1

        for (i in 0..255) {
            val v = i.toDouble()
            val mapped = when {
                v <= black -> 0.0
                v >= white -> 255.0
                else -> 255.0 * ((v - black) / (white - black)).pow(gamma)
            }
            lutData[i] = mapped.toInt().coerceIn(0, 255).toByte()
        }
        lut.put(0, 0, lutData)

        val leveled = Mat()
        Core.LUT(flattened, lut, leveled)
        flattened.release()
        lut.release()

        // Unsharp mask: Gaussian sigma 2.0, weights 1.6 / -0.6
        val blurred = Mat()
        val sharpened = Mat()
        Imgproc.GaussianBlur(leveled, blurred, Size(0.0, 0.0), 2.0)
        Core.addWeighted(leveled, 1.6, blurred, -0.6, 0.0, sharpened)

        leveled.release()
        blurred.release()

        return sharpened
    }

    /**
     * Gray: Flatten -> Convert to Grayscale -> Levels LUT.
     */
    private fun applyGray(src: Mat): Mat {
        val flattened = flatten(src)
        val gray = Mat()
        if (flattened.channels() >= 3) {
            Imgproc.cvtColor(flattened, gray, Imgproc.COLOR_BGR2GRAY)
            flattened.release()
        } else {
            flattened.copyTo(gray)
            flattened.release()
        }

        val lut = Mat(1, 256, CvType.CV_8UC1)
        val lutData = ByteArray(256)
        val black = 40.0
        val white = 220.0
        val invGamma = 1.0 / 1.1

        for (i in 0..255) {
            val v = i.toDouble()
            val mapped = when {
                v <= black -> 0.0
                v >= white -> 255.0
                else -> 255.0 * ((v - black) / (white - black)).pow(invGamma)
            }
            lutData[i] = mapped.toInt().coerceIn(0, 255).toByte()
        }
        lut.put(0, 0, lutData)

        val leveled = Mat()
        Core.LUT(gray, lut, leveled)
        gray.release()
        lut.release()

        // Convert back to BGR so all filters output 3-channel consistent Mats
        val bgr = Mat()
        Imgproc.cvtColor(leveled, bgr, Imgproc.COLOR_GRAY2BGR)
        leveled.release()

        return bgr
    }

    /**
     * Eco: Flatten -> Grayscale -> AdaptiveThreshold (GAUSSIAN_C, C=12).
     */
    private fun applyEco(src: Mat): Mat {
        val flattened = flatten(src)
        val gray = Mat()
        if (flattened.channels() >= 3) {
            Imgproc.cvtColor(flattened, gray, Imgproc.COLOR_BGR2GRAY)
            flattened.release()
        } else {
            flattened.copyTo(gray)
            flattened.release()
        }

        val w = gray.cols()
        val h = gray.rows()
        var blockSize = (min(w, h) / 30) or 1
        if (blockSize < 3) blockSize = 3

        val binarized = Mat()
        Imgproc.adaptiveThreshold(
            gray,
            binarized,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY,
            blockSize,
            12.0
        )
        gray.release()

        val bgr = Mat()
        Imgproc.cvtColor(binarized, bgr, Imgproc.COLOR_GRAY2BGR)
        binarized.release()

        return bgr
    }

    /**
     * No Handwriting: Enhance -> HSV mask (S>70, V>40) dilated 3x3 x2 -> Paint white.
     */
    private fun applyNoHandwriting(src: Mat): Mat {
        val enhanced = applyEnhance(src)
        val hsv = Mat()
        Imgproc.cvtColor(enhanced, hsv, Imgproc.COLOR_BGR2HSV)

        // Colored ink mask: Saturation > 70, Value > 40
        val mask = Mat()
        Core.inRange(
            hsv,
            Scalar(0.0, 70.0, 40.0),
            Scalar(180.0, 255.0, 255.0),
            mask
        )
        hsv.release()

        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.dilate(mask, mask, kernel3, org.opencv.core.Point(-1.0, -1.0), 2)
        kernel3.release()

        // Paint colored ink white
        enhanced.setTo(Scalar(255.0, 255.0, 255.0), mask)
        mask.release()

        return enhanced
    }
}
