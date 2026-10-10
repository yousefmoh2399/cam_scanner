import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Clean stroke representation with normalized coordinates (0.0 to 1.0)
class CleanStroke {
  const CleanStroke({
    required this.points,
    required this.radiusFraction,
  });

  /// Normalized points (x: 0..1, y: 0..1)
  final List<({double x, double y})> points;

  /// Radius as a fraction of image minimum dimension (e.g. 0.02 = 2%)
  final double radiusFraction;
}

class MagicCleanService {
  /// Applies manual brush inpainting using local paper background interpolation
  Future<Uint8List> applyInpaintingStrokes({
    required Uint8List imageBytes,
    required List<CleanStroke> strokes,
  }) async {
    if (strokes.isEmpty) return imageBytes;

    return compute(_inpaintIsolate, {
      'bytes': imageBytes,
      'strokes': strokes.map((s) => {
        'pts': s.points.map((p) => [p.x, p.y]).toList(),
        'radius': s.radiusFraction,
      }).toList(),
    });
  }

  /// Automatically clears finger intrusions and punch holes along document margins
  Future<Uint8List> autoCleanMargins({
    required Uint8List imageBytes,
    bool cleanFingers = true,
    bool cleanPunchHoles = true,
    double marginFraction = 0.075, // Outer 7.5% margins
  }) async {
    return compute(_autoMarginCleanIsolate, {
      'bytes': imageBytes,
      'cleanFingers': cleanFingers,
      'cleanPunchHoles': cleanPunchHoles,
      'margin': marginFraction,
    });
  }

