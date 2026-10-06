import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Preset modes for notebook line and grid removal
enum NotebookPaperType {
  /// Standard lined notebook (single horizontal ruled lines)
  horizontalLined(
    'دفتر مسطر (أفقي)',
    'إزالة خطوط التسطير الأفقية العادية مع الحفاظ على الكتابة اليدوية',
  ),

  /// Graph / grid paper (squared math notebooks)
  mathGrid(
    'ورق رسم بياني ومربعات',
    'إزالة الشبكة والمربعات المتقاطعة (الأفقية والعمودية)',
  ),

  /// Blue / Cyan printed ruling lines (school and college notebooks)
  blueRuled(
    'خطوط زرقاء وسماوية',
    'فصل لوني دقيق لحذف الخطوط المطبوعة باللون الأزرق أو السماوي الفاتح',
  ),

  /// French ruled / Seyès paper (multiple sub-lines)
  frenchRuled(
    'تسطير فرنسي دقيق (Seyès)',
    'إزالة خطوط التسطير المتعددة والخطوط الفرعية الرفيعة',
  );

  const NotebookPaperType(this.label, this.description);
  final String label;
  final String description;
}

/// Configuration parameters for notebook line removal
class NotebookRemovalConfig {
  const NotebookRemovalConfig({
    this.paperType = NotebookPaperType.horizontalLined,
    this.sensitivity = 0.5, // 0.0 to 1.0
    this.preserveColoredInk = true, // Keep red, green, blue pen markings
    this.whitenBackground = true, // Normalize paper background to pristine white
    this.enhanceHandwriting = true, // Boost ink contrast and sharpness
  });

  final NotebookPaperType paperType;
  final double sensitivity;
  final bool preserveColoredInk;
  final bool whitenBackground;
  final bool enhanceHandwriting;
}

/// High-performance 100% offline computer vision service for removing
/// notebook ruling lines and graph paper grids.
class NotebookLinesRemoverService {
  const NotebookLinesRemoverService();

  /// Process image bytes and remove ruling lines/grids in an isolate
  Future<Uint8List> removeNotebookLines({
    required Uint8List inputBytes,
    required NotebookRemovalConfig config,
  }) async {
    return compute(_processIsolate, {
      'bytes': inputBytes,
      'paperType': config.paperType.index,
      'sensitivity': config.sensitivity,
      'preserveColoredInk': config.preserveColoredInk,
      'whitenBackground': config.whitenBackground,
      'enhanceHandwriting': config.enhanceHandwriting,
    });
  }

  /// Process a file from disk and save the result to a new file
  Future<String> processFile({
    required String inputPath,
    required NotebookRemovalConfig config,
  }) async {
    final inputBytes = await File(inputPath).readAsBytes();
    final outputBytes = await removeNotebookLines(
      inputBytes: inputBytes,
      config: config,
    );

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(dir.path, 'clean_notes_$timestamp.png');
    await File(outPath).writeAsBytes(outputBytes, flush: true);
    return outPath;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Isolate Worker
  // ─────────────────────────────────────────────────────────────────────────

  static Uint8List _processIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final paperTypeIdx = params['paperType'] as int;
    final sensitivity = (params['sensitivity'] as num).toDouble();
    final preserveColoredInk = params['preserveColoredInk'] as bool;
    final whitenBackground = params['whitenBackground'] as bool;
    final enhanceHandwriting = params['enhanceHandwriting'] as bool;

    final paperType = NotebookPaperType.values[paperTypeIdx];

    final original = img.decodeImage(rawBytes);
    if (original == null) return rawBytes;

    // Work on full image or create processed copy
    final result = img.Image.from(original);

    // 1. Calculate dominant paper background color (sampling brightest regions)
    final bg = _samplePaperBackground(original);

    // 2. Identify and remove ruling lines based on chosen paper type
    switch (paperType) {
      case NotebookPaperType.horizontalLined:
      case NotebookPaperType.frenchRuled:
        _removeHorizontalLines(
          original: original,
          result: result,
          bgColor: bg,
          sensitivity: sensitivity,
          preserveColoredInk: preserveColoredInk,
          isFrenchRuled: paperType == NotebookPaperType.frenchRuled,
        );
        break;

      case NotebookPaperType.mathGrid:
        _removeOrthogonalGrid(
          original: original,
          result: result,
          bgColor: bg,
          sensitivity: sensitivity,
          preserveColoredInk: preserveColoredInk,
        );
        break;

      case NotebookPaperType.blueRuled:
        _removeBlueCyanLines(
          original: original,
          result: result,
          bgColor: bg,
          sensitivity: sensitivity,
          preserveColoredInk: preserveColoredInk,
        );
        break;
    }

    // 3. Optional paper background whitening and ink sharpening
    if (whitenBackground || enhanceHandwriting) {
      _applyPostEnhancement(
        result,
        whitenBackground: whitenBackground,
        enhanceHandwriting: enhanceHandwriting,
        paperBg: bg,
      );
    }

    return Uint8List.fromList(img.encodePng(result));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core Image Processing Algorithms
  // ─────────────────────────────────────────────────────────────────────────

  /// Samples the predominant paper background tone
  static ({int r, int g, int b, int lum}) _samplePaperBackground(img.Image image) {
    final w = image.width;
    final h = image.height;
    int sumR = 0, sumG = 0, sumB = 0, count = 0;

    const step = 6;
    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        final p = image.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        // Discard dark ink strokes
        if (lum > 170) {
          sumR += p.r.toInt();
          sumG += p.g.toInt();
          sumB += p.b.toInt();
          count++;
        }
      }
    }

