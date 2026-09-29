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
    private val REQUEST_CODE_SCANNER = 0x534341
    private var pendingScannerResult: MethodChannel.Result? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)
    private val nativeOpSemaphore = java.util.concurrent.Semaphore(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!OpenCVLoader.initLocal()) {
            android.util.Log.e("MainActivity", "OpenCV init failed")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, docScannerChannel)
            .setMethodCallHandler { call, result ->
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
                                    val tempOut = File(cacheDir, "ocr_prep_${System.currentTimeMillis()}.jpg")
                                    if (ImageFilters.preprocessForOcr(imagePath, tempOut.absolutePath)) {
                                        prepFile = tempOut
                                        tempOut.absolutePath
                                    } else {
                                        imagePath
                                    }
                                } else {
                                    imagePath
                                }

                                val initialized = tess.init(dataPath, language, TessBaseAPI.OEM_DEFAULT)
                                if (!initialized) {
                                    withContext(Dispatchers.Main) {
                                        result.error("TESS_INIT_FAIL", "Failed to initialize Tesseract ($language) at $dataPath", null)
                                    }
                                    return@launch
                                }
                                tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO

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
                    else -> result.notImplemented()
                }
            }
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

    private fun extractIncomingFilesFromIntent(incoming: Intent?): List<String> {
        if (incoming == null) return emptyList()
        val uris = ArrayList<android.net.Uri>()
        when (incoming.action) {
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
            Intent.ACTION_VIEW -> {
                val dataUri = incoming.data
                if (dataUri != null) uris.add(dataUri)
            }
        }
        val copiedPaths = ArrayList<String>()
        for ((idx, uri) in uris.withIndex()) {
            try {
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

    override fun onDestroy() {
        replyScannerResult { it.success(null) }
        mainScope.cancel()
        super.onDestroy()
    }
}