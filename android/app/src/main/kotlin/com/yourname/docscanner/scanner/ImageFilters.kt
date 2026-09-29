package com.yourname.docscanner.scanner

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

object ImageFilters {

    private const val TAG = "DocScan"

    /**
     * Executes the requested filter on [inPath] and saves the result to [outPath].
     * Supports all 8 filters:
     * - original ("أصلي")
     * - magic ("لون سحري" — LAB CLAHE + vibrance boost + background whitening)
     * - enhance ("توضيح" — Flatten + Levels LUT + Unsharp Mask)
     * - lighten ("تفتيح" — Gamma 0.7 + contrast boost)
     * - no_handwriting ("إزالة خط اليد" — Enhance + HSV colored-ink mask removal)
     * - gray ("رمادي" — Flatten + Grayscale + Levels LUT)
     * - bw ("أبيض وأسود" — High-contrast sharp Sauvola-style binary document)
     * - eco ("توفير الحبر" — Soft adaptive threshold C=12 for ink-saving printing)
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
            val normalizedFilter = when (filter.lowercase().trim()) {
                "original" -> "original"
                "magic", "magic_color" -> "magic"
                "document", "enhance" -> "enhance"
                "color", "lighten" -> "lighten"
                "no_handwriting", "nohandwriting" -> "no_handwriting"
                "grayscale", "gray" -> "gray"
                "bw", "blackwhite_sharp", "sauvola" -> "bw"
                "blackwhite", "eco" -> "eco"
                else -> "enhance"
            }

            result = when (normalizedFilter) {
                "original" -> processingMat.clone()
                "magic" -> applyMagicColor(processingMat)
                "enhance" -> applyEnhance(processingMat)
                "lighten" -> applyLighten(processingMat)
                "no_handwriting" -> applyNoHandwriting(processingMat)
                "gray" -> applyGray(processingMat)
                "bw" -> applyBwSharp(processingMat)
                "eco" -> applyEco(processingMat)
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
     * Preprocesses an image specifically for high-accuracy Arabic/English OCR:
     * 1. Upscale small images to ~300 DPI equivalent (long side >= 2200px) using INTER_CUBIC.
     * 2. Illumination flattening + conversion to grayscale.
     * 3. Noise removal via median & Gaussian smoothing.
     * 4. Deskew text tilt (-12..+12 degrees) via morphological text line detection & minAreaRect.
     * 5. Sauvola-like adaptive thresholding for crisp glyphs.
     */
    fun preprocessForOcr(inPath: String, outPath: String): Boolean {
        val src = Imgcodecs.imread(inPath, Imgcodecs.IMREAD_COLOR)
        if (src.empty()) return false

        var working = src
        try {
            // 1. Upscale small images so Arabic diacritics and ligatures have sufficient pixels (~300 DPI)
            val longer = max(working.cols(), working.rows())
            if (longer < 2200) {
                val scale = (2200.0 / longer.toDouble()).coerceAtMost(2.5)
                val upscaled = Mat()
                Imgproc.resize(
                    working,
                    upscaled,
                    Size(working.cols() * scale, working.rows() * scale),
                    0.0,
                    0.0,
                    Imgproc.INTER_CUBIC
                )
                if (working !== src) working.release()
                working = upscaled
            }

            // 2. Flatten illumination & convert to grayscale
            val flattened = flatten(working)
            val gray = Mat()
            Imgproc.cvtColor(flattened, gray, Imgproc.COLOR_BGR2GRAY)
            flattened.release()

            // 3. Denoise while keeping character edges sharp
            val denoised = Mat()
            Imgproc.GaussianBlur(gray, denoised, Size(3.0, 3.0), 0.0)
            gray.release()

            // 4. Estimate skew angle and deskew if tilt is between 0.4 and 12 degrees
            val skewAngle = estimateSkewAngle(denoised)
            val deskewed = if (abs(skewAngle) in 0.4..12.0) {
                rotateKeepBounds(denoised, skewAngle)
            } else {
                denoised.clone()
            }
            denoised.release()

            // 5. Adaptive thresholding tuned for Arabic connected script
            val w = deskewed.cols()
            val h = deskewed.rows()
            var blockSize = (min(w, h) / 28) or 1
            if (blockSize < 15) blockSize = 15

            val binary = Mat()
            Imgproc.adaptiveThreshold(
                deskewed,
                binary,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY,
                blockSize,
                10.0
            )
            deskewed.release()

            File(outPath).parentFile?.mkdirs()
            val params = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
            val ok = Imgcodecs.imwrite(outPath, binary, params)
            params.release()
            binary.release()
            return ok
        } catch (e: Exception) {
            Log.e(TAG, "preprocessForOcr error", e)
            return false
        } finally {
            if (working !== src) working.release()
            src.release()
        }
    }

