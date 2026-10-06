import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum BookSpinePosition {
  left,
  right,
  center,
}

class BookCurveService {
  BookCurveService();

  /// Dewarp and flatten a curved book page using a cylindrical 3D arc-length model.
  /// 100% offline, pure Dart processing.
  Future<Uint8List> flattenBookCurve({
    required Uint8List imageBytes,
    double curvatureStrength = 0.55,
    BookSpinePosition spinePosition = BookSpinePosition.left,
    bool removeGutterShadow = true,
    double shadowRemovalIntensity = 0.45,
  }) async {
    return compute(
      _flattenBookCurveIsolate,
      _DewarpParams(
        imageBytes: imageBytes,
        curvatureStrength: curvatureStrength.clamp(0.1, 1.0),
        spinePosition: spinePosition,
        removeGutterShadow: removeGutterShadow,
        shadowRemovalIntensity: shadowRemovalIntensity.clamp(0.1, 1.0),
      ),
    );
  }
}

class _DewarpParams {
  const _DewarpParams({
    required this.imageBytes,
    required this.curvatureStrength,
    required this.spinePosition,
    required this.removeGutterShadow,
    required this.shadowRemovalIntensity,
  });

  final Uint8List imageBytes;
  final double curvatureStrength;
  final BookSpinePosition spinePosition;
  final bool removeGutterShadow;
  final double shadowRemovalIntensity;
}

