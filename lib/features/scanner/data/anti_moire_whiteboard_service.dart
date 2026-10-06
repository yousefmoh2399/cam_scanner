import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Available filter modes for Anti-Moiré and Whiteboard Glare
enum AntiGlareFilterMode {
  /// Screen / Display Capture: Suppresses pixel grid moiré ripples and raster lines
  screenAntiMoire(
    'إزالة تموجات الشاشات (Screen Anti-Moiré)',
    'إزالة خطوط التموج وقوس قزح من شاشات الكمبيوتر والتلفزيون لتبدو كلقطة شاشة أصلية',
  ),

  /// Whiteboard / Blackboard: Removes overhead light glare and boosts faded marker ink
  whiteboardGlare(
    'إزالة لمعان السبورة وتعزيز الأقلام',
    'إزالة انعكاس فلاش الكاميرا ومصابيح السقف مع تعزيز ألوان أقلام السبورة',
  ),

  /// Glossy Paper / Magazines: Neutralizes reflections on coated photographic paper
  glossyPaperGlare(
    'إزالة انعكاسات الورق المصقول والمجلات',
    'معادلة البقع المضيئة واللمعان على الورق اللامع والكتالوجات',
  );

  const AntiGlareFilterMode(this.label, this.description);
  final String label;
  final String description;
}

/// Processing parameters for Anti-Moiré and Glare suppression
class AntiGlareConfig {
  const AntiGlareConfig({
    this.mode = AntiGlareFilterMode.screenAntiMoire,
    this.strength = 0.65, // 0.1 to 1.0
    this.sharpenText = true,
    this.digitalScreenshotTone = true, // Re-map gamma to pure digital display gamut
  });

  final AntiGlareFilterMode mode;
  final double strength;
  final bool sharpenText;
  final bool digitalScreenshotTone;
}

/// Service that executes offline mathematical filters to suppress
/// high-frequency moiré patterns and specular whiteboard glare.
class AntiMoireWhiteboardService {
  const AntiMoireWhiteboardService();

  /// Process image bytes with anti-moiré and glare elimination in an isolate
  Future<Uint8List> applyFilter({
    required Uint8List inputBytes,
    required AntiGlareConfig config,
  }) async {
    return compute(_processIsolate, {
      'bytes': inputBytes,
      'mode': config.mode.index,
      'strength': config.strength,
      'sharpenText': config.sharpenText,
      'digitalTone': config.digitalScreenshotTone,
    });
  }

