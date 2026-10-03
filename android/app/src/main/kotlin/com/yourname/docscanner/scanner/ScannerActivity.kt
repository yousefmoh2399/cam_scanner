package com.yourname.docscanner.scanner

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.hypot

class ScannerActivity : ComponentActivity() {

    companion object {
        private const val TAG = "DocScan"
        const val EXTRA_DEST_DIR = "extra_dest_dir"
        const val EXTRA_BATCH_MODE = "extra_batch_mode"
        const val RESULT_PATH = "result_path"
        const val RESULT_CORNERS = "result_corners" // DoubleArray of 8 normalized coords
        const val RESULT_WIDTH = "result_width"
        const val RESULT_HEIGHT = "result_height"
        const val RESULT_BATCH_LIST = "result_batch_list"

        private const val AUTO_SHUTTER_STABLE_FRAMES = 14
        private const val AUTO_SHUTTER_COOLDOWN_MS = 1800L
    }

    private lateinit var cameraExecutor: ExecutorService
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var previewView: PreviewView? = null
    private var overlayView: QuadOverlayView? = null
    private var flashOverlayView: View? = null
    private var flashButton: ImageButton? = null
    private var modeToggleButton: TextView? = null
    private var autoShutterButton: TextView? = null
    private var hintBanner: TextView? = null
    private var doneButton: TextView? = null
    private var shutterButton: View? = null

    private var destinationDir: String? = null
    private var isTorchOn = false
    private var isBatchMode = false
    private var isAutoShutterEnabled = true
    private var stableFrameCount = 0
    private val batchItems = ArrayList<Bundle>()
    private val isCapturing = AtomicBoolean(false)
    private val pendingCaptureRequest = AtomicBoolean(false)
    @Volatile
    private var lastShutterTime = 0L
    @Volatile
    private var shutterTapTime = 0L

    // Analyzer timing metrics
    private var analyzerFrameCount = 0
    private var analyzerTotalTimeMs = 0L

    // Live quad tracking state
    @Volatile
    private var latestNormalizedQuad: List<Point>? = null
    private var previousQuad: List<Point>? = null
    private var missedFrameCount = 0

