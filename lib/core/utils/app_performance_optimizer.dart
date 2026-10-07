import 'dart:io';
import 'package:flutter/material.dart';

/// Performance & Memory Optimizer designed specifically for low-end Android & iOS devices
/// (devices with 1GB - 3GB RAM, low heap limits, or budget chipsets).
///
/// Features:
/// 1. Global ImageCache constraints to prevent Dalvik/ART OOM (Out-Of-Memory) crashes.
/// 2. Downsampled image loading helpers (cacheWidth / cacheHeight) so multi-megapixel camera
///    photos do not decode to 40MB+ uncompressed bitmaps in memory.
/// 3. Memory garbage collection & image eviction helpers.
class AppPerformanceOptimizer with WidgetsBindingObserver {
  AppPerformanceOptimizer._();

  static final AppPerformanceOptimizer _instance = AppPerformanceOptimizer._();
  static bool _isInitialized = false;

  /// Call once at app startup in [main()]
  static void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    final imageCache = PaintingBinding.instance.imageCache;

    // Default Flutter image cache is 1000 images and 100MB+, which causes
    // Out-Of-Memory crashes on low-end devices (1GB - 2GB RAM).
    // Restrict cache count to 100 and max heap to 48MB.
    imageCache.maximumSize = 100;
    imageCache.maximumSizeBytes = 48 * 1024 * 1024; // 48 Megabytes

    // Register lifecycle and memory pressure listener
    WidgetsBinding.instance.addObserver(_instance);

    debugPrint(
      '[AppPerformanceOptimizer] Initialized: maxImages=${imageCache.maximumSize}, maxBytes=${imageCache.maximumSizeBytes ~/ (1024 * 1024)}MB',
    );
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    debugPrint('[AppPerformanceOptimizer] Memory pressure detected from OS! Purging image cache...');
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // Free RAM when user switches apps so low-end OS doesn't kill this process
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
    }
  }

  /// Evict an image file from Flutter's cache to free RAM immediately
  static Future<void> evictFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await FileImage(file).evict();
      }
    } catch (_) {}
  }

  /// Recommended cache widths for different UI scenarios
  static const int thumbnailWidth = 320;
  static const int cardPreviewWidth = 600;
  static const int fullPageWidth = 1440;

  /// Builds a memory-safe [Image.file] widget with downscaled decoding.
  static Widget buildOptimizedFileImage({
    required File file,
    int? cacheWidth,
    int? cacheHeight,
    BoxFit fit = BoxFit.cover,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
    Key? key,
  }) {
    return Image.file(
      file,
      key: key,
      cacheWidth: cacheWidth ?? thumbnailWidth,
      cacheHeight: cacheHeight,
      fit: fit,
      errorBuilder: errorBuilder ??
          (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  size: 28,
                  color: Colors.black26,
                ),
              ),
    );
  }
}
