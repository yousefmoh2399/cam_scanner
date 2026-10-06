package com.yourname.docscanner

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.SystemClock
import com.googlecode.tesseract.android.TessBaseAPI
import com.yourname.docscanner.scanner.DocumentDetector
import com.yourname.docscanner.scanner.ImageFilters
import com.yourname.docscanner.scanner.ScannerActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.opencv.android.OpenCVLoader
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.Point
import org.opencv.imgcodecs.Imgcodecs
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

class MainActivity : FlutterFragmentActivity() {
    private val docScannerChannel = "ismart/doc_scanner"
    private val altScannerChannel = "com.yourname.docscanner/scanner"
    private val REQUEST_CODE_SCANNER = 0x534341
    private var pendingScannerResult: MethodChannel.Result? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)
    private val nativeOpSemaphore = java.util.concurrent.Semaphore(2)
    private var tts: android.speech.tts.TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!OpenCVLoader.initLocal()) {
            android.util.Log.e("MainActivity", "OpenCV init failed")
        }

        val handler = MethodChannel.MethodCallHandler setMethodCallHandler@{ call, result ->
                when (call.method) {
                    "startScan" -> {
                        if (pendingScannerResult != null) {
                            result.error("SCANNER_BUSY", "A scan is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingScannerResult = result
                        val destDir = call.argument<String>("destDir")
                        val batch = call.argument<Boolean>("batch") ?: false
                        try {
                            val intent = Intent(this, ScannerActivity::class.java).apply {
                                if (!destDir.isNullOrBlank()) {
                                    putExtra(ScannerActivity.EXTRA_DEST_DIR, destDir)
                                }
                                putExtra(ScannerActivity.EXTRA_BATCH_MODE, batch)
                            }
                            startActivityForResult(intent, REQUEST_CODE_SCANNER)
                        } catch (e: Exception) {
                            pendingScannerResult = null
                            result.error("LAUNCH_FAILED", "Failed to launch ScannerActivity: ${e.message}", null)
                        }
                    }
                    "getInitialQuickAction" -> {
                        val action = intent?.getStringExtra("quick_action")
                        if (action != null) {
                            intent?.removeExtra("quick_action")
                        }
                        result.success(action)
                    }
                    "warp" -> {
                        val path = call.argument<String>("path")
                        val rawCorners = call.argument<List<Double>>("corners")
                        val outPath = call.argument<String>("outPath")
                        val maxSide = call.argument<Int>("maxSide") ?: 0
                        val quarterTurns = call.argument<Int>("quarterTurns") ?: 0
                        if (path.isNullOrBlank() || rawCorners == null || rawCorners.size != 8 || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path, corners (8 items), and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            val warpStart = SystemClock.elapsedRealtime()
                            try {
                                var useReduced = false
                                if (maxSide > 0) {
                                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                    BitmapFactory.decodeFile(path, options)
                                    val longerSide = max(options.outWidth, options.outHeight)
                                    if (longerSide >= 2 * maxSide) {
                                        useReduced = true
                                    }
                                }
                                val readFlags = if (useReduced) Imgcodecs.IMREAD_REDUCED_COLOR_2 else Imgcodecs.IMREAD_COLOR
                                val src = Imgcodecs.imread(path, readFlags)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Failed to read image", null) }
                                    return@launch
                                }
                                val w = src.cols().toDouble()
                                val h = src.rows().toDouble()
                                val quad = listOf(
                                    Point(rawCorners[0] * w, rawCorners[1] * h),
                                    Point(rawCorners[2] * w, rawCorners[3] * h),
                                    Point(rawCorners[4] * w, rawCorners[5] * h),
                                    Point(rawCorners[6] * w, rawCorners[7] * h)
                                )
                                val warped = DocumentDetector.warp(src, quad, maxSide)
                                src.release()

                                val finalWarped = if (quarterTurns % 4 != 0) {
                                    val rotated = Mat()
                                    val turns = (quarterTurns % 4 + 4) % 4
                                    when (turns) {
                                        1 -> Core.rotate(warped, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                                        2 -> Core.rotate(warped, rotated, Core.ROTATE_180)
                                        3 -> Core.rotate(warped, rotated, Core.ROTATE_90_CLOCKWISE)
                                    }
                                    warped.release()
                                    rotated
                                } else {
                                    warped
                                }

                                val outFile = File(outPath)
                                outFile.parentFile?.mkdirs()
                                val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
                                val success = Imgcodecs.imwrite(outPath, finalWarped, writeParams)
                                writeParams.release()
                                finalWarped.release()

                                val warpDuration = SystemClock.elapsedRealtime() - warpStart
                                android.util.Log.d("DocScan", "Warp time (transform + write): ${warpDuration}ms -> $outPath (maxSide=$maxSide, quarterTurns=$quarterTurns, reduced=$useReduced)")

                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("WRITE_FAILED", "Failed to write warped image", null)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("WARP_ERROR", e.message, null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "applyFilter" -> {
                        val path = call.argument<String>("path")
                        val filter = call.argument<String>("filter") ?: "enhance"
                        val maxSide = call.argument<Int>("maxSide") ?: 0
                        val outPath = call.argument<String>("outPath")
                        if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val success = ImageFilters.runFile(path, outPath, filter, maxSide)
                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("FILTER_FAILED", "Failed to apply filter $filter", null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "preprocessForOcr" -> {
                        val path = call.argument<String>("path")
                        val outPath = call.argument<String>("outPath")
                        if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val success = ImageFilters.preprocessForOcr(path, outPath)
                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("OCR_PREP_FAILED", "Failed to preprocess image for OCR", null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "runTesseractOcr" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        val dataPath = call.argument<String>("dataPath") ?: ""
                        val language = call.argument<String>("language") ?: "ara+eng"
                        val preprocess = call.argument<Boolean>("preprocess") ?: true
                        if (imagePath.isBlank() || dataPath.isBlank()) {
                            result.error("INVALID_ARGS", "imagePath and dataPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            var prepFile: File? = null
                            val tess = TessBaseAPI()
                            try {
                                val targetPath = if (preprocess) {
                                    val tempOut = File(cacheDir, "ocr_prep_${System.currentTimeMillis()}.png")
                                    if (ImageFilters.preprocessForOcr(imagePath, tempOut.absolutePath)) {
                                        prepFile = tempOut
                                        tempOut.absolutePath
                                    } else {
                                        imagePath
                                    }
                                } else {
                                    imagePath
                                }

                                val initialized = tess.init(dataPath, language, TessBaseAPI.OEM_LSTM_ONLY)
                                if (!initialized) {
                                    withContext(Dispatchers.Main) {
                                        result.error("TESS_INIT_FAIL", "Failed to initialize Tesseract ($language) at $dataPath", null)
                                    }
                                    return@launch
                                }
                                tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
                                tess.setVariable("user_defined_dpi", "300")
                                tess.setVariable("preserve_interword_spaces", "1")

                                val bmpOpts = BitmapFactory.Options().apply {
                                    inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
                                }
                                val bitmap = BitmapFactory.decodeFile(targetPath, bmpOpts)
                                if (bitmap == null) {
                                    withContext(Dispatchers.Main) {
                                        result.error("BMP_DECODE_FAIL", "Could not decode image for OCR: $targetPath", null)
                                    }
                                    return@launch
                                }

                                val imgW = bitmap.width.coerceAtLeast(1)
                                val imgH = bitmap.height.coerceAtLeast(1)
                                tess.setImage(bitmap)
                                val fullText = tess.utF8Text ?: ""

                                val blocksList = ArrayList<HashMap<String, Any>>()
                                val iter = tess.resultIterator
                                if (iter != null) {
                                    val level = TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
                                    iter.begin()
                                    do {
                                        val lineText = iter.getUTF8Text(level)?.trim() ?: ""
                                        val box = iter.getBoundingRect(level)
                                        val conf = iter.confidence(level)
                                        if (lineText.isNotEmpty() && box != null) {
                                            val map = HashMap<String, Any>()
                                            map["text"] = lineText
                                            map["confidence"] = conf.toDouble()
                                            map["left"] = box.left.toDouble() / imgW.toDouble()
                                            map["top"] = box.top.toDouble() / imgH.toDouble()
                                            map["right"] = box.right.toDouble() / imgW.toDouble()
                                            map["bottom"] = box.bottom.toDouble() / imgH.toDouble()
                                            map["pixelLeft"] = box.left
                                            map["pixelTop"] = box.top
                                            map["pixelWidth"] = box.width()
                                            map["pixelHeight"] = box.height()
                                            blocksList.add(map)
                                        }
                                    } while (iter.next(level))
                                    iter.delete()
                                }
                                bitmap.recycle()

                                val response = HashMap<String, Any>()
                                response["text"] = fullText
                                response["width"] = imgW
                                response["height"] = imgH
                                response["blocks"] = blocksList

                                withContext(Dispatchers.Main) {
                                    result.success(response)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("TESS_OCR_ERR", e.message, null)
                                }
                            } finally {
                                try {
                                    tess.recycle()
                                } catch (_: Exception) {}
                                try {
                                    prepFile?.delete()
                                } catch (_: Exception) {}
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "consumeIncomingFiles" -> {
                        val files = extractIncomingFilesFromIntent(intent)
                        intent = Intent(this@MainActivity, MainActivity::class.java)
                        result.success(files)
                    }
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }
                    "rotateLeft" -> {
                        val path = call.argument<String>("path")
                        val outPath = call.argument<String>("outPath")
                        if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val src = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Failed to read image", null) }
                                    return@launch
                                }
                                val rotated = Mat()
                                Core.rotate(src, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                                src.release()

                                val outFile = File(outPath)
                                outFile.parentFile?.mkdirs()
                                val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
                                val success = Imgcodecs.imwrite(outPath, rotated, writeParams)
                                writeParams.release()
                                rotated.release()

                                withContext(Dispatchers.Main) {
                                    if (success) result.success(outPath)
                                    else result.error("WRITE_FAILED", "Failed to write rotated image", null)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("ROTATE_ERROR", e.message, null)
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    "compositeSignature" -> {
                        val pagePath = call.argument<String>("pagePath")
                        val sigBytes = call.argument<ByteArray>("signatureBytes")
                        val relX = call.argument<Double>("relX") ?: 0.05
                        val relY = call.argument<Double>("relY") ?: 0.70
                        val relW = call.argument<Double>("relW") ?: 0.40
                        val maxSide = call.argument<Int>("maxSide") ?: 2048
                        if (pagePath.isNullOrBlank() || sigBytes == null || sigBytes.isEmpty()) {
                            result.error("INVALID_ARGS", "pagePath and signatureBytes are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            val startMs = SystemClock.elapsedRealtime()
                            try {
                                val rawPage = BitmapFactory.decodeFile(pagePath)
                                if (rawPage == null) {
                                    withContext(Dispatchers.Main) {
                                        result.error("DECODE_PAGE_FAILED", "Failed to decode page image", null)
                                    }
                                    return@launch
                                }
                                val exif = androidx.exifinterface.media.ExifInterface(pagePath)
                                val orientation = exif.getAttributeInt(
                                    androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION,
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_NORMAL
                                )
                                val rotationDegrees = when (orientation) {
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                                    androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                                    else -> 0f
                                }
                                var orientedPage = if (rotationDegrees != 0f) {
                                    val m = android.graphics.Matrix().apply { postRotate(rotationDegrees) }
                                    val rotated = android.graphics.Bitmap.createBitmap(
                                        rawPage, 0, 0, rawPage.width, rawPage.height, m, true
                                    )
                                    if (rotated !== rawPage) rawPage.recycle()
                                    rotated
                                } else {
                                    rawPage
                                }

                                val longerSide = max(orientedPage.width, orientedPage.height)
                                if (maxSide > 0 && longerSide > maxSide) {
                                    val scale = maxSide.toFloat() / longerSide.toFloat()
                                    val newW = (orientedPage.width * scale).toInt().coerceAtLeast(1)
                                    val newH = (orientedPage.height * scale).toInt().coerceAtLeast(1)
                                    val scaled = android.graphics.Bitmap.createScaledBitmap(orientedPage, newW, newH, true)
                                    if (scaled !== orientedPage) orientedPage.recycle()
                                    orientedPage = scaled
                                }

                                val mutablePage = if (orientedPage.isMutable && orientedPage.config == android.graphics.Bitmap.Config.ARGB_8888) {
                                    orientedPage
                                } else {
                                    val copy = orientedPage.copy(android.graphics.Bitmap.Config.ARGB_8888, true)
                                    if (copy !== orientedPage) orientedPage.recycle()
                                    copy
                                }

                                val sigBitmap = BitmapFactory.decodeByteArray(sigBytes, 0, sigBytes.size)
                                if (sigBitmap == null) {
                                    mutablePage.recycle()
                                    withContext(Dispatchers.Main) {
                                        result.error("DECODE_SIG_FAILED", "Failed to decode signature PNG", null)
                                    }
                                    return@launch
                                }

                                val targetWidth = (mutablePage.width * relW).toInt().coerceIn(10, mutablePage.width)
                                val aspectRatio = sigBitmap.height.toFloat() / sigBitmap.width.toFloat().coerceAtLeast(1f)
                                val targetHeight = (targetWidth * aspectRatio).toInt().coerceIn(1, mutablePage.height)
                                val offsetX = (mutablePage.width * relX).toInt().coerceIn(0, (mutablePage.width - targetWidth).coerceAtLeast(0))
                                val offsetY = (mutablePage.height * relY).toInt().coerceIn(0, (mutablePage.height - targetHeight).coerceAtLeast(0))

                                val canvas = android.graphics.Canvas(mutablePage)
                                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.FILTER_BITMAP_FLAG)
                                val dstRect = android.graphics.RectF(
                                    offsetX.toFloat(),
                                    offsetY.toFloat(),
                                    (offsetX + targetWidth).toFloat(),
                                    (offsetY + targetHeight).toFloat()
                                )
                                canvas.drawBitmap(sigBitmap, null, dstRect, paint)
                                sigBitmap.recycle()

                                val baos = java.io.ByteArrayOutputStream(mutablePage.width * mutablePage.height / 4)
                                mutablePage.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, baos)
                                mutablePage.recycle()
                                val outBytes = baos.toByteArray()

                                val elapsed = SystemClock.elapsedRealtime() - startMs
                                android.util.Log.d("DocScan", "compositeSignature completed in ${elapsed}ms (${outBytes.size} bytes)")

                                withContext(Dispatchers.Main) {
                                    result.success(outBytes)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("COMPOSITE_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "checkBlur" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            try {
                                val src = Imgcodecs.imread(path, Imgcodecs.IMREAD_GRAYSCALE)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Could not load image", null) }
                                    return@launch
                                }
                                val laplacian = Mat()
                                org.opencv.imgproc.Imgproc.Laplacian(src, laplacian, org.opencv.core.CvType.CV_64F)
                                val mean = org.opencv.core.MatOfDouble()
                                val stddev = org.opencv.core.MatOfDouble()
                                Core.meanStdDev(laplacian, mean, stddev)
                                val std = stddev.get(0, 0)[0]
                                val variance = std * std
                                src.release()
                                laplacian.release()
                                mean.release()
                                stddev.release()
                                val isBlurry = variance < 80.0
                                withContext(Dispatchers.Main) {
                                    result.success(mapOf("isBlurry" to isBlurry, "variance" to variance))
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) { result.error("BLUR_ERR", e.message, null) }
                            }
                        }
                    }
                    "splitBookPage" -> {
                        val path = call.argument<String>("path")
                        val outRightPath = call.argument<String>("outRightPath")
                        val outLeftPath = call.argument<String>("outLeftPath")
                        if (path.isNullOrBlank() || outRightPath.isNullOrBlank() || outLeftPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path, outRightPath and outLeftPath are required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            try {
                                val src = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
                                if (src.empty()) {
                                    withContext(Dispatchers.Main) { result.error("READ_FAILED", "Could not load image", null) }
                                    return@launch
                                }
                                val w = src.cols()
                                val h = src.rows()
                                val midX = w / 2
                                val rectRight = org.opencv.core.Rect(midX, 0, w - midX, h)
                                val matRight = Mat(src, rectRight)
                                val rectLeft = org.opencv.core.Rect(0, 0, midX, h)
                                val matLeft = Mat(src, rectLeft)

                                val writeParams = MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95)
                                File(outRightPath).parentFile?.mkdirs()
                                File(outLeftPath).parentFile?.mkdirs()
                                Imgcodecs.imwrite(outRightPath, matRight, writeParams)
                                Imgcodecs.imwrite(outLeftPath, matLeft, writeParams)

                                src.release()
                                matRight.release()
                                matLeft.release()
                                writeParams.release()

                                withContext(Dispatchers.Main) {
                                    result.success(mapOf("pageRight" to outRightPath, "pageLeft" to outLeftPath))
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) { result.error("SPLIT_ERR", e.message, null) }
                            }
                        }
                    }
                    "speakText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("lang") ?: "ar"
                        if (text.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        if (tts == null) {
                            tts = android.speech.tts.TextToSpeech(this@MainActivity) { status ->
                                if (status == android.speech.tts.TextToSpeech.SUCCESS) {
                                    val locale = if (lang.startsWith("ar")) java.util.Locale("ar") else java.util.Locale.ENGLISH
                                    tts?.language = locale
                                    tts?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "tts_id")
                                }
                            }
                            result.success(true)
                        } else {
                            val locale = if (lang.startsWith("ar")) java.util.Locale("ar") else java.util.Locale.ENGLISH
                            tts?.language = locale
                            tts?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "tts_id")
                            result.success(true)
                        }
                    }
                    "stopSpeaking" -> {
                        tts?.stop()
                        result.success(true)
                    }
                    "detectCorners" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        mainScope.launch(Dispatchers.Default) {
                            nativeOpSemaphore.acquire()
                            try {
                                val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                BitmapFactory.decodeFile(path, boundsOptions)
                                val origW = boundsOptions.outWidth
                                val origH = boundsOptions.outHeight
                                if (origW <= 0 || origH <= 0) {
                                    withContext(Dispatchers.Main) { result.success(emptyList<Double>()) }
                                    return@launch
                                }

                                val maxTarget = 1024
                                var sampleSize = 1
                                while ((origW / sampleSize) > maxTarget || (origH / sampleSize) > maxTarget) {
                                    sampleSize *= 2
                                }

                                val decodeOptions = BitmapFactory.Options().apply {
                                    inSampleSize = sampleSize
                                    inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
                                }
                                val bmp = BitmapFactory.decodeFile(path, decodeOptions)
                                if (bmp == null) {
                                    withContext(Dispatchers.Main) { result.success(emptyList<Double>()) }
                                    return@launch
                                }
                                val bmpW = bmp.width.toDouble()
                                val bmpH = bmp.height.toDouble()

                                val matBgra = Mat()
                                org.opencv.android.Utils.bitmapToMat(bmp, matBgra)
                                bmp.recycle()

                                val gray = Mat()
                                org.opencv.imgproc.Imgproc.cvtColor(matBgra, gray, org.opencv.imgproc.Imgproc.COLOR_BGRA2GRAY)
                                matBgra.release()

                                val quad = DocumentDetector.findQuad(gray)
                                gray.release()

                                val corners = if (quad != null && quad.size == 4) {
                                    listOf(
                                        quad[0].x / bmpW, quad[0].y / bmpH,
                                        quad[1].x / bmpW, quad[1].y / bmpH,
                                        quad[2].x / bmpW, quad[2].y / bmpH,
                                        quad[3].x / bmpW, quad[3].y / bmpH
                                    )
                                } else {
                                    emptyList<Double>()
                                }

                                withContext(Dispatchers.Main) {
                                    result.success(corners)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.success(emptyList<Double>())
                                }
                            } finally {
                                nativeOpSemaphore.release()
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, docScannerChannel).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, altScannerChannel).setMethodCallHandler(handler)
    }

    private fun replyScannerResult(block: (MethodChannel.Result) -> Unit) {
        val pending = pendingScannerResult ?: return
        pendingScannerResult = null
        try {
            block(pending)
        } catch (e: Exception) {
            android.util.Log.e("DocScan", "Failed to reply to scanner result", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCANNER) {
            replyScannerResult { pending ->
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val batchList = data.getParcelableArrayListExtra<Bundle>(ScannerActivity.RESULT_BATCH_LIST)
                    if (batchList != null && batchList.isNotEmpty()) {
                        val results = batchList.map { b ->
                            mapOf(
                                "path" to (b.getString(ScannerActivity.RESULT_PATH) ?: ""),
                                "corners" to (b.getDoubleArray(ScannerActivity.RESULT_CORNERS)?.toList() ?: emptyList<Double>()),
                                "width" to b.getInt(ScannerActivity.RESULT_WIDTH, 0),
                                "height" to b.getInt(ScannerActivity.RESULT_HEIGHT, 0)
                            )
                        }
                        pending.success(mapOf("batch" to true, "items" to results))
                    } else {
                        val path = data.getStringExtra(ScannerActivity.RESULT_PATH)
                        val corners = data.getDoubleArrayExtra(ScannerActivity.RESULT_CORNERS)
                        val width = data.getIntExtra(ScannerActivity.RESULT_WIDTH, 0)
                        val height = data.getIntExtra(ScannerActivity.RESULT_HEIGHT, 0)
                        if (path != null && corners != null) {
                            pending.success(
                                mapOf(
                                    "batch" to false,
                                    "path" to path,
                                    "corners" to corners.toList(),
                                    "width" to width,
                                    "height" to height
                                )
                            )
                        } else {
                            pending.error("SCANNER_FAILED", "Incomplete scan result", null)
                        }
                    }
                } else {
                    pending.success(null)
                }
            }
        }
    }

    override fun getInitialRoute(): String {
        return "/"
    }

    private fun extractIncomingFilesFromIntent(incoming: Intent?): List<String> {
        if (incoming == null) return emptyList()
        val action = incoming.action
        // Only consume external shares (ACTION_SEND or ACTION_SEND_MULTIPLE)
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return emptyList()
        }
        val uris = ArrayList<android.net.Uri>()
        when (action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val single = incoming.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                if (single != null) uris.add(single)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val list = incoming.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                if (list != null) uris.addAll(list)
            }
        }
        val copiedPaths = ArrayList<String>()
        for ((idx, uri) in uris.withIndex()) {
            try {
                val uriStr = uri.toString()
                // Never re-import internal files belonging to the app
                if (uriStr.contains(packageName) || uriStr.contains("com.yourname.docscanner") || uriStr.contains("Exports")) {
                    continue
                }
                val mime = contentResolver.getType(uri) ?: ""
                val ext = if (mime.contains("pdf")) ".pdf" else ".jpg"
                val dest = File(cacheDir, "incoming_${System.currentTimeMillis()}_$idx$ext")
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(dest).use { output ->
                        input.copyTo(output)
                    }
                }
                if (dest.exists() && dest.length() > 0) {
                    copiedPaths.add(dest.absolutePath)
                }
            } catch (_: Exception) {}
        }
        return copiedPaths
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra("run_ocr_benchmark", false) == true) {
            runOcrDeviceBenchmark()
        }
    }

    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        intent = newIntent
        if (newIntent.getBooleanExtra("run_ocr_benchmark", false)) {
            runOcrDeviceBenchmark()
        }
    }

    private fun normalizeOcrText(raw: String): String {
        return raw
            .replace(Regex("[\\u064B-\\u065F\\u0670\\u0640]"), "")
            .replace(Regex("[إأآا]"), "ا")
            .replace("ى", "ي")
            .replace("ة", "ه")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun levenshteinDistance(a: List<String>, b: List<String>): Int {
        val n = a.size
        val m = b.size
        if (n == 0) return m
        if (m == 0) return n
        var prev = IntArray(m + 1) { it }
        var curr = IntArray(m + 1)
        for (i in 1..n) {
            curr[0] = i
            for (j in 1..m) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                curr[j] = minOf(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            val tmp = prev
            prev = curr
            curr = tmp
        }
        return prev[m]
    }

    private fun runOcrDeviceBenchmark() {
        mainScope.launch(Dispatchers.Default) {
            try {
                val extBench = File(getExternalFilesDir(null), "ocr_bench")
                val benchRoot = if (extBench.exists()) extBench else File("/sdcard/Download/ocr_bench")
                if (!benchRoot.exists()) {
                    android.util.Log.e("OcrBenchmark", "Bench directory not found: ${benchRoot.absolutePath}")
                    return@launch
                }
                val workDir = File(cacheDir, "ocr_bench_work").apply { mkdirs() }
                val fastDir = File(workDir, "fast").apply { File(this, "tessdata").mkdirs() }
                val bestDir = File(workDir, "best").apply { File(this, "tessdata").mkdirs() }

                // Copy tessdata files from /sdcard/Download/ocr_bench/
                File(benchRoot, "fast_ara.traineddata").copyTo(File(fastDir, "tessdata/ara.traineddata"), overwrite = true)
                File(benchRoot, "eng.traineddata").copyTo(File(fastDir, "tessdata/eng.traineddata"), overwrite = true)
                File(benchRoot, "best_ara.traineddata").copyTo(File(bestDir, "tessdata/ara.traineddata"), overwrite = true)
                File(benchRoot, "eng.traineddata").copyTo(File(bestDir, "tessdata/eng.traineddata"), overwrite = true)

                val samples = listOf(
                    "sample1_arabic_clean" to "ara",
                    "sample2_arabic_skewed_noisy" to "ara",
                    "sample3_english_clean" to "eng",
                    "sample4_mixed_ara_eng_numbers" to "ara+eng",
                    "sample5_table_invoice" to "ara+eng"
                )

                val configs = listOf(
                    Triple("fast_no_prep", fastDir.absolutePath, "NONE"),
                    Triple("fast_legacy_prep", fastDir.absolutePath, "LEGACY"),
                    Triple("fast_improved_prep", fastDir.absolutePath, "IMPROVED"),
                    Triple("best_improved_prep", bestDir.absolutePath, "IMPROVED")
                )

                android.util.Log.i("OcrBenchmark", "=== OCR_BENCHMARK_START ===")
                for ((cfgName, dataPath, prepMode) in configs) {
                    var sumCer = 0.0
                    var sumWer = 0.0
                    var sumMs = 0L
                    for ((sampleName, lang) in samples) {
                        val imgFile = File(benchRoot, "$sampleName.png")
                        val gtFile = File(benchRoot, "$sampleName.txt")
                        val gtRaw = gtFile.readText(Charsets.UTF_8)
                        val gtNorm = normalizeOcrText(gtRaw)

                        val t0 = SystemClock.elapsedRealtime()
                        val targetImgPath = when (prepMode) {
                            "LEGACY" -> {
                                val out = File(workDir, "${sampleName}_legacy.jpg")
                                ImageFilters.preprocessForOcrLegacy(imgFile.absolutePath, out.absolutePath)
                                out.absolutePath
                            }
                            "IMPROVED" -> {
                                val out = File(workDir, "${sampleName}_improved.png")
                                ImageFilters.preprocessForOcr(imgFile.absolutePath, out.absolutePath)
                                out.absolutePath
                            }
                            else -> imgFile.absolutePath
                        }

                        val tess = TessBaseAPI()
                        tess.init(dataPath, lang, TessBaseAPI.OEM_LSTM_ONLY)
                        tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
                        if (prepMode == "IMPROVED") {
                            tess.setVariable("user_defined_dpi", "300")
                            tess.setVariable("preserve_interword_spaces", "1")
                        }
                        val bmp = BitmapFactory.decodeFile(targetImgPath)
                        tess.setImage(bmp)
                        val predRaw = tess.utF8Text ?: ""
                        bmp?.recycle()
                        tess.recycle()
                        val elapsedMs = SystemClock.elapsedRealtime() - t0

                        val predNorm = normalizeOcrText(predRaw)
                        val gtChars = gtNorm.map { it.toString() }
                        val predChars = predNorm.map { it.toString() }
                        val charDist = levenshteinDistance(gtChars, predChars)
                        val cer = (charDist.toDouble() / gtChars.size.coerceAtLeast(1).toDouble()) * 100.0

                        val gtWords = gtNorm.split(" ").filter { it.isNotEmpty() }
                        val predWords = predNorm.split(" ").filter { it.isNotEmpty() }
                        val wordDist = levenshteinDistance(gtWords, predWords)
                        val wer = (wordDist.toDouble() / gtWords.size.coerceAtLeast(1).toDouble()) * 100.0

                        sumCer += cer
                        sumWer += wer
                        sumMs += elapsedMs

                        android.util.Log.i(
                            "OcrBenchmark",
                            String.format(
                                java.util.Locale.US,
                                "ROW | %s | %s | CER=%.2f%% | WER=%.2f%% | TIME=%dms | GT_LEN=%d | PRED_PREVIEW=%s",
                                cfgName, sampleName, cer, wer, elapsedMs, gtChars.size, predNorm.take(60)
                            )
                        )
                    }
                    android.util.Log.i(
                        "OcrBenchmark",
                        String.format(
                            java.util.Locale.US,
                            "AVG | %s | AVG_CER=%.2f%% | AVG_WER=%.2f%% | AVG_TIME=%dms",
                            cfgName, sumCer / samples.size, sumWer / samples.size, sumMs / samples.size
                        )
                    )
                }
                android.util.Log.i("OcrBenchmark", "=== OCR_BENCHMARK_DONE ===")
            } catch (e: Exception) {
                android.util.Log.e("OcrBenchmark", "Benchmark failed", e)
            }
        }
    }

    override fun onDestroy() {
        replyScannerResult { it.success(null) }
        try {
            tts?.stop()
            tts?.shutdown()
            tts = null
        } catch (_: Exception) {}
        mainScope.cancel()
        super.onDestroy()
    }
}