    if (count == 0) {
      return (r: 255, g: 255, b: 255, lum: 255);
    }

    final r = (sumR / count).round().clamp(210, 255);
    final g = (sumG / count).round().clamp(210, 255);
    final b = (sumB / count).round().clamp(210, 255);
    final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
    return (r: r, g: g, b: b, lum: lum);
  }

  /// Removes horizontal notebook lines while preserving overlapping handwriting strokes
  static void _removeHorizontalLines({
    required img.Image original,
    required img.Image result,
    required ({int r, int g, int b, int lum}) bgColor,
    required double sensitivity,
    required bool preserveColoredInk,
    required bool isFrenchRuled,
  }) {
    final w = original.width;
    final h = original.height;

    // Line thickness search window based on image size
    final maxLineThickness = math.max(2, (h / 450).round());
    final horizontalSpan = math.max(16, (w / 40).round());

    // Luminance threshold for ruling lines vs background
    final thresholdDiff = (25 + (sensitivity * 45)).round();

    for (int y = 2; y < h - 2; y++) {
      // Analyze horizontal row consistency
      for (int x = 1; x < w - 1; x++) {
        final p = original.getPixel(x, y);
        final pLum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        // Check if this pixel is darker than paper background
        final diff = bgColor.lum - pLum;
        if (diff <= 8 || diff > thresholdDiff + 60) {
          // Either too close to background (already paper) or very dark (likely ink stroke)
          continue;
        }

        // Test if pixel is part of a horizontal ruling line:
        // A ruling line is narrow vertically and continuous horizontally.
        final topP = original.getPixel(x, math.max(0, y - maxLineThickness));
        final btmP = original.getPixel(x, math.min(h - 1, y + maxLineThickness));
        final topLum = (0.299 * topP.r + 0.587 * topP.g + 0.114 * topP.b).round();
        final btmLum = (0.299 * btmP.r + 0.587 * btmP.g + 0.114 * btmP.b).round();

        // The background above and below the line should be brighter
        final isNarrowVertically = (topLum - pLum > 10) && (btmLum - pLum > 10);

        // Check horizontal continuity: check pixels to the left and right
        int horizCount = 0;
        final checkSpan = math.min(10, horizontalSpan);
        for (int dx = -checkSpan; dx <= checkSpan; dx += 2) {
          final curX = (x + dx).clamp(0, w - 1);
          final neighbor = original.getPixel(curX, y);
          final nLum = (0.299 * neighbor.r + 0.587 * neighbor.g + 0.114 * neighbor.b).round();
          if ((bgColor.lum - nLum).abs() > 8) {
            horizCount++;
          }
        }

        final isContinuousHoriz = horizCount >= (checkSpan * 0.7);

        if (isNarrowVertically || isContinuousHoriz) {
          // Check if this is an intersection with a genuine handwriting stroke:
          // Handwriting strokes are typically much darker (diff > 80) or colored (pen ink)
          final isHeavyInk = (bgColor.lum - pLum) > 95;
          final isColoredPen = preserveColoredInk && _isDistinctColorInk(p);

          if (!isHeavyInk && !isColoredPen) {
            // Smoothly inpaint using adjacent background pixels
            final interpR = ((topP.r + btmP.r) / 2).round().clamp(0, 255);
            final interpG = ((topP.g + btmP.g) / 2).round().clamp(0, 255);
            final interpB = ((topP.b + btmP.b) / 2).round().clamp(0, 255);

            result.setPixelRgb(x, y, interpR, interpG, interpB);
          }
        }
      }
    }
  }

  /// Removes both horizontal and vertical grid lines for graph/math paper
  static void _removeOrthogonalGrid({
    required img.Image original,
    required img.Image result,
    required ({int r, int g, int b, int lum}) bgColor,
    required double sensitivity,
    required bool preserveColoredInk,
  }) {
    // 1. Remove horizontal components
    _removeHorizontalLines(
      original: original,
      result: result,
      bgColor: bgColor,
      sensitivity: sensitivity,
      preserveColoredInk: preserveColoredInk,
      isFrenchRuled: false,
    );

    // 2. Remove vertical components
    final w = original.width;
    final h = original.height;
    final maxThickness = math.max(2, (w / 450).round());
    final thresholdDiff = (25 + (sensitivity * 45)).round();

    for (int x = 2; x < w - 2; x++) {
      for (int y = 1; y < h - 1; y++) {
        final p = original.getPixel(x, y);
        final pLum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        final diff = bgColor.lum - pLum;
        if (diff <= 8 || diff > thresholdDiff + 60) continue;

        final leftP = original.getPixel(math.max(0, x - maxThickness), y);
        final rightP = original.getPixel(math.min(w - 1, x + maxThickness), y);
        final leftLum = (0.299 * leftP.r + 0.587 * leftP.g + 0.114 * leftP.b).round();
        final rightLum = (0.299 * rightP.r + 0.587 * rightP.g + 0.114 * rightP.b).round();

        final isNarrowHorizontally = (leftLum - pLum > 10) && (rightLum - pLum > 10);

        if (isNarrowHorizontally) {
          final isHeavyInk = (bgColor.lum - pLum) > 95;
          final isColoredPen = preserveColoredInk && _isDistinctColorInk(p);

          if (!isHeavyInk && !isColoredPen) {
            final interpR = ((leftP.r + rightP.r) / 2).round().clamp(0, 255);
            final interpG = ((leftP.g + rightP.g) / 2).round().clamp(0, 255);
            final interpB = ((leftP.b + rightP.b) / 2).round().clamp(0, 255);

            result.setPixelRgb(x, y, interpR, interpG, interpB);
          }
        }
      }
    }
  }

  /// Removes blue/cyan ruling lines specifically via chromatic differential analysis
  static void _removeBlueCyanLines({
    required img.Image original,
    required img.Image result,
    required ({int r, int g, int b, int lum}) bgColor,
    required double sensitivity,
    required bool preserveColoredInk,
  }) {
    final w = original.width;
    final h = original.height;
    final blueThreshold = (10 - (sensitivity * 6)).round().clamp(4, 20);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = original.getPixel(x, y);

        // Cyan / Blue lines have higher Blue & Green than Red:
        // (B > R + threshold) AND (p is relatively bright, not dark black ink)
        final blueDiff = p.b - p.r;
        final greenDiff = p.g - p.r;
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        final isBlueOrCyanRuling = (blueDiff > blueThreshold || greenDiff > blueThreshold) && lum > 140;

        if (isBlueOrCyanRuling) {
          // Replace with clean paper background
          result.setPixelRgb(x, y, bgColor.r, bgColor.g, bgColor.b);
        }
      }
    }
  }

  /// Checks if a pixel has strong non-ruling color saturation (e.g. red pen, green highlighter, bold blue ink)
  static bool _isDistinctColorInk(img.Pixel p) {
    final maxC = math.max(p.r, math.max(p.g, p.b));
    final minC = math.min(p.r, math.min(p.g, p.b));
    final saturation = maxC - minC;

    // Distinct colored pens (red/green/purple) have high chromatic differential
    // and moderate-to-dark luminance.
    return saturation > 45 && maxC < 210;
  }

  /// Enhances handwriting strokes and whitens the paper background
  static void _applyPostEnhancement(
    img.Image image, {
    required bool whitenBackground,
    required bool enhanceHandwriting,
    required ({int r, int g, int b, int lum}) paperBg,
  }) {
    final w = image.width;
    final h = image.height;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        if (whitenBackground && lum >= (paperBg.lum - 22)) {
          // Paper background whiten to 255
          image.setPixelRgb(x, y, 255, 255, 255);
        } else if (enhanceHandwriting && lum < 155) {
          // Darken and boost ink contrast
          final factor = 0.82;
          final newR = (p.r * factor).round().clamp(0, 255);
          final newG = (p.g * factor).round().clamp(0, 255);
          final newB = (p.b * factor).round().clamp(0, 255);
          image.setPixelRgb(x, y, newR, newG, newB);
        }
      }
    }
  }
}