  /// Process a file from disk and save the clean output
  Future<String> processFile({
    required String inputPath,
    required AntiGlareConfig config,
  }) async {
    final inputBytes = await File(inputPath).readAsBytes();
    final outputBytes = await applyFilter(
      inputBytes: inputBytes,
      config: config,
    );

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(dir.path, 'anti_glare_$ts.png');
    await File(outPath).writeAsBytes(outputBytes, flush: true);
    return outPath;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Isolate Worker
  // ─────────────────────────────────────────────────────────────────────────

  static Uint8List _processIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final modeIdx = params['mode'] as int;
    final strength = (params['strength'] as num).toDouble();
    final sharpenText = params['sharpenText'] as bool;
    final digitalTone = params['digitalTone'] as bool;

    final mode = AntiGlareFilterMode.values[modeIdx];

    final original = img.decodeImage(rawBytes);
    if (original == null) return rawBytes;

    final result = img.Image.from(original);

    switch (mode) {
      case AntiGlareFilterMode.screenAntiMoire:
        _applyScreenAntiMoire(
          original: original,
          result: result,
          strength: strength,
          digitalTone: digitalTone,
          sharpenText: sharpenText,
        );
        break;

      case AntiGlareFilterMode.whiteboardGlare:
        _applyWhiteboardGlareEqualization(
          original: original,
          result: result,
          strength: strength,
          sharpenText: sharpenText,
        );
        break;

      case AntiGlareFilterMode.glossyPaperGlare:
        _applyGlossyPaperGlareFilter(
          original: original,
          result: result,
          strength: strength,
        );
        break;
    }

    return Uint8List.fromList(img.encodePng(result));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Algorithms
  // ─────────────────────────────────────────────────────────────────────────

  /// Suppresses high-frequency chromatic moiré fringes and screen pixel raster stripes
  static void _applyScreenAntiMoire({
    required img.Image original,
    required img.Image result,
    required double strength,
    required bool digitalTone,
    required bool sharpenText,
  }) {
    final w = original.width;
    final h = original.height;

    final radius = (strength * 2.5).round().clamp(1, 4);

    // 1. Chromatic Fringe Suppression (removes rainbow ripple colors)
    for (int y = radius; y < h - radius; y++) {
      for (int x = radius; x < w - radius; x++) {
        final p = original.getPixel(x, y);

        // Calculate local chromatic average over small window
        int sumR = 0, sumG = 0, sumB = 0, count = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final neighbor = original.getPixel(x + dx, y + dy);
            sumR += neighbor.r.toInt();
            sumG += neighbor.g.toInt();
            sumB += neighbor.b.toInt();
            count++;
          }
        }

        final avgR = (sumR / count).round();
        final avgG = (sumG / count).round();
        final avgB = (sumB / count).round();

        // Blend luminance from original (preserve sharpness) with chrominance from smoothed
        final pLum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
        final avgLum = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB);
        final lumDiff = pLum - avgLum;

        // Reconstitute pixel
        int outR = (avgR + lumDiff * 0.75).round().clamp(0, 255);
        int outG = (avgG + lumDiff * 0.75).round().clamp(0, 255);
        int outB = (avgB + lumDiff * 0.75).round().clamp(0, 255);

        // 2. Digital Screen Tone Mapping (Screenshot finish)
        if (digitalTone) {
          // Stretch dynamic range so dark screen areas snap to deep crisp blacks
          outR = _toneCurve(outR);
          outG = _toneCurve(outG);
          outB = _toneCurve(outB);
        }

        result.setPixelRgb(x, y, outR, outG, outB);
      }
    }

    // 3. Optional unsharp mask to crisp up text letters
    if (sharpenText) {
      _applyTextSharpen(result);
    }
  }

  /// Equalizes uneven lighting and flash specular hot spots on whiteboards
  static void _applyWhiteboardGlareEqualization({
    required img.Image original,
    required img.Image result,
    required double strength,
    required bool sharpenText,
  }) {
    final w = original.width;
    final h = original.height;

    // Estimate background illumination field via downsampled coarse grid
    const blockSize = 32;
    final blocksX = (w / blockSize).ceil();
    final blocksY = (h / blockSize).ceil();
    final illuminationField = List.generate(blocksY, (_) => Float32List(blocksX));

    for (int by = 0; by < blocksY; by++) {
      for (int bx = 0; bx < blocksX; bx++) {
        int maxLum = 0;
        final startX = bx * blockSize;
        final startY = by * blockSize;
        final endX = math.min(w, startX + blockSize);
        final endY = math.min(h, startY + blockSize);

        for (int y = startY; y < endY; y += 4) {
          for (int x = startX; x < endX; x += 4) {
            final p = original.getPixel(x, y);
            final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
            if (lum > maxLum) maxLum = lum;
          }
        }
        illuminationField[by][bx] = math.max(120.0, maxLum.toDouble());
      }
    }

    // Retinex-based illumination division and dry-erase marker saturation
    for (int y = 0; y < h; y++) {
      final by = (y / blockSize).floor().clamp(0, blocksY - 1);

      for (int x = 0; x < w; x++) {
        final bx = (x / blockSize).floor().clamp(0, blocksX - 1);
        final bgLum = illuminationField[by][bx];

        final p = original.getPixel(x, y);

        // Normalize against local glare field
        final normFactor = 248.0 / bgLum;
        int normR = (p.r * normFactor).round().clamp(0, 255);
        int normG = (p.g * normFactor).round().clamp(0, 255);
        int normB = (p.b * normFactor).round().clamp(0, 255);

        // Marker color saturation boost: if pixel is colored marker (not white board)
        final pLum = (0.299 * normR + 0.587 * normG + 0.114 * normB).round();
        if (pLum < 195) {
          // Darken and saturate marker ink
          final inkFactor = 0.88;
          normR = (normR * inkFactor).round().clamp(0, 255);
          normG = (normG * inkFactor).round().clamp(0, 255);
          normB = (normB * inkFactor).round().clamp(0, 255);
        } else {
          // Whiten plastic board
          normR = math.min(255, (normR * 1.05).round());
          normG = math.min(255, (normG * 1.05).round());
          normB = math.min(255, (normB * 1.05).round());
        }

        result.setPixelRgb(x, y, normR, normG, normB);
      }
    }
  }

  /// Dampens specular highlights on glossy paper
  static void _applyGlossyPaperGlareFilter({
    required img.Image original,
    required img.Image result,
    required double strength,
  }) {
    final w = original.width;
    final h = original.height;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = original.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        // If specular blown-out glare (lum > 235), softly compress towards natural page tone
        if (lum > 225) {
          final factor = 1.0 - (strength * 0.18);
          final outR = (p.r * factor).round().clamp(0, 255);
          final outG = (p.g * factor).round().clamp(0, 255);
          final outB = (p.b * factor).round().clamp(0, 255);
          result.setPixelRgb(x, y, outR, outG, outB);
        }
      }
    }
  }

  /// S-Curve tone mapping for rich digital screenshot aesthetic
  static int _toneCurve(int val) {
    final v = val / 255.0;
    // S-curve stretching
    final mapped = (v < 0.5)
        ? 2 * v * v
        : 1 - 2 * (1 - v) * (1 - v);
    return (mapped * 255).round().clamp(0, 255);
  }

  /// Unsharp mask text sharpening
  static void _applyTextSharpen(img.Image image) {
    final w = image.width;
    final h = image.height;
    final copy = img.Image.from(image);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final center = copy.getPixel(x, y);
        final top = copy.getPixel(x, y - 1);
        final btm = copy.getPixel(x, y + 1);
        final left = copy.getPixel(x - 1, y);
        final right = copy.getPixel(x + 1, y);

        // Simple 3x3 Laplacian sharpening kernel
        final newR = (5 * center.r - top.r - btm.r - left.r - right.r).clamp(0, 255);
        final newG = (5 * center.g - top.g - btm.g - left.g - right.g).clamp(0, 255);
        final newB = (5 * center.b - top.b - btm.b - left.b - right.b).clamp(0, 255);

        image.setPixelRgb(x, y, newR.toInt(), newG.toInt(), newB.toInt());
      }
    }
  }
}