  /// Levels paper background to crisp clean tone while preserving text sharpness
  Future<Uint8List> autoLevelAndWhiten({
    required Uint8List imageBytes,
  }) async {
    return compute(_autoLevelIsolate, {
      'bytes': imageBytes,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Isolate Workers
  // ─────────────────────────────────────────────────────────────────────────

  static Uint8List _inpaintIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final strokeData = params['strokes'] as List<dynamic>;

    final image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    final w = image.width;
    final h = image.height;
    final minDim = math.min(w, h);

    // Compute paper dominant tone (sampling brightest 25% of image)
    int bgR = 255, bgG = 255, bgB = 255;
    int lumCount = 0;
    int sumR = 0, sumG = 0, sumB = 0;

    for (int y = 0; y < h; y += 8) {
      for (int x = 0; x < w; x += 8) {
        final p = image.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        if (lum > 185) {
          sumR += p.r.toInt();
          sumG += p.g.toInt();
          sumB += p.b.toInt();
          lumCount++;
        }
      }
    }
    if (lumCount > 0) {
      bgR = (sumR / lumCount).round().clamp(220, 255);
      bgG = (sumG / lumCount).round().clamp(220, 255);
      bgB = (sumB / lumCount).round().clamp(220, 255);
    }

    // Apply strokes
    for (final s in strokeData) {
      final pts = (s['pts'] as List<dynamic>);
      final radius = ((s['radius'] as num).toDouble() * minDim).round().clamp(4, 120);
      final r2 = radius * radius;

      for (final pt in pts) {
        final px = ((pt[0] as num).toDouble() * w).round();
        final py = ((pt[1] as num).toDouble() * h).round();

        // Sample local perimeter around this spot to get exact local paper tone
        int localSumR = 0, localSumG = 0, localSumB = 0, localSamples = 0;
        final sampleRadius = radius * 2;
        for (int dy = -sampleRadius; dy <= sampleRadius; dy += 4) {
          for (int dx = -sampleRadius; dx <= sampleRadius; dx += 4) {
            final dist2 = dx * dx + dy * dy;
            if (dist2 >= r2 && dist2 <= sampleRadius * sampleRadius) {
              final sx = (px + dx).clamp(0, w - 1);
              final sy = (py + dy).clamp(0, h - 1);
              final sp = image.getPixel(sx, sy);
              final lum = (0.299 * sp.r + 0.587 * sp.g + 0.114 * sp.b).round();
              if (lum > 160) {
                localSumR += sp.r.toInt();
                localSumG += sp.g.toInt();
                localSumB += sp.b.toInt();
                localSamples++;
              }
            }
          }
        }

        final fillR = localSamples > 0 ? (localSumR / localSamples).round() : bgR;
        final fillG = localSamples > 0 ? (localSumG / localSamples).round() : bgG;
        final fillB = localSamples > 0 ? (localSumB / localSamples).round() : bgB;

        // Inpaint mask circle with soft anti-aliased edge
        for (int dy = -radius; dy <= radius; dy++) {
          final targetY = py + dy;
          if (targetY < 0 || targetY >= h) continue;

          for (int dx = -radius; dx <= radius; dx++) {
            final targetX = px + dx;
            if (targetX < 0 || targetX >= w) continue;

            final d2 = dx * dx + dy * dy;
            if (d2 <= r2) {
              final edgeFactor = math.sqrt(d2) / radius;
              if (edgeFactor < 0.8) {
                image.setPixelRgb(targetX, targetY, fillR, fillG, fillB);
              } else {
                // Soft alpha blending on edge
                final alpha = (1.0 - edgeFactor) / 0.2;
                final curr = image.getPixel(targetX, targetY);
                final blendedR = (fillR * alpha + curr.r * (1.0 - alpha)).round();
                final blendedG = (fillG * alpha + curr.g * (1.0 - alpha)).round();
                final blendedB = (fillB * alpha + curr.b * (1.0 - alpha)).round();
                image.setPixelRgb(targetX, targetY, blendedR, blendedG, blendedB);
              }
            }
          }
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  static Uint8List _autoMarginCleanIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final marginFrac = (params['margin'] as num).toDouble().clamp(0.04, 0.15);

    final image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    final w = image.width;
    final h = image.height;
    final marginW = (w * marginFrac).round();
    final marginH = (h * marginFrac).round();

    // 1. Sample clean paper reference band (from marginW to marginW * 2)
    int refR = 250, refG = 250, refB = 250;
    int samples = 0;
    int sumR = 0, sumG = 0, sumB = 0;

    for (int y = marginH; y < h - marginH; y += 6) {
      // Left reference strip
      for (int x = marginW; x < marginW + 30 && x < w; x += 3) {
        final p = image.getPixel(x, y);
        if (p.r > 175 && p.g > 175 && p.b > 175) {
          sumR += p.r.toInt();
          sumG += p.g.toInt();
          sumB += p.b.toInt();
          samples++;
        }
      }
      // Right reference strip
      for (int x = w - marginW - 30; x < w - marginW && x >= 0; x += 3) {
        final p = image.getPixel(x, y);
        if (p.r > 175 && p.g > 175 && p.b > 175) {
          sumR += p.r.toInt();
          sumG += p.g.toInt();
          sumB += p.b.toInt();
          samples++;
        }
      }
    }

    if (samples > 0) {
      refR = (sumR / samples).round().clamp(215, 255);
      refG = (sumG / samples).round().clamp(215, 255);
      refB = (sumB / samples).round().clamp(215, 255);
    }

    // 2. Clean Left Margin (fingers, punch holes, edge binder marks)
    _cleanVerticalStrip(
      image: image,
      startX: 0,
      endX: marginW,
      refX: marginW + 5,
      h: h,
      fallbackR: refR,
      fallbackG: refG,
      fallbackB: refB,
    );

    // 3. Clean Right Margin
    _cleanVerticalStrip(
      image: image,
      startX: w - marginW,
      endX: w,
      refX: w - marginW - 5,
      h: h,
      fallbackR: refR,
      fallbackG: refG,
      fallbackB: refB,
    );

    // 4. Clean Top & Bottom Margins
    _cleanHorizontalStrip(
      image: image,
      startY: 0,
      endY: marginH,
      refY: marginH + 5,
      w: w,
      fallbackR: refR,
      fallbackG: refG,
      fallbackB: refB,
    );

    _cleanHorizontalStrip(
      image: image,
      startY: h - marginH,
      endY: h,
      refY: h - marginH - 5,
      w: w,
      fallbackR: refR,
      fallbackG: refG,
      fallbackB: refB,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  static void _cleanVerticalStrip({
    required img.Image image,
    required int startX,
    required int endX,
    required int refX,
    required int h,
    required int fallbackR,
    required int fallbackG,
    required int fallbackB,
  }) {
    final validRefX = refX.clamp(0, image.width - 1);
    for (int y = 0; y < h; y++) {
      final refPix = image.getPixel(validRefX, y);
      final r = refPix.r > 160 ? refPix.r.toInt() : fallbackR;
      final g = refPix.g > 160 ? refPix.g.toInt() : fallbackG;
      final b = refPix.b > 160 ? refPix.b.toInt() : fallbackB;

      for (int x = startX; x < endX && x < image.width; x++) {
        final cur = image.getPixel(x, y);
        final lum = (0.299 * cur.r + 0.587 * cur.g + 0.114 * cur.b).round();
        // If pixel is darker than clean paper or has skin tint (finger / punch hole / staple)
        if (lum < 195 || (cur.r > cur.b + 35)) {
          image.setPixelRgb(x, y, r, g, b);
        }
      }
    }
  }

  static void _cleanHorizontalStrip({
    required img.Image image,
    required int startY,
    required int endY,
    required int refY,
    required int w,
    required int fallbackR,
    required int fallbackG,
    required int fallbackB,
  }) {
    final validRefY = refY.clamp(0, image.height - 1);
    for (int x = 0; x < w; x++) {
      final refPix = image.getPixel(x, validRefY);
      final r = refPix.r > 160 ? refPix.r.toInt() : fallbackR;
      final g = refPix.g > 160 ? refPix.g.toInt() : fallbackG;
      final b = refPix.b > 160 ? refPix.b.toInt() : fallbackB;

      for (int y = startY; y < endY && y < image.height; y++) {
        final cur = image.getPixel(x, y);
        final lum = (0.299 * cur.r + 0.587 * cur.g + 0.114 * cur.b).round();
        if (lum < 195 || (cur.r > cur.b + 35)) {
          image.setPixelRgb(x, y, r, g, b);
        }
      }
    }
  }

  static Uint8List _autoLevelIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    if (image.width > 1400 || image.height > 1400) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 1400 : null,
        height: image.height > image.width ? 1400 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    final w = image.width;
    final h = image.height;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();

        if (lum > 195) {
          // Flatten paper background to crisp pure white
          image.setPixelRgb(x, y, 255, 255, 255);
        } else if (lum < 110) {
          // Enhance ink contrast
          final newR = (p.r * 0.85).round();
          final newG = (p.g * 0.85).round();
          final newB = (p.b * 0.85).round();
          image.setPixelRgb(x, y, newR, newG, newB);
        } else {
          // Midtones: gently stretch towards white
          final ratio = (lum - 110) / (195 - 110);
          final boost = (45 * ratio).round();
          final newR = (p.r + boost).clamp(0, 255);
          final newG = (p.g + boost).clamp(0, 255);
          final newB = (p.b + boost).clamp(0, 255);
          image.setPixelRgb(x, y, newR, newG, newB);
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  /// Automatically detects and eliminates uneven room lighting and harsh phone shadows
  Future<Uint8List> removeShadowAndGlare({
    required Uint8List imageBytes,
  }) async {
    return compute(_shadowGlareIsolate, {
      'bytes': imageBytes,
    });
  }

  static Uint8List _shadowGlareIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    if (image.width > 1400 || image.height > 1400) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 1400 : null,
        height: image.height > image.width ? 1400 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    final w = image.width;
    final h = image.height;

    // 1. Build downsampled 2D illumination grid (approx. 40x40 blocks)
    const gridSize = 40;
    final gridCols = (w / gridSize).ceil();
    final gridRows = (h / gridSize).ceil();
    final lightMap = List.generate(gridRows, (_) => List<double>.filled(gridCols, 240.0));

    // Sample the brightest pixels in each block to model local background paper luminance
    for (int gy = 0; gy < gridRows; gy++) {
      final startY = gy * gridSize;
      final endY = math.min(h, startY + gridSize);

      for (int gx = 0; gx < gridCols; gx++) {
        final startX = gx * gridSize;
        final endX = math.min(w, startX + gridSize);

        int count = 0;
        double sumLum = 0;

        for (int y = startY; y < endY; y += 3) {
          for (int x = startX; x < endX; x += 3) {
            final p = image.getPixel(x, y);
            final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
            if (lum > 140) {
              sumLum += lum;
              count++;
            }
          }
        }

        lightMap[gy][gx] = count > 0 ? (sumLum / count).clamp(90.0, 255.0) : 230.0;
      }
    }

    // 2. Smooth the illumination grid to eliminate sharp cell boundaries
    final smoothedLight = List.generate(gridRows, (_) => List<double>.filled(gridCols, 240.0));
    for (int gy = 0; gy < gridRows; gy++) {
      for (int gx = 0; gx < gridCols; gx++) {
        double sum = 0;
        int neighbours = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final ny = gy + dy;
            final nx = gx + dx;
            if (ny >= 0 && ny < gridRows && nx >= 0 && nx < gridCols) {
              sum += lightMap[ny][nx];
              neighbours++;
            }
          }
        }
        smoothedLight[gy][gx] = sum / neighbours;
      }
    }

    // 3. Normalize pixels by local illumination field
    for (int y = 0; y < h; y++) {
      final gy = ((y / h) * gridRows).floor().clamp(0, gridRows - 1);

      for (int x = 0; x < w; x++) {
        final gx = ((x / w) * gridCols).floor().clamp(0, gridCols - 1);
        final localPaperLight = smoothedLight[gy][gx];

        final p = image.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

        // If it's dark ink (text, signature, stamp), keep it dark and sharp
        if (lum < 110) {
          const darkScale = 0.88;
          image.setPixelRgb(
            x,
            y,
            (p.r * darkScale).round(),
            (p.g * darkScale).round(),
            (p.b * darkScale).round(),
          );
        } else {
          // Normalize background paper by dividing out shadow gradient
          final scale = 255.0 / localPaperLight;
          final normR = (p.r * scale).round().clamp(0, 255);
          final normG = (p.g * scale).round().clamp(0, 255);
          final normB = (p.b * scale).round().clamp(0, 255);

          // If normalized pixel is near paper level, whiten it completely
          final normLum = 0.299 * normR + 0.587 * normG + 0.114 * normB;
          if (normLum > 200) {
            image.setPixelRgb(x, y, 255, 255, 255);
          } else {
            image.setPixelRgb(x, y, normR, normG, normB);
          }
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }
}