    private val pickSingleLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            importImagesFromGallery(listOf(uri))
        }
    }

    private val pickMultipleLauncher = registerForActivityResult(
        ActivityResultContracts.GetMultipleContents()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            importImagesFromGallery(uris)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Camera permission missing, finishing with RESULT_CANCELED")
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }

        if (!OpenCVLoader.initLocal()) {
            Log.e(TAG, "OpenCVLoader.initLocal() failed")
        }

        destinationDir = intent.getStringExtra(EXTRA_DEST_DIR) ?: cacheDir.absolutePath
        isBatchMode = intent.getBooleanExtra(EXTRA_BATCH_MODE, false)
        cameraExecutor = Executors.newSingleThreadExecutor()

        buildUi()
        startCamera()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // AspectFrameLayout maintaining 3:4 portrait ratio (4:3 camera sensor)
        val aspectContainer = AspectRatioFrameLayout(this, 3.0f / 4.0f).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        }

        previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        aspectContainer.addView(previewView)

        overlayView = QuadOverlayView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        aspectContainer.addView(overlayView)

        flashOverlayView = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.WHITE)
            alpha = 0f
            visibility = View.GONE
        }
        aspectContainer.addView(flashOverlayView)
        root.addView(aspectContainer)

        // Top control bar
        val topBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(76),
                Gravity.TOP
            )
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        val closeButton = ImageButton(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.START or Gravity.CENTER_VERTICAL)
            setBackgroundColor(Color.TRANSPARENT)
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(Color.WHITE)
            setOnClickListener {
                handleBackOrClose()
            }
        }
        topBar.addView(closeButton)

        // Center pills container: Batch/Single toggle + Auto-Shutter toggle
        val centerPills = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        modeToggleButton = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(36)
            ).apply {
                marginEnd = dp(8)
            }
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(4), dp(14), dp(4))
            text = if (isBatchMode) "دفعة" else "مفرد"
            setTextColor(Color.WHITE)
            textSize = 13.5f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            val bg = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#80000000"))
                setStroke(dp(1), Color.parseColor("#80FFFFFF"))
            }
            background = bg
            setOnClickListener {
                isBatchMode = !isBatchMode
                text = if (isBatchMode) "دفعة" else "مفرد"
                updateDoneButtonState()
            }
        }
        centerPills.addView(modeToggleButton)

        autoShutterButton = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(36)
            )
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(4), dp(14), dp(4))
            text = if (isAutoShutterEnabled) "تلقائي ⚡" else "يدوي"
            setTextColor(if (isAutoShutterEnabled) Color.BLACK else Color.WHITE)
            textSize = 13.5f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            background = buildAutoShutterBg(isAutoShutterEnabled)
            setOnClickListener {
                isAutoShutterEnabled = !isAutoShutterEnabled
                stableFrameCount = 0
                overlayView?.setAutoShutterProgress(0f)
                text = if (isAutoShutterEnabled) "تلقائي ⚡" else "يدوي"
                setTextColor(if (isAutoShutterEnabled) Color.BLACK else Color.WHITE)
                background = buildAutoShutterBg(isAutoShutterEnabled)
                updateHintBanner(null)
            }
        }
        centerPills.addView(autoShutterButton)
        topBar.addView(centerPills)

        flashButton = ImageButton(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.END or Gravity.CENTER_VERTICAL)
            setBackgroundColor(Color.TRANSPARENT)
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(Color.WHITE)
            setOnClickListener { toggleFlash() }
        }
        topBar.addView(flashButton)
        root.addView(topBar)

        // Status / Auto-Shutter hint banner below top bar
        hintBanner = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            ).apply {
                topMargin = dp(82)
            }
            setPadding(dp(16), dp(6), dp(16), dp(6))
            text = "وجّه الكاميرا نحو المستند"
            setTextColor(Color.WHITE)
            textSize = 13f
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#88000000"))
            }
        }
        root.addView(hintBanner)

        // Bottom control bar with shutter button
        val bottomBar = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(120),
                Gravity.BOTTOM
            )
            setBackgroundColor(Color.parseColor("#44000000"))
        }

        val galleryButton = ImageButton(this).apply {
            val size = dp(48)
            layoutParams = FrameLayout.LayoutParams(size, size, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                marginStart = dp(24)
            }
            setImageResource(android.R.drawable.ic_menu_gallery)
            setColorFilter(Color.WHITE)
            val bg = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.parseColor("#55000000"))
                setStroke(dp(1), Color.parseColor("#80FFFFFF"))
            }
            background = bg
            setOnClickListener {
                if (isBatchMode) {
                    pickMultipleLauncher.launch("image/*")
                } else {
                    pickSingleLauncher.launch("image/*")
                }
            }
        }
        bottomBar.addView(galleryButton)

        shutterButton = View(this).apply {
            val size = dp(74)
            layoutParams = FrameLayout.LayoutParams(size, size, Gravity.CENTER)
            val outerBorder = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(dp(4), Color.parseColor("#00E676"))
            }
            background = outerBorder
            setOnClickListener { takeShutterPicture() }
        }
        bottomBar.addView(shutterButton)

        doneButton = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(44),
                Gravity.END or Gravity.CENTER_VERTICAL
            ).apply {
                marginEnd = dp(20)
            }
            setPadding(dp(16), dp(8), dp(16), dp(8))
            text = "تم (${batchItems.size})"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            val bg = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(Color.parseColor("#00C853"))
            }
            background = bg
            visibility = if (isBatchMode && batchItems.isNotEmpty()) View.VISIBLE else View.GONE
            setOnClickListener {
                finishWithBatch()
            }
        }
        bottomBar.addView(doneButton)
        root.addView(bottomBar)

        setContentView(root)
    }

    private fun buildAutoShutterBg(enabled: Boolean): android.graphics.drawable.GradientDrawable {
        return android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = dp(18).toFloat()
            if (enabled) {
                setColor(Color.parseColor("#00E676"))
                setStroke(dp(1), Color.parseColor("#00E676"))
            } else {
                setColor(Color.parseColor("#80000000"))
                setStroke(dp(1), Color.parseColor("#80FFFFFF"))
            }
        }
    }

    private fun updateHintBanner(customText: String?) {
        val label = customText ?: if (latestNormalizedQuad != null) {
            if (isAutoShutterEnabled) "اثبت قليلاً للالتقاط التلقائي..." else "تم كشف الحواف • اضغط للالتقاط"
        } else {
            "وجّه الكاميرا نحو الورقة لكشف الحواف"
        }
        if (hintBanner?.text != label) {
            hintBanner?.text = label
        }
    }

    private fun importImagesFromGallery(uris: List<Uri>) {
        if (uris.isEmpty()) return
        cameraExecutor.execute {
            try {
                val destFolder = File(destinationDir!!)
                destFolder.mkdirs()

                for (uri in uris) {
                    val fileName = "raw_${UUID.randomUUID()}.jpg"
                    val outputFile = File(destFolder, fileName)

                    contentResolver.openInputStream(uri)?.use { input ->
                        outputFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }

                    if (!outputFile.exists() || outputFile.length() == 0L) continue

                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(outputFile.absolutePath, options)
                    val rawWidth = options.outWidth
                    val rawHeight = options.outHeight

                    if (rawWidth <= 0 || rawHeight <= 0) {
                        outputFile.delete()
                        continue
                    }

                    val exif = ExifInterface(outputFile.absolutePath)
                    val orientation = exif.getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL
                    )

                    val isRotated90 = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                            orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                            orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                            orientation == ExifInterface.ORIENTATION_TRANSVERSE

                    val uprightWidth = if (isRotated90) rawHeight else rawWidth
                    val uprightHeight = if (isRotated90) rawWidth else rawHeight

                    val src = Imgcodecs.imread(outputFile.absolutePath, Imgcodecs.IMREAD_COLOR)
                    val detectedCorners = if (!src.empty()) {
                        val gray = Mat()
                        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)
                        val quad = DocumentDetector.findQuad(gray)
                        gray.release()
                        src.release()
                        quad?.map { Point(it.x / uprightWidth.toDouble(), it.y / uprightHeight.toDouble()) }
                    } else {
                        null
                    }

                    val finalCorners = detectedCorners ?: listOf(
                        Point(0.05, 0.05),
                        Point(0.95, 0.05),
                        Point(0.95, 0.95),
                        Point(0.05, 0.95)
                    )

                    val cornersArray = DoubleArray(8)
                    cornersArray[0] = finalCorners[0].x
                    cornersArray[1] = finalCorners[0].y
                    cornersArray[2] = finalCorners[1].x
                    cornersArray[3] = finalCorners[1].y
                    cornersArray[4] = finalCorners[2].x
                    cornersArray[5] = finalCorners[2].y
                    cornersArray[6] = finalCorners[3].x
                    cornersArray[7] = finalCorners[3].y

                    val pageBundle = Bundle().apply {
                        putString(RESULT_PATH, outputFile.absolutePath)
                        putDoubleArray(RESULT_CORNERS, cornersArray)
                        putInt(RESULT_WIDTH, uprightWidth)
                        putInt(RESULT_HEIGHT, uprightHeight)
                    }

                    if (isBatchMode) {
                        synchronized(batchItems) {
                            batchItems.add(pageBundle)
                        }
                    } else {
                        val resultIntent = Intent().apply {
                            putExtra(RESULT_PATH, outputFile.absolutePath)
                            putExtra(RESULT_CORNERS, cornersArray)
                            putExtra(RESULT_WIDTH, uprightWidth)
                            putExtra(RESULT_HEIGHT, uprightHeight)
                        }
                        runOnUiThread {
                            setResult(Activity.RESULT_OK, resultIntent)
                            finish()
                        }
                        return@execute
                    }
                }

                if (isBatchMode) {
                    runOnUiThread {
                        updateDoneButtonState()
                        overlayView?.animate()
                            ?.alpha(0.2f)
                            ?.setDuration(70)
                            ?.withEndAction {
                                overlayView?.animate()?.alpha(1.0f)?.setDuration(100)?.start()
                            }?.start()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to import images from gallery", e)
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()
                .also {
                    it.setSurfaceProvider(previewView?.surfaceProvider)
                }

            imageCapture = ImageCapture.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .setJpegQuality(95)
                .build()

            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                analyzePreviewFrame(imageProxy)
            }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                camera = cameraProvider.bindToLifecycle(
                    this,
                    cameraSelector,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
            } catch (exc: Exception) {
                Log.e(TAG, "Camera binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun toggleFlash() {
        val cam = camera ?: return
        if (!cam.cameraInfo.hasFlashUnit()) return

        isTorchOn = !isTorchOn
        cam.cameraControl.enableTorch(isTorchOn)
        flashButton?.setColorFilter(if (isTorchOn) Color.parseColor("#FFEB3B") else Color.WHITE)
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun analyzePreviewFrame(imageProxy: ImageProxy) {
        val frameStartTime = SystemClock.elapsedRealtime()
        try {
            val yPlane = imageProxy.planes[0]
            val yBuffer = yPlane.buffer
            val rowStride = yPlane.rowStride
            val pixelStride = yPlane.pixelStride
            val width = imageProxy.width
            val height = imageProxy.height

            // Create grayscale Mat from Y-plane
            val yMat = if (rowStride == width && pixelStride == 1) {
                val bytes = ByteArray(yBuffer.remaining())
                yBuffer.get(bytes)
                Mat(height, width, CvType.CV_8UC1).apply {
                    put(0, 0, bytes)
                }
            } else {
                val fullMat = Mat(height, rowStride, CvType.CV_8UC1)
                val bytes = ByteArray(yBuffer.remaining())
                yBuffer.get(bytes)
                fullMat.put(0, 0, bytes)
                val sub = fullMat.submat(0, height, 0, width)
                val result = Mat()
                sub.copyTo(result)
                fullMat.release()
                sub.release()
                result
            }

            // Rotate according to CameraX image rotation
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val rotated = Mat()
            when (rotationDegrees) {
                90 -> Core.rotate(yMat, rotated, Core.ROTATE_90_CLOCKWISE)
                180 -> Core.rotate(yMat, rotated, Core.ROTATE_180)
                270 -> Core.rotate(yMat, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
                else -> yMat.copyTo(rotated)
            }
            yMat.release()

            val detectedQuad = DocumentDetector.findQuad(rotated)
            val rotW = rotated.cols().toDouble()
            val rotH = rotated.rows().toDouble()
            rotated.release()

            if (detectedQuad != null) {
                val prevBeforeSmooth = previousQuad
                val normalized = detectedQuad.map { Point(it.x / rotW, it.y / rotH) }
                val smoothed = smoothQuad(normalized)
                latestNormalizedQuad = smoothed
                missedFrameCount = 0

                // Check corner movement stability for Auto-Shutter
                var maxDelta = 0.0
                if (prevBeforeSmooth != null && prevBeforeSmooth.size == 4) {
                    for (i in 0..3) {
                        val d = hypot(normalized[i].x - prevBeforeSmooth[i].x, normalized[i].y - prevBeforeSmooth[i].y)
                        if (d > maxDelta) maxDelta = d
                    }
                }

                val now = SystemClock.elapsedRealtime()
                val cooldownElapsed = (now - lastShutterTime) >= AUTO_SHUTTER_COOLDOWN_MS
                if (isAutoShutterEnabled && !isCapturing.get() && cooldownElapsed && maxDelta < 0.04) {
                    stableFrameCount++
                } else if (maxDelta >= 0.06) {
                    stableFrameCount = 0
                }

                val progress = if (isAutoShutterEnabled) {
                    (stableFrameCount.toFloat() / AUTO_SHUTTER_STABLE_FRAMES.toFloat()).coerceIn(0f, 1f)
                } else {
                    0f
                }

                val shouldTriggerAutoShutter = isAutoShutterEnabled &&
                        stableFrameCount >= AUTO_SHUTTER_STABLE_FRAMES &&
                        !isCapturing.get() &&
                        cooldownElapsed

                if (shouldTriggerAutoShutter) {
                    stableFrameCount = 0
                }

                runOnUiThread {
                    overlayView?.setPolygon(smoothed)
                    overlayView?.setAutoShutterProgress(progress)
                    updateHintBanner(null)
                    if (shouldTriggerAutoShutter) {
                        takeShutterPicture()
                    }
                }
            } else {
                missedFrameCount++
                if (missedFrameCount > 5) {
                    latestNormalizedQuad = null
                    previousQuad = null
                    stableFrameCount = 0
                    runOnUiThread {
                        overlayView?.setPolygon(null)
                        overlayView?.setAutoShutterProgress(0f)
                        updateHintBanner(null)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing preview frame", e)
        } finally {
            val frameDuration = SystemClock.elapsedRealtime() - frameStartTime
            analyzerTotalTimeMs += frameDuration
            analyzerFrameCount++
            if (analyzerFrameCount % 30 == 0) {
                val avg = analyzerTotalTimeMs.toDouble() / 30.0
                Log.d(TAG, "Analyzer average time per frame (last 30 frames): ${"%.2f".format(avg)}ms")
                analyzerTotalTimeMs = 0L
            }
            imageProxy.close()
        }
    }

    /**
     * Temporal smoothing with LERP 0.5 and >15% jump reset.
     */
    private fun smoothQuad(newQuad: List<Point>): List<Point> {
        val prev = previousQuad
        if (prev == null || prev.size != 4) {
            previousQuad = newQuad
            return newQuad
        }

        var maxJump = 0.0
        for (i in 0..3) {
            val dist = hypot(newQuad[i].x - prev[i].x, newQuad[i].y - prev[i].y)
            if (dist > maxJump) maxJump = dist
        }

        if (maxJump > 0.15) {
            previousQuad = newQuad
            return newQuad
        }

        val smoothed = ArrayList<Point>(4)
        for (i in 0..3) {
            smoothed.add(
                Point(
                    prev[i].x * 0.5 + newQuad[i].x * 0.5,
                    prev[i].y * 0.5 + newQuad[i].y * 0.5
                )
            )
        }
        previousQuad = smoothed
        return smoothed
    }

    private fun takeShutterPicture() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastShutterTime < 250) {
            return // Shutter debounce 250ms
        }
        if (!isCapturing.compareAndSet(false, true)) {
            // If already capturing previous shot, queue this tap so it's NEVER lost
            pendingCaptureRequest.set(true)
            runOnUiThread {
                shutterButton?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                shutterButton?.animate()?.scaleX(0.88f)?.scaleY(0.88f)?.setDuration(60)?.withEndAction {
                    shutterButton?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(80)?.start()
                }?.start()
                updateHintBanner("جارٍ حفظ اللقطة...")
            }
            return
        }
        lastShutterTime = now
        shutterTapTime = now
        stableFrameCount = 0
        overlayView?.setAutoShutterProgress(0f)

        // Haptic feedback & button bounce animation
        runOnUiThread {
            shutterButton?.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
            shutterButton?.animate()?.scaleX(0.85f)?.scaleY(0.85f)?.setDuration(60)?.withEndAction {
                shutterButton?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(80)?.start()
            }?.start()
            // White shutter flash
            flashOverlayView?.apply {
                alpha = 0.65f
                visibility = View.VISIBLE
                animate().alpha(0f).setDuration(120).withEndAction {
                    visibility = View.GONE
                }.start()
            }
        }

        val capture = imageCapture ?: run {
            isCapturing.set(false)
            return
        }

        // Snapshot current stable live quad
        val liveQuad = latestNormalizedQuad

        capture.takePicture(
            cameraExecutor,
            object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(imageProxy: ImageProxy) {
                    val captureSuccessTime = SystemClock.elapsedRealtime()
                    processCapturedPhoto(imageProxy, liveQuad, shutterTapTime, captureSuccessTime)
                }

                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Capture failed: ${exception.message}", exception)
                    isCapturing.set(false)
                    if (pendingCaptureRequest.compareAndSet(true, false)) {
                        takeShutterPicture()
                    }
                }
            }
        )
    }

    private fun detectCornersFromDownsampledImage(filePath: String): List<Point>? {
        return try {
            val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(filePath, boundsOptions)
            val origW = boundsOptions.outWidth
            val origH = boundsOptions.outHeight
            if (origW <= 0 || origH <= 0) return null

            val maxTarget = 1024
            var sampleSize = 1
            while ((origW / sampleSize) > maxTarget || (origH / sampleSize) > maxTarget) {
                sampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val bmp = BitmapFactory.decodeFile(filePath, decodeOptions) ?: return null
            val bmpW = bmp.width.toDouble()
            val bmpH = bmp.height.toDouble()

            val matBgra = Mat()
            Utils.bitmapToMat(bmp, matBgra)
            bmp.recycle()

            val gray = Mat()
            Imgproc.cvtColor(matBgra, gray, Imgproc.COLOR_BGRA2GRAY)
            matBgra.release()

            val quad = DocumentDetector.findQuad(gray)
            gray.release()

            quad?.map { Point(it.x / bmpW, it.y / bmpH) }
        } catch (e: Exception) {
            Log.e(TAG, "Fast downsampled corner detection fallback failed", e)
            null
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun processCapturedPhoto(
        imageProxy: ImageProxy,
        liveNormalizedQuad: List<Point>?,
        tapTime: Long,
        captureSuccessTime: Long
    ) {
        try {
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val plane = imageProxy.planes[0]
            val buffer = plane.buffer
            val rawBytes = ByteArray(buffer.remaining())
            buffer.get(rawBytes)

            // Direct zero-decode write to disk
            val destFolder = File(destinationDir!!)
            destFolder.mkdirs()
            val fileName = "raw_${UUID.randomUUID()}.jpg"
            val outputFile = File(destFolder, fileName)

            FileOutputStream(outputFile).use { fos ->
                fos.write(rawBytes)
                fos.flush()
            }

            // Write EXIF orientation tag so any reader (including imread) reads it upright
            val exif = ExifInterface(outputFile.absolutePath)
            val exifOrientation = when (rotationDegrees) {
                90 -> ExifInterface.ORIENTATION_ROTATE_90
                180 -> ExifInterface.ORIENTATION_ROTATE_180
                270 -> ExifInterface.ORIENTATION_ROTATE_270
                else -> ExifInterface.ORIENTATION_NORMAL
            }
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, exifOrientation.toString())
            exif.saveAttributes()

            val fileWrittenTime = SystemClock.elapsedRealtime()
            val tapToCaptureMs = captureSuccessTime - tapTime
            val captureToWriteMs = fileWrittenTime - captureSuccessTime
            val totalLatencyMs = fileWrittenTime - tapTime
            Log.d(
                TAG,
                "Shutter timeline: tap->capture=${tapToCaptureMs}ms, capture->written=${captureToWriteMs}ms, total tap->setResult=${totalLatencyMs}ms"
            )

            // Raw sensor dimensions vs upright image dimensions
            val rawWidth = imageProxy.width
            val rawHeight = imageProxy.height
            val uprightWidth = if (rotationDegrees == 90 || rotationDegrees == 270) rawHeight else rawWidth
            val uprightHeight = if (rotationDegrees == 90 || rotationDegrees == 270) rawWidth else rawHeight

            // Resolve final corners (normalized 0.0..1.0 relative to upright image)
            val finalNormalizedCorners: List<Point> = if (liveNormalizedQuad != null) {
                liveNormalizedQuad
            } else {
                val detected = detectCornersFromDownsampledImage(outputFile.absolutePath)
                detected ?: listOf(
                    Point(0.05, 0.05),
                    Point(0.95, 0.05),
                    Point(0.95, 0.95),
                    Point(0.05, 0.95)
                )
            }

            // Format corners array [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
            val cornersArray = DoubleArray(8)
            cornersArray[0] = finalNormalizedCorners[0].x
            cornersArray[1] = finalNormalizedCorners[0].y
            cornersArray[2] = finalNormalizedCorners[1].x
            cornersArray[3] = finalNormalizedCorners[1].y
            cornersArray[4] = finalNormalizedCorners[2].x
            cornersArray[5] = finalNormalizedCorners[2].y
            cornersArray[6] = finalNormalizedCorners[3].x
            cornersArray[7] = finalNormalizedCorners[3].y

            val pageBundle = Bundle().apply {
                putString(RESULT_PATH, outputFile.absolutePath)
                putDoubleArray(RESULT_CORNERS, cornersArray)
                putInt(RESULT_WIDTH, uprightWidth)
                putInt(RESULT_HEIGHT, uprightHeight)
            }

            if (isBatchMode) {
                synchronized(batchItems) {
                    batchItems.add(pageBundle)
                }
                runOnUiThread {
                    updateDoneButtonState()
                    updateHintBanner("تم التقاط الصفحة (${batchItems.size}) بنجاح ✅")
                    overlayView?.animate()
                        ?.alpha(0.2f)
                        ?.setDuration(70)
                        ?.withEndAction {
                            overlayView?.animate()?.alpha(1.0f)?.setDuration(100)?.start()
                        }?.start()
                }
                isCapturing.set(false)
                if (pendingCaptureRequest.compareAndSet(true, false)) {
                    takeShutterPicture()
                }
            } else {
                val resultIntent = Intent().apply {
                    putExtra(RESULT_PATH, outputFile.absolutePath)
                    putExtra(RESULT_CORNERS, cornersArray)
                    putExtra(RESULT_WIDTH, uprightWidth)
                    putExtra(RESULT_HEIGHT, uprightHeight)
                }

                runOnUiThread {
                    setResult(Activity.RESULT_OK, resultIntent)
                    finish()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing captured photo", e)
            isCapturing.set(false)
            if (pendingCaptureRequest.compareAndSet(true, false)) {
                takeShutterPicture()
            }
        } finally {
            imageProxy.close()
        }
    }

    private fun updateDoneButtonState() {
        runOnUiThread {
            doneButton?.apply {
                text = "تم (${batchItems.size})"
                visibility = if (batchItems.isNotEmpty()) View.VISIBLE else View.GONE
            }
        }
    }

    private fun finishWithBatch() {
        if (batchItems.isEmpty()) {
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }
        val resultIntent = Intent().apply {
            putParcelableArrayListExtra(RESULT_BATCH_LIST, batchItems)
        }
        setResult(Activity.RESULT_OK, resultIntent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        handleBackOrClose()
    }

    private fun handleBackOrClose() {
        if (batchItems.isNotEmpty()) {
            showDiscardBatchConfirmDialog()
        } else {
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun showDiscardBatchConfirmDialog() {
        android.app.AlertDialog.Builder(this)
            .setTitle("صفحات غير محفوظة")
            .setMessage("لديك ${batchItems.size} صفحة ممسوحة. هل تريد حفظها ومتابعة الجلسة أم إلغاء الكل؟")
            .setPositiveButton("حفظ ومتابعة") { _, _ ->
                finishWithBatch()
            }
            .setNegativeButton("إلغاء الكل") { _, _ ->
                discardBatchAndFinish()
            }
            .setNeutralButton("البقاء في الكاميرا", null)
            .show()
    }

    private fun discardBatchAndFinish() {
        synchronized(batchItems) {
            for (item in batchItems) {
                val path = item.getString(RESULT_PATH)
                if (path != null) {
                    try {
                        File(path).delete()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to delete temp batch file: $path", e)
                    }
                }
            }
            batchItems.clear()
        }
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density).toInt()
    }
}

/**
 * Custom FrameLayout that enforces a strict target aspect ratio (width / height).
 */
class AspectRatioFrameLayout(
    context: android.content.Context,
    private val targetRatio: Float
) : FrameLayout(context) {

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val originalWidth = MeasureSpec.getSize(widthMeasureSpec)
        val originalHeight = MeasureSpec.getSize(heightMeasureSpec)

        var finalWidth = originalWidth
        var finalHeight = originalHeight

        if (originalWidth > 0 && originalHeight > 0) {
            val currentRatio = originalWidth.toFloat() / originalHeight.toFloat()
            if (currentRatio > targetRatio) {
                finalWidth = (originalHeight * targetRatio).toInt()
            } else {
                finalHeight = (originalWidth / targetRatio).toInt()
            }
        }

        val exactWidth = MeasureSpec.makeMeasureSpec(finalWidth, MeasureSpec.EXACTLY)
        val exactHeight = MeasureSpec.makeMeasureSpec(finalHeight, MeasureSpec.EXACTLY)
        super.onMeasure(exactWidth, exactHeight)
    }
}