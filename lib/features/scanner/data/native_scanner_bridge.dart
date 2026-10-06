import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/services/permission_request_coordinator.dart';

/// Represents the captured scan result returned from the native camera.
class NativeScannerResult {
  const NativeScannerResult({
    required this.path,
    required this.corners,
    required this.width,
    required this.height,
  });

  /// File path to the captured JPEG on disk.
  final String path;

  /// 8 normalized coordinates [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
  /// in the range [0.0, 1.0], ordered Top-Left, Top-Right, Bottom-Right, Bottom-Left,
  /// relative to the UPRIGHT portrait image.
  final List<double> corners;

  /// Upright pixel width.
  final int width;

  /// Upright pixel height.
  final int height;

  factory NativeScannerResult.fromMap(Map<dynamic, dynamic> map) {
    final rawCorners = (map['corners'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    return NativeScannerResult(
      path: map['path'] as String? ?? '',
      corners: rawCorners,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class ScannerPermissionDeniedException implements Exception {
  const ScannerPermissionDeniedException({
    required this.permission,
    this.permanentlyDenied = false,
  });

  final String permission;
  final bool permanentlyDenied;

  @override
  String toString() {
    if (permanentlyDenied) {
      return 'تم رفض إذن $permission نهائيًا. افتح إعدادات التطبيق واسمح به.';
    }
    return 'لم يتم منح إذن $permission.';
  }
}

/// Global reusable dialog to prompt user if scanner permission is denied.
Future<void> showScannerPermissionDialog(
  BuildContext context,
  ScannerPermissionDeniedException error,
) {
  final isPermanent = error.permanentlyDenied;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.photo_camera_front_rounded,
          color: Colors.red,
          size: 40,
        ),
      ),
      title: const Text(
        'الصلاحية مطلوبة للمسح',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text(
        isPermanent
            ? 'يحتاج التطبيق إذن الوصول إلى الكاميرا (${error.permission}).\n\nتم رفض الإذن سابقاً من إعدادات النظام، يرجى فتح الإعدادات وتفعيله يدوياً.'
            : 'يحتاج التطبيق إلى إذن الوصول إلى الكاميرا (${error.permission}) لتتمكن من مسح الصفحات والمستندات واستيرادها بنجاح.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('إلغاء'),
        ),
        if (isPermanent)
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('فتح الإعدادات'),
          ),
      ],
    ),
  );
}

/// Cross-Platform Native Scanner Channel Contract: "ismart/doc_scanner"
/// -------------------------------------------------------------------
/// This class defines the unified API for document scanning across platforms
/// (Android implementation active; iOS will implement this identical interface).
///
/// Principles & Invariants:
/// 1. Methods:
///    - `startScan({String? destDir, bool batch = false})` -> returns list of [NativeScannerResult] (empty if cancelled).
///    - `startSingleScan({String? destDir})` -> returns single [NativeScannerResult] or null if cancelled.
///    - `warp({required String path, required List<double> corners, required String outPath, int? maxSide})`
///    - `applyFilter({required String path, required String filter, required String outPath, int maxSide = 0})`
///    - `rotateLeft({required String path, required String outPath})`
/// 2. Data flow:
///    - Only file paths are exchanged across the channel; image bytes and Base64 are NEVER passed.
///    - The raw captured image file is written directly to disk and retains upright orientation
///      when read by an EXIF-honoring reader.
/// 3. Coordinates:
///    - `corners` always contains exactly 8 doubles in the order:
///      [TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y], normalized to [0.0, 1.0]
///      relative to the upright image dimensions.
/// 4. Performance & Scalability:
///    - `warp` accepts optional `maxSide` to allow instant preview rectification (<=1600px)
///      without full-resolution overhead. Full-resolution warp is executed only when saving.
///    - Native memory is explicitly managed and released on the native side.
class NativeScannerBridge {
  static const MethodChannel _channel = MethodChannel('ismart/doc_scanner');