Uint8List _flattenBookCurveIsolate(_DewarpParams params) {
  try {
    img.Image? src = img.decodeImage(params.imageBytes);
    if (src == null) return params.imageBytes;

    // Constrain resolution to max 1600px dimension for lightning performance (<250ms)
    // and preventing out-of-memory or Choreographer skipped frames
    if (src.width > 1600 || src.height > 1600) {
      src = img.copyResize(
        src,
        width: src.width >= src.height ? 1600 : null,
        height: src.height > src.width ? 1600 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    final width = src.width;
    final height = src.height;

    // Working image copy
    final dst = img.Image(width: width, height: height, numChannels: src.numChannels);

    final strength = params.curvatureStrength;
    final spine = params.spinePosition;
    final removeShadow = params.removeGutterShadow;
    final shadowIntensity = params.shadowRemovalIntensity;

    // Gutter influence width (typically 35% to 45% of page width near binding)
    final gutterWidth = spine == BookSpinePosition.center
        ? (width * 0.28).clamp(60.0, width * 0.45)
        : (width * 0.40).clamp(80.0, width * 0.60);

    // Precompute arc-length expansion mapping
    // Map output coordinate x -> input coordinate x
    final xMapping = Float32List(width);
    for (int x = 0; x < width; x++) {
      xMapping[x] = _calculateSourceX(
        x: x.toDouble(),
        width: width.toDouble(),
        gutterWidth: gutterWidth,
        spine: spine,
        strength: strength,
      );
    }

    // Precompute vertical camber curvature factors per column
    final camberFactors = Float32List(width);
    for (int x = 0; x < width; x++) {
      double distToSpine;
      switch (spine) {
        case BookSpinePosition.left:
          distToSpine = x.toDouble();
          break;
        case BookSpinePosition.right:
          distToSpine = (width - 1 - x).toDouble();
          break;
        case BookSpinePosition.center:
          distToSpine = (x - (width / 2.0)).abs();
          break;
      }
      if (distToSpine < gutterWidth) {
        final u = (distToSpine / gutterWidth).clamp(0.0, 1.0);
        camberFactors[x] = math.pow(1.0 - u, 2.0).toDouble();
      } else {
        camberFactors[x] = 0.0;
      }
    }

    // Precompute shadow lightening multipliers
    final shadowMultipliers = Float32List(width);
    for (int x = 0; x < width; x++) {
      if (!removeShadow) {
        shadowMultipliers[x] = 1.0;
        continue;
      }

      double distToSpine;
      switch (spine) {
        case BookSpinePosition.left:
          distToSpine = x.toDouble();
          break;
        case BookSpinePosition.right:
          distToSpine = (width - 1 - x).toDouble();
          break;
        case BookSpinePosition.center:
          distToSpine = (x - width / 2.0).abs();
          break;
      }

      final shadowZone = gutterWidth * 0.65;
      if (distToSpine < shadowZone) {
        final norm = distToSpine / shadowZone; // 0 (spine) to 1 (outer)
        final falloff = math.pow(1.0 - norm, 2.0);
        shadowMultipliers[x] = (1.0 + (shadowIntensity * 0.75 * falloff)).toDouble();
      } else {
        shadowMultipliers[x] = 1.0;
      }
    }

    final maxSag = height * 0.035 * strength;

    // Resample pixels using bilinear interpolation along dewarped coordinates
    for (int y = 0; y < height; y++) {
      final normY = (y / height) - 0.5;
      final sagFactor = normY * maxSag;

      for (int x = 0; x < width; x++) {
        final srcX = xMapping[x];
        final camber = camberFactors[x];
        final srcY = camber > 0.0
            ? (y - (sagFactor * camber)).clamp(0.0, height - 1.0)
            : y.toDouble();

        // Bilinear sampling
        final pixel = _sampleBilinear(src, srcX, srcY, width, height);

        final shadowMult = shadowMultipliers[x];
        if (shadowMult > 1.001) {
          // Brighten gutter shadow while preserving dark text ink
          final r = _applyShadowBoost(pixel.r.toInt(), shadowMult);
          final g = _applyShadowBoost(pixel.g.toInt(), shadowMult);
          final b = _applyShadowBoost(pixel.b.toInt(), shadowMult);
          dst.setPixelRgba(x, y, r, g, b, pixel.a.toInt());
        } else {
          dst.setPixel(x, y, pixel);
        }
      }
    }

    final encoded = img.encodeJpg(dst, quality: 90);
    return Uint8List.fromList(encoded);
  } catch (e) {
    debugPrint('[BookCurveService] Processing error: $e');
    return params.imageBytes;
  }
}

double _calculateSourceX({
  required double x,
  required double width,
  required double gutterWidth,
  required BookSpinePosition spine,
  required double strength,
}) {
  switch (spine) {
    case BookSpinePosition.left:
      if (x >= gutterWidth) return x;
      final u = (x / gutterWidth).clamp(0.0, 1.0);
      // Cylindrical expansion: unrolls condensed text near left binding
      final dewarpedU = math.pow(u, 1.0 / (1.0 + strength * 0.75)).toDouble();
      return dewarpedU * gutterWidth;

    case BookSpinePosition.right:
      final distFromRight = width - 1 - x;
      if (distFromRight >= gutterWidth) return x;
      final u = (distFromRight / gutterWidth).clamp(0.0, 1.0);
      final dewarpedU = math.pow(u, 1.0 / (1.0 + strength * 0.75)).toDouble();
      return width - 1 - (dewarpedU * gutterWidth);

    case BookSpinePosition.center:
      final center = width / 2.0;
      final dist = (x - center).abs();
      if (dist >= gutterWidth) return x;
      final u = (dist / gutterWidth).clamp(0.0, 1.0);
      final dewarpedU = math.pow(u, 1.0 / (1.0 + strength * 0.75)).toDouble();
      final sign = x >= center ? 1.0 : -1.0;
      return center + (sign * dewarpedU * gutterWidth);
  }
}

img.Pixel _sampleBilinear(
  img.Image image,
  double fx,
  double fy,
  int width,
  int height,
) {
  final x0 = fx.floor().clamp(0, width - 1);
  final y0 = fy.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);

  final dx = fx - x0;
  final dy = fy - y0;

  final p00 = image.getPixel(x0, y0);
  final p10 = image.getPixel(x1, y0);
  final p01 = image.getPixel(x0, y1);
  final p11 = image.getPixel(x1, y1);

  final r = _bilerp(p00.r, p10.r, p01.r, p11.r, dx, dy).round();
  final g = _bilerp(p00.g, p10.g, p01.g, p11.g, dx, dy).round();
  final b = _bilerp(p00.b, p10.b, p01.b, p11.b, dx, dy).round();
  final a = _bilerp(p00.a, p10.a, p01.a, p11.a, dx, dy).round();

  return image.getPixel(x0, y0)
    ..r = r
    ..g = g
    ..b = b
    ..a = a;
}

double _bilerp(num v00, num v10, num v01, num v11, double dx, double dy) {
  final top = v00 * (1.0 - dx) + v10 * dx;
  final btm = v01 * (1.0 - dx) + v11 * dx;
  return top * (1.0 - dy) + btm * dy;
}

int _applyShadowBoost(int val, double gain) {
  // If ink is dark (text), don't wash it out completely
  if (val < 60) {
    return val;
  }
  // Lighten grayish paper background
  final boosted = (val * gain).round();
  return boosted.clamp(0, 255);
}