    private fun estimateSkewAngle(gray: Mat): Double {
        val small = Mat()
        val scale = 800.0 / max(gray.cols(), gray.rows()).toDouble()
        if (scale < 1.0) {
            Imgproc.resize(gray, small, Size(gray.cols() * scale, gray.rows() * scale), 0.0, 0.0, Imgproc.INTER_AREA)
        } else {
            gray.copyTo(small)
        }

        val inv = Mat()
        Imgproc.threshold(small, inv, 0.0, 255.0, Imgproc.THRESH_BINARY_INV or Imgproc.THRESH_OTSU)
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(25.0, 3.0))
        val connected = Mat()
        Imgproc.dilate(inv, connected, kernel)

        val contours = ArrayList<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(connected, contours, hierarchy, Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)

        val angles = ArrayList<Double>()
        for (c in contours) {
            val rect = Imgproc.boundingRect(c)
            if (rect.width > 40 && rect.height in 6..80 && rect.width > rect.height * 2) {
                val pts2f = MatOfPoint2f(*c.toArray())
                val minRect = Imgproc.minAreaRect(pts2f)
                pts2f.release()
                var angle = minRect.angle
                if (minRect.size.width < minRect.size.height) {
                    angle += 90.0
                }
                if (abs(angle) <= 12.0) {
                    angles.add(angle)
                }
            }
            c.release()
        }
        small.release()
        inv.release()
        kernel.release()
        connected.release()
        hierarchy.release()