  /// Starts the embedded high-performance native camera activity/view.
  /// When [batch] is true, camera remains open for sequential captures.
  /// Returns a list of [NativeScannerResult] (empty if cancelled).
  static Future<List<NativeScannerResult>> startScan({
    String? destDir,
    bool batch = false,
  }) async {
    // 1. Ensure Camera permission is requested and granted
    final cameraStatus = await PermissionRequestCoordinator.run(
      Permission.camera.request,
    );
    if (!cameraStatus.isGranted) {
      debugPrint('[NativeScannerBridge] Camera permission not granted ($cameraStatus)');
      throw ScannerPermissionDeniedException(
        permission: 'الكاميرا',
        permanentlyDenied:
            cameraStatus.isPermanentlyDenied || cameraStatus.isRestricted,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startScan',
        {
          'destDir': destDir,
          'batch': batch,
        },
      );
      debugPrint('[NativeScannerBridge] startScan completed in ${sw.elapsedMilliseconds}ms');
      if (result == null) return const [];

      final isBatch = result['batch'] == true;
      if (isBatch) {
        final items = result['items'] as List<dynamic>? ?? const [];
        return items
            .map((item) => NativeScannerResult.fromMap(item as Map<dynamic, dynamic>))
            .toList();
      } else {
        return [NativeScannerResult.fromMap(result)];
      }
    } catch (e) {
      debugPrint('[NativeScannerBridge] startScan failed: $e');
      rethrow;
    }
  }

  /// Convenience method for single document capture.
  static Future<NativeScannerResult?> startSingleScan({String? destDir}) async {
    final results = await startScan(destDir: destDir, batch: false);
    return results.isNotEmpty ? results.first : null;
  }

  /// Warps a document quadrilateral defined by 8 normalized corners
  /// [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y] and writes the perspective-rectified
  /// image to [outPath].
  ///
  /// Optional [maxSide] limits the destination resolution for cheap preview rendering (e.g. 1600).
  /// Omit [maxSide] (or pass 0) for full-resolution final output.
  ///
  /// Optional [quarterTurns] (0..3, counter-clockwise) rotates the rectified Mat in-memory
  /// before saving to [outPath], reducing save passes to warp(+rotation) -> filter.
  static Future<String> warp({
    required String path,
    required List<double> corners,
    required String outPath,
    int? maxSide,
    int quarterTurns = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('warp', {
        'path': path,
        'corners': corners,
        'outPath': outPath,
        if (maxSide != null && maxSide > 0) 'maxSide': maxSide,
        if (quarterTurns > 0) 'quarterTurns': quarterTurns,
      }).timeout(const Duration(seconds: 20));
      debugPrint('[NativeScannerBridge] warp completed in ${sw.elapsedMilliseconds}ms -> $outPath (maxSide=$maxSide, quarterTurns=$quarterTurns)');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] warp failed: $e');
      rethrow;
    }
  }

  /// Applies one of the native document filters:
  /// 'enhance', 'lighten', 'gray', 'eco', 'no_handwriting', 'original'.
  /// Optional [maxSide] downscales the image during filtering (e.g. 200 for thumbnails, 1600 for preview).
  static Future<String> applyFilter({
    required String path,
    required String filter,
    required String outPath,
    int maxSide = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('applyFilter', {
        'path': path,
        'filter': filter,
        'maxSide': maxSide,
        'outPath': outPath,
      }).timeout(const Duration(seconds: 20));
      debugPrint('[NativeScannerBridge] applyFilter ($filter, maxSide=$maxSide) completed in ${sw.elapsedMilliseconds}ms -> $outPath');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] applyFilter failed: $e');
      rethrow;
    }
  }

  /// Rotates an image 90 degrees counter-clockwise natively.
  static Future<String> rotateLeft({
    required String path,
    required String outPath,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<String>('rotateLeft', {
        'path': path,
        'outPath': outPath,
      }).timeout(const Duration(seconds: 20));
      debugPrint('[NativeScannerBridge] rotateLeft completed in ${sw.elapsedMilliseconds}ms -> $outPath');
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] rotateLeft failed: $e');
      rethrow;
    }
  }

  /// Composites a PNG signature natively onto a page JPEG using platform Canvas/Bitmap,
  /// capping the output at [maxSide] (default 2048px) so PdfBuilderService hits its 0ms fast path.
  static Future<Uint8List?> compositeSignature({
    required String pagePath,
    required Uint8List signatureBytes,
    required double relativeX,
    required double relativeY,
    required double relativeWidth,
    int maxSide = 2048,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod<Uint8List>('compositeSignature', {
        'pagePath': pagePath,
        'signatureBytes': signatureBytes,
        'relX': relativeX,
        'relY': relativeY,
        'relW': relativeWidth,
        'maxSide': maxSide,
      }).timeout(const Duration(seconds: 15));
      debugPrint('[NativeScannerBridge] compositeSignature completed in ${sw.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      debugPrint('[NativeScannerBridge] compositeSignature fallback to Dart isolate ($e)');
      return null;
    }
  }

  /// Preprocesses a document image specifically for high-accuracy Arabic/English OCR
  /// (upscaling to ~300 DPI, illumination flattening, denoise, deskew, adaptive binarization).
  static Future<String> preprocessForOcr({
    required String path,
    required String outPath,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('preprocessForOcr', {
        'path': path,
        'outPath': outPath,
      }).timeout(const Duration(seconds: 20));
      return result ?? outPath;
    } catch (e) {
      debugPrint('[NativeScannerBridge] preprocessForOcr fallback to original path: $e');
      return path;
    }
  }

  /// Enables or disables Android FLAG_SECURE to hide app screen in Recent Apps switcher.
  static Future<void> setSecureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('setSecureScreen', {'enabled': enabled});
    } catch (_) {}
  }

  /// Runs offline Tesseract 4/5 LSTM OCR natively via JNI (`TessBaseAPI`).
  /// Supports `ara`, `eng`, and `ara+eng`.
  static Future<Map<String, dynamic>?> runTesseractOcr({
    required String imagePath,
    required String dataPath,
    String language = 'ara+eng',
    bool preprocess = true,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'runTesseractOcr',
        {
          'imagePath': imagePath,
          'dataPath': dataPath,
          'language': language,
          'preprocess': preprocess,
        },
      ).timeout(const Duration(seconds: 45));
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('[NativeScannerBridge] runTesseractOcr failed: $e');
      return null;
    }
  }

  /// Consumes incoming files shared or opened from external apps (ACTION_SEND / ACTION_VIEW).
  static Future<List<String>> consumeIncomingFiles() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('consumeIncomingFiles');
      if (res == null) return const [];
      return res.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Detects 4 document corners natively from an image file on disk.
  /// Returns 8 normalized doubles [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
  /// or an empty list if no clear document quadrilateral was detected.
  static Future<List<double>> detectCorners(String path) async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('detectCorners', {
        'path': path,
      });
      if (res == null) return const [];
      return res.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      debugPrint('[NativeScannerBridge] detectCorners error: $e');
      return const [];
    }
  }

  /// Evaluates document blurriness natively using Laplacian variance.
  /// Returns `isBlurry: true` if variance is below sharpness threshold (~80.0).
  static Future<({bool isBlurry, double variance})> checkBlur(String imagePath) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkBlur', {
        'path': imagePath,
      });
      if (res == null) return (isBlurry: false, variance: 999.0);
      return (
        isBlurry: res['isBlurry'] == true,
        variance: (res['variance'] as num?)?.toDouble() ?? 999.0,
      );
    } catch (e) {
      debugPrint('[NativeScannerBridge] checkBlur error: $e');
      return (isBlurry: false, variance: 999.0);
    }
  }

  /// Splits a 2-page book spread vertically down the center into 2 pages.
  /// Follows Arabic RTL order: Page 1 = Right half, Page 2 = Left half.
  static Future<({String pageRight, String pageLeft})?> splitBookPage({
    required String path,
    required String outRightPath,
    required String outLeftPath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('splitBookPage', {
        'path': path,
        'outRightPath': outRightPath,
        'outLeftPath': outLeftPath,
      });
      if (res == null) return null;
      return (
        pageRight: res['pageRight'] as String? ?? outRightPath,
        pageLeft: res['pageLeft'] as String? ?? outLeftPath,
      );
    } catch (e) {
      debugPrint('[NativeScannerBridge] splitBookPage error: $e');
      return null;
    }
  }

  /// Offline Text-to-Speech (TTS) reading using Android built-in speech engine.
  static Future<bool> speakText(String text, {String lang = 'ar'}) async {
    try {
      final res = await _channel.invokeMethod<bool>('speakText', {
        'text': text,
        'lang': lang,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeScannerBridge] speakText error: $e');
      return false;
    }
  }

  /// Stops any currently playing speech.
  static Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
  }
}