        if (angles.isEmpty()) return 0.0
        angles.sort()
        return angles[angles.size / 2]
    }

    private fun rotateKeepBounds(src: Mat, angleDeg: Double): Mat {
        val center = Point(src.cols() / 2.0, src.rows() / 2.0)
        val rotMat = Imgproc.getRotationMatrix2D(center, angleDeg, 1.0)
        val dst = Mat()
        Imgproc.warpAffine(
            src,
            dst,
            rotMat,
            src.size(),
            Imgproc.INTER_LINEAR,
            Core.BORDER_CONSTANT,
            Scalar(255.0, 255.0, 255.0)
        )
        rotMat.release()
        return dst
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
     * Magic Color ("لون سحري"):
     * Flattens shadows -> Converts to LAB -> Applies CLAHE on L channel + boosts A/B saturation -> Sharpens.
     */
    private fun applyMagicColor(src: Mat): Mat {
        val flattened = flatten(src)
        val lab = Mat()
        Imgproc.cvtColor(flattened, lab, Imgproc.COLOR_BGR2Lab)
        flattened.release()

        val channels = ArrayList<Mat>(3)
        Core.split(lab, channels)
        lab.release()

        // CLAHE on Luminance + strong white clipping
        val clahe = Imgproc.createCLAHE(2.4, Size(8.0, 8.0))
        val lEnhanced = Mat()
        clahe.apply(channels[0], lEnhanced)
        channels[0].release()

        // Stretch L levels (black=25, white=215) for crisp white paper background
        val lut = Mat(1, 256, CvType.CV_8UC1)
        val lutData = ByteArray(256)
        for (i in 0..255) {
            val v = i.toDouble()
            val mapped = when {
                v <= 25.0 -> 0.0
                v >= 215.0 -> 255.0
                else -> 255.0 * ((v - 25.0) / (215.0 - 25.0)).pow(0.95)
            }
            lutData[i] = mapped.toInt().coerceIn(0, 255).toByte()
        }
        lut.put(0, 0, lutData)
        val lFinal = Mat()
        Core.LUT(lEnhanced, lut, lFinal)
        lEnhanced.release()
        lut.release()
        channels[0] = lFinal

        // Boost color saturation on A & B channels around neutral 128
        val satLut = Mat(1, 256, CvType.CV_8UC1)
        val satData = ByteArray(256)
        for (i in 0..255) {
            val boosted = 128.0 + (i - 128.0) * 1.32
            satData[i] = boosted.toInt().coerceIn(0, 255).toByte()
        }
        satLut.put(0, 0, satData)
        val aBoosted = Mat()
        val bBoosted = Mat()
        Core.LUT(channels[1], satLut, aBoosted)
        Core.LUT(channels[2], satLut, bBoosted)
        channels[1].release()
        channels[2].release()
        satLut.release()
        channels[1] = aBoosted
        channels[2] = bBoosted

        val mergedLab = Mat()
        Core.merge(channels, mergedLab)
        for (ch in channels) ch.release()

        val bgr = Mat()
        Imgproc.cvtColor(mergedLab, bgr, Imgproc.COLOR_Lab2BGR)
        mergedLab.release()
        return bgr
    }

    /**
     * Lighten ("تفتيح"): Gamma ~0.7 with slight contrast boost.
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
     * Enhance ("توضيح"): Flatten -> Levels LUT (black 35, white 225, gamma 1.1) -> Unsharp mask.
     */
    private fun applyEnhance(src: Mat): Mat {
        val flattened = flatten(src)

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

        val blurred = Mat()
        val sharpened = Mat()
        Imgproc.GaussianBlur(leveled, blurred, Size(0.0, 0.0), 2.0)
        Core.addWeighted(leveled, 1.6, blurred, -0.6, 0.0, sharpened)

        leveled.release()
        blurred.release()

        return sharpened
    }

    /**
     * Gray ("رمادي"): Flatten -> Convert to Grayscale -> Levels LUT.
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

        val bgr = Mat()
        Imgproc.cvtColor(leveled, bgr, Imgproc.COLOR_GRAY2BGR)
        leveled.release()

        return bgr
    }

    /**
     * B&W Sharp ("أبيض وأسود"): High-contrast Sauvola-inspired sharp binary document filter.
     */
    private fun applyBwSharp(src: Mat): Mat {
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
        var blockSize = (min(w, h) / 22) or 1
        if (blockSize < 11) blockSize = 11

        val binarized = Mat()
        Imgproc.adaptiveThreshold(
            gray,
            binarized,
            255.0,
            Imgproc.ADAPTIVE_THRESH_MEAN_C,
            Imgproc.THRESH_BINARY,
            blockSize,
            8.0
        )
        gray.release()

        val bgr = Mat()
        Imgproc.cvtColor(binarized, bgr, Imgproc.COLOR_GRAY2BGR)
        binarized.release()
        return bgr
    }

    /**
     * Eco ("توفير الحبر"): Flatten -> Grayscale -> AdaptiveThreshold (GAUSSIAN_C, C=12).
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
     * No Handwriting ("إزالة خط اليد"): Enhance -> HSV mask (S>70, V>40) dilated 3x3 x2 -> Paint white.
     */
    private fun applyNoHandwriting(src: Mat): Mat {
        val enhanced = applyEnhance(src)
        val hsv = Mat()
        Imgproc.cvtColor(enhanced, hsv, Imgproc.COLOR_BGR2HSV)

        val mask = Mat()
        Core.inRange(
            hsv,
            Scalar(0.0, 70.0, 40.0),
            Scalar(180.0, 255.0, 255.0),
            mask
        )
        hsv.release()

        val kernel3 = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.dilate(mask, mask, kernel3, Point(-1.0, -1.0), 2)
        kernel3.release()

        enhanced.setTo(Scalar(255.0, 255.0, 255.0), mask)
        mask.release()

        return enhanced
    }
}
