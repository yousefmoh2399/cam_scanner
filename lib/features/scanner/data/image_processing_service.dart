// ignore_for_file: unused_element
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../shared/models/image_filter_type.dart';

enum ScanProcessingQuality { preview, balanced, enhanced }

class ImageProcessingService {
  Future<Uint8List> transformFile({
    required String sourcePath,
    required ImageFilterType filter,
    required int quarterTurns,
    ScanProcessingQuality quality = ScanProcessingQuality.enhanced,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    return transformBytes(
      bytes: bytes,
      filter: filter,
      quarterTurns: quarterTurns,
      quality: quality,
    );
  }

  Future<Uint8List> transformBytes({
    required Uint8List bytes,
    required ImageFilterType filter,
    required int quarterTurns,
    ScanProcessingQuality quality = ScanProcessingQuality.enhanced,
  }) {
    return Isolate.run(
      () => _processImageBytes(
        _ImageTransformRequest(
          bytes: bytes,
          filterIndex: filter.index,
          quarterTurns: quarterTurns,
          qualityIndex: quality.index,
        ),
      ),
    );
  }

  Future<void> rotateFileInPlace(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final rotated = await Isolate.run(() => _rotateImageBytes(bytes, 1));
    await File(imagePath).writeAsBytes(rotated);
  }

  Future<Uint8List> applyEnhancementFilter({
    required Uint8List bytes,
    bool applyEnhancement = true,
    bool runInIsolate = true,
    bool skipPerspectiveCrop = true,
  }) {
    if (!applyEnhancement) return Future.value(bytes);
    if (runInIsolate) {
      return Isolate.run(
        () => processEnhancementOnly(
          bytes,
          skipPerspectiveCrop: skipPerspectiveCrop,
        ),
      );
    }
    return Future.value(
      processEnhancementOnly(bytes, skipPerspectiveCrop: skipPerspectiveCrop),
    );
  }
}

/// PDF/save enhancement pipeline. Public so pdf_builder isolate can call it.
Uint8List processEnhancementOnly(
  Uint8List bytes, {
  bool skipPerspectiveCrop = true,
  bool applyAdaptiveThreshold = false,
}) {
  final pipelineStopwatch = Stopwatch()..start();
  debugPrint(
    '[EnhancementPipeline] START - input ${bytes.length} bytes, skipCrop=$skipPerspectiveCrop, bw=$applyAdaptiveThreshold',
  );

  var stepStopwatch = Stopwatch()..start();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    debugPrint('[EnhancementPipeline] ABORT - JPEG decode failed');
    return bytes;
  }
  debugPrint(
    '[EnhancementPipeline] Step 1 DECODE OK - ${decoded.width}x${decoded.height} (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 1 DECODE', decoded);

  stepStopwatch = Stopwatch()..start();
  var transformed = _normalizeSourceOrientation(decoded);
  debugPrint(
    '[EnhancementPipeline] Step 2 ORIENTATION normalized (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 2 ORIENTATION', transformed);

  stepStopwatch = Stopwatch()..start();
  transformed = _resizeForProcessing(
    transformed,
    quality: ScanProcessingQuality.enhanced,
  );
  debugPrint(
    '[EnhancementPipeline] Step 3 RESIZE OK - ${transformed.width}x${transformed.height} (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 3 RESIZE', transformed);

  stepStopwatch = Stopwatch()..start();
  if (skipPerspectiveCrop) {
    debugPrint(
      '[EnhancementPipeline] Step 4 CROP skipped - ML Kit already cropped (${stepStopwatch.elapsedMilliseconds}ms)',
    );
  } else {
    final detectedQuad = _detectDocumentQuad(
      transformed,
      quality: ScanProcessingQuality.enhanced,
    );
    if (detectedQuad != null) {
      transformed = _rectifyDocumentPerspective(transformed, detectedQuad);
      debugPrint(
        '[EnhancementPipeline] Step 4 CROP applied - perspective rectified (${stepStopwatch.elapsedMilliseconds}ms)',
      );
    } else {
      debugPrint(
        '[EnhancementPipeline] Step 4 CROP skipped - no quad detected (${stepStopwatch.elapsedMilliseconds}ms)',
      );
    }
  }
  _logColorDiagnostic('Step 4 CROP', transformed);

  stepStopwatch = Stopwatch()..start();
  transformed = _applyFastDenoise(transformed);
  debugPrint(
    '[EnhancementPipeline] Step 5 DENOISE applied - gaussian radius 1px (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 5 DENOISE', transformed);

  stepStopwatch = Stopwatch()..start();
  final blurRadius = _computeIlluminationBlurRadius(
    transformed.width,
    transformed.height,
  );
  transformed = _applyDivisionShadowRemoval(
    transformed,
    blurRadius: blurRadius,
  );
  debugPrint(
    '[EnhancementPipeline] Step 6 SHADOW REMOVAL applied - background map radius: ${blurRadius}px (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 6 SHADOW REMOVAL', transformed);

  stepStopwatch = Stopwatch()..start();
  transformed = _applyHistogramStretch(transformed);
  debugPrint(
    '[EnhancementPipeline] Step 7 HISTOGRAM STRETCH applied - white paper normalized to 255, color preserved (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 7 HISTOGRAM STRETCH', transformed);

  stepStopwatch = Stopwatch()..start();
  if (applyAdaptiveThreshold) {
    transformed = _applyAdaptiveThresholdBw(transformed);
    debugPrint(
      '[EnhancementPipeline] Step 8 ADAPTIVE THRESHOLD applied - Otsu B&W (${stepStopwatch.elapsedMilliseconds}ms)',
    );
  } else {
    transformed = _applyDocumentContrast(transformed);
    debugPrint(
      '[EnhancementPipeline] Step 8 DOCUMENT CONTRAST applied - color-preserving document look (${stepStopwatch.elapsedMilliseconds}ms)',
    );
  }
  _logColorDiagnostic('Step 8 CONTRAST/THRESHOLD', transformed);

  stepStopwatch = Stopwatch()..start();
  transformed = _fastSharpen(transformed);
  debugPrint(
    '[EnhancementPipeline] Step 9 SHARPEN applied - light unsharp mask (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  _logColorDiagnostic('Step 9 SHARPEN', transformed);

  stepStopwatch = Stopwatch()..start();
  final result = Uint8List.fromList(img.encodeJpg(transformed, quality: 88));
  debugPrint(
    '[EnhancementPipeline] Step 10 ENCODE JPEG (${stepStopwatch.elapsedMilliseconds}ms)',
  );
  final encodedProbe = img.decodeImage(result);
  if (encodedProbe != null) {
    _logColorDiagnostic('Step 10 ENCODE JPEG', encodedProbe);
  }
  debugPrint(
    '[EnhancementPipeline] DONE in ${pipelineStopwatch.elapsedMilliseconds}ms - output ${result.length} bytes, ${transformed.width}x${transformed.height}',
  );
  return result;
}

void _logColorDiagnostic(String step, img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width == 0 || height == 0) {
    debugPrint(
      '[EnhancementPipeline][ColorDiag] $step avgRedBlueDiff=0.00 maxRedBlueDiff=0 nearGrayRatio=1.000 samples=0',
    );
    return;
  }

  final strideX = math.max(1, width ~/ 48);
  final strideY = math.max(1, height ~/ 48);
  var totalDiff = 0.0;
  var maxDiff = 0;
  var nearGray = 0;
  var samples = 0;

  for (var y = 0; y < height; y += strideY) {
    for (var x = 0; x < width; x += strideX) {
      final pixel = image.getPixel(x, y);
      final diff = (pixel.r.toInt() - pixel.b.toInt()).abs();
      totalDiff += diff;
      if (diff > maxDiff) {
        maxDiff = diff;
      }
      if (diff <= 2) {
        nearGray++;
      }
      samples++;
    }
  }

  final avgDiff = samples == 0 ? 0.0 : totalDiff / samples;
  final nearGrayRatio = samples == 0 ? 1.0 : nearGray / samples;
  debugPrint(
    '[EnhancementPipeline][ColorDiag] $step avgRedBlueDiff=${avgDiff.toStringAsFixed(2)} maxRedBlueDiff=$maxDiff nearGrayRatio=${nearGrayRatio.toStringAsFixed(3)} samples=$samples',
  );
}

class _ImageTransformRequest {
  const _ImageTransformRequest({
    required this.bytes,
    required this.filterIndex,
    required this.quarterTurns,
    required this.qualityIndex,
  });

  final Uint8List bytes;
  final int filterIndex;
  final int quarterTurns;
  final int qualityIndex;
}

class _DocumentQuad {
  const _DocumentQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  final img.Point topLeft;
  final img.Point topRight;
  final img.Point bottomLeft;
  final img.Point bottomRight;
}

class _MaskComponent {
  _MaskComponent(int x, int y)
    : area = 0,
      minX = x,
      minY = y,
      maxX = x,
      maxY = y;

  int area;
  int minX;
  int minY;
  int maxX;
  int maxY;
  double sumX = 0;
  double sumY = 0;

  double _minSum = double.infinity;
  double _maxSum = double.negativeInfinity;
  double _maxDiff = double.negativeInfinity;
  double _maxInvDiff = double.negativeInfinity;

  img.Point topLeft = img.Point();
  img.Point topRight = img.Point();
  img.Point bottomLeft = img.Point();
  img.Point bottomRight = img.Point();

  void include(int x, int y) {
    area++;
    sumX += x;
    sumY += y;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;

    final sum = x + y;
    final diff = x - y;
    final inverseDiff = y - x;

    if (sum < _minSum) {
      _minSum = sum.toDouble();
      topLeft = img.Point(x, y);
    }
    if (sum > _maxSum) {
      _maxSum = sum.toDouble();
      bottomRight = img.Point(x, y);
    }
    if (diff > _maxDiff) {
      _maxDiff = diff.toDouble();
      topRight = img.Point(x, y);
    }
    if (inverseDiff > _maxInvDiff) {
      _maxInvDiff = inverseDiff.toDouble();
      bottomLeft = img.Point(x, y);
    }
  }

  double get centerX => area == 0 ? 0 : sumX / area;
  double get centerY => area == 0 ? 0 : sumY / area;
  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
}

Uint8List _processImageBytes(_ImageTransformRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    return request.bytes;
  }

  final filter = ImageFilterType.values[request.filterIndex];
  final quality = ScanProcessingQuality.values[request.qualityIndex];
  var transformed = _normalizeSourceOrientation(decoded);

  transformed = _resizeForProcessing(transformed, quality: quality);
  var detectedQuad = _detectDocumentQuad(transformed, quality: quality);
  if (detectedQuad == null) {
    final marginW = (transformed.width * 0.015).round();
    final marginH = (transformed.height * 0.015).round();
    detectedQuad = _DocumentQuad(
      topLeft: img.Point(marginW, marginH),
      topRight: img.Point(transformed.width - 1 - marginW, marginH),
      bottomLeft: img.Point(marginW, transformed.height - 1 - marginH),
      bottomRight: img.Point(
        transformed.width - 1 - marginW,
        transformed.height - 1 - marginH,
      ),
    );
  }
  transformed = _rectifyDocumentPerspective(transformed, detectedQuad);

  switch (filter) {
    case ImageFilterType.enhance:
    case ImageFilterType.magic:
      transformed = _applyDocumentScanLook(transformed, quality: quality);
      break;
    case ImageFilterType.original:
    case ImageFilterType.lighten:
      transformed = _applyColorScanLook(transformed, quality: quality);
      break;
    case ImageFilterType.gray:
      transformed = _applyGrayscaleScanLook(transformed, quality: quality);
      break;
    case ImageFilterType.bw:
    case ImageFilterType.eco:
    case ImageFilterType.noHandwriting:
      transformed = _applyBlackWhiteDocumentLook(transformed, quality: quality);
      break;
  }

  final normalizedTurns = request.quarterTurns % 4;
  if (normalizedTurns != 0) {
    transformed = img.copyRotate(transformed, angle: normalizedTurns * 90);
  }

  final jpegQuality = switch (quality) {
    ScanProcessingQuality.enhanced => 90,
    ScanProcessingQuality.balanced => 82,
    ScanProcessingQuality.preview => 74,
  };
  return Uint8List.fromList(img.encodeJpg(transformed, quality: jpegQuality));
}

Uint8List _rotateImageBytes(Uint8List bytes, int quarterTurns) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  var transformed = _normalizeSourceOrientation(decoded);
  final normalizedTurns = quarterTurns % 4;
  if (normalizedTurns != 0) {
    transformed = img.copyRotate(transformed, angle: normalizedTurns * 90);
  }

  return Uint8List.fromList(img.encodeJpg(transformed, quality: 88));
}

img.Image _normalizeSourceOrientation(img.Image source) {
  final orientation = source.exif.imageIfd.orientation ?? 1;
  if (orientation != 1) {
    return img.bakeOrientation(source);
  }
  return source;
}

img.Image _resizeForProcessing(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  final (maxWidth, maxHeight) = switch (quality) {
    ScanProcessingQuality.enhanced => (1500, 2000),
    ScanProcessingQuality.balanced => (1280, 1720),
    ScanProcessingQuality.preview => (960, 1280),
  };

  if (source.width <= maxWidth && source.height <= maxHeight) {
    return img.Image.from(source);
  }

  final widthRatio = maxWidth / source.width;
  final heightRatio = maxHeight / source.height;
  final scale = math.min(widthRatio, heightRatio);

  return img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}

img.Image _dilateImageGrayscale(img.Image small, int radius) {
  final width = small.width;
  final height = small.height;
  final result = img.Image(
    width: width,
    height: height,
    numChannels: small.numChannels,
  );

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var maxVal = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        final ny = (y + dy).clamp(0, height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final nx = (x + dx).clamp(0, width - 1);
          final val = small.getPixel(nx, ny).r.toInt();
          if (val > maxVal) {
            maxVal = val;
          }
        }
      }
      final p = result.getPixel(x, y);
      p.r = maxVal;
      if (result.numChannels > 1) {
        p.g = maxVal;
        p.b = maxVal;
      }
    }
  }
  return result;
}

img.Image _dilateImageColor(img.Image small, int radius) {
  final width = small.width;
  final height = small.height;
  final result = img.Image(
    width: width,
    height: height,
    numChannels: small.numChannels,
  );

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var maxR = 0;
      var maxG = 0;
      var maxB = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        final ny = (y + dy).clamp(0, height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final nx = (x + dx).clamp(0, width - 1);
          final p = small.getPixel(nx, ny);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          if (r > maxR) maxR = r;
          if (g > maxG) maxG = g;
          if (b > maxB) maxB = b;
        }
      }
      final destPixel = result.getPixel(x, y);
      destPixel.r = maxR;
      destPixel.g = maxG;
      destPixel.b = maxB;
    }
  }
  return result;
}

img.Image _estimateGrayscaleBackground(img.Image gray) {
  final blurRadius = _computeIlluminationBlurRadius(gray.width, gray.height);
  return _buildIlluminationMap(gray, blurRadius);
}

int _computeIlluminationBlurRadius(int width, int height) {
  final shorterSide = math.min(width, height);
  return (shorterSide * 40 / 1200).round().clamp(20, 60);
}

img.Image _buildIlluminationMap(img.Image gray, int blurRadius) {
  final mapWidth = math.max(120, math.min(400, gray.width ~/ 2));
  var small = img.copyResize(
    gray,
    width: mapWidth,
    interpolation: img.Interpolation.linear,
  );
  final scaledRadius = (blurRadius * mapWidth / gray.width).round().clamp(
    3,
    50,
  );
  final dilated = _dilateImageGrayscale(small, math.max(1, scaledRadius ~/ 10));
  return _integralBoxBlurGrayscale(dilated, scaledRadius);
}

img.Image _applyFastDenoise(img.Image source) {
  final data = _buildIntegralDataColor(source);
  final width = source.width;
  final height = source.height;
  final dst = img.Image.from(source);
  const radius = 1;
  const blendRatio = 0.25;
  const baseRatio = 1.0 - blendRatio;

  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final x1 = x - radius;
    final y1 = y - radius;
    final x2 = x + radius;
    final y2 = y + radius;

    final cx1 = x1.clamp(0, width - 1);
    final cy1 = y1.clamp(0, height - 1);
    final cx2 = x2.clamp(0, width - 1);
    final cy2 = y2.clamp(0, height - 1);
    final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);

    final blurredR =
        _getIntegralSum(data.r, width, height, x1, y1, x2, y2) / count;
    final blurredG =
        _getIntegralSum(data.g, width, height, x1, y1, x2, y2) / count;
    final blurredB =
        _getIntegralSum(data.b, width, height, x1, y1, x2, y2) / count;

    pixel
      ..r = (pixel.r * baseRatio + blurredR * blendRatio).round().clamp(0, 255)
      ..g = (pixel.g * baseRatio + blurredG * blendRatio).round().clamp(0, 255)
      ..b = (pixel.b * baseRatio + blurredB * blendRatio).round().clamp(0, 255);
  }

  return dst;
}

img.Image _applyDocumentContrast(img.Image source) {
  final hasColor = source.numChannels >= 3;

  if (!hasColor) {
    // Grayscale path (B&W document mode)
    final dst = img.Image.from(source);
    for (final pixel in dst) {
      final flat = pixel.r.toDouble();
      final double val;
      if (flat >= 215.0) {
        val = 255.0;
      } else if (flat <= 70.0) {
        val = 0.0;
      } else {
        val = ((flat - 70.0) / (215.0 - 70.0)) * 255.0;
      }
      final intVal = val.round().clamp(0, 255);
      pixel
        ..r = intVal
        ..g = intVal
        ..b = intVal;
    }
    return dst;
  }

  // Color path: apply contrast curve to each channel independently
  // This brightens paper background and darkens ink without losing color.
  final dst = img.Image.from(source);
  for (final pixel in dst) {
    double applyContrast(double v) {
      if (v >= 215.0) return 255.0;
      if (v <= 70.0) {
        return v * 0.6; // Darken shadows slightly, don't crush to 0
      }
      return ((v - 70.0) / (215.0 - 70.0)) * 255.0;
    }

    pixel.r = applyContrast(pixel.r.toDouble()).round().clamp(0, 255);
    pixel.g = applyContrast(pixel.g.toDouble()).round().clamp(0, 255);
    pixel.b = applyContrast(pixel.b.toDouble()).round().clamp(0, 255);
  }
  return dst;
}

img.Image _applyAdaptiveThresholdBw(img.Image source) {
  final gray = source.numChannels == 1 ? source : img.grayscale(source);
  final width = gray.width;
  final height = gray.height;

  final data = _buildIntegralDataGrayscale(gray);
  final dst = img.Image.from(gray);

  // Sauvola params
  const k = 0.2; // typical 0.2 to 0.5
  const R = 128.0;
  final windowSize = math.max(15, math.min(width, height) ~/ 30);
  final radius = windowSize ~/ 2;

  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;

    final x1 = x - radius;
    final y1 = y - radius;
    final x2 = x + radius;
    final y2 = y + radius;

    // Exact bounds for count
    final cx1 = x1.clamp(0, width - 1);
    final cy1 = y1.clamp(0, height - 1);
    final cx2 = x2.clamp(0, width - 1);
    final cy2 = y2.clamp(0, height - 1);
    final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);

    final sum = _getIntegralSum(data.integral, width, height, x1, y1, x2, y2);
    final sumSq = _getIntegralSum(
      data.integralSq,
      width,
      height,
      x1,
      y1,
      x2,
      y2,
    );

    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    final stddev = variance > 0 ? math.sqrt(variance) : 0.0;

    final threshold = mean * (1.0 + k * ((stddev / R) - 1.0));

    final val = pixel.r >= threshold ? 255 : 0;
    pixel
      ..r = val
      ..g = val
      ..b = val;
  }
  return dst;
}

img.Image _applyDivisionShadowRemoval(
  img.Image source, {
  required int blurRadius,
}) {
  final hasColor = source.numChannels >= 3;
  debugPrint(
    '[EnhancementPipeline][ColorDiag] Step 6 internals source.numChannels=${source.numChannels} hasColor=$hasColor',
  );

  // Build illumination map from grayscale (to estimate background brightness only)
  _logColorDiagnostic(
    'Step 6 before img.grayscale(img.Image.from(source))',
    source,
  );
  final gray = img.grayscale(img.Image.from(source));
  _logColorDiagnostic(
    'Step 6 after img.grayscale(img.Image.from(source)) - source',
    source,
  );
  _logColorDiagnostic(
    'Step 6 after img.grayscale(img.Image.from(source)) - gray',
    gray,
  );
  final background = _buildIlluminationMap(gray, blurRadius);

  final bgWidth = background.width;
  final bgHeight = background.height;
  final scaleX = bgWidth <= 1 ? 0.0 : (bgWidth - 1) / (source.width - 1);
  final scaleY = bgHeight <= 1 ? 0.0 : (bgHeight - 1) / (source.height - 1);
  final x0Cache = List<int>.filled(source.width, 0);
  final x1Cache = List<int>.filled(source.width, 0);
  final txCache = List<double>.filled(source.width, 0.0);
  final y0Cache = List<int>.filled(source.height, 0);
  final y1Cache = List<int>.filled(source.height, 0);
  final tyCache = List<double>.filled(source.height, 0.0);

  for (var x = 0; x < source.width; x++) {
    final bx = x * scaleX;
    final x0 = bx.floor().clamp(0, bgWidth - 1);
    x0Cache[x] = x0;
    x1Cache[x] = (x0 + 1).clamp(0, bgWidth - 1);
    txCache[x] = bx - x0;
  }

  for (var y = 0; y < source.height; y++) {
    final by = y * scaleY;
    final y0 = by.floor().clamp(0, bgHeight - 1);
    y0Cache[y] = y0;
    y1Cache[y] = (y0 + 1).clamp(0, bgHeight - 1);
    tyCache[y] = by - y0;
  }

  // Apply illumination correction to SOURCE (preserving color if present)
  final dst = img.Image.from(source);
  var loggedColorSample = false;
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final originalPixel = source.getPixel(x, y);
    final originalR = originalPixel.r.toInt();
    final originalG = originalPixel.g.toInt();
    final originalB = originalPixel.b.toInt();
    final x0 = x0Cache[x];
    final x1 = x1Cache[x];
    final y0 = y0Cache[y];
    final y1 = y1Cache[y];
    final tx = txCache[x];
    final ty = tyCache[y];

    final p00 = background.getPixel(x0, y0).r.toDouble();
    final p10 = background.getPixel(x1, y0).r.toDouble();
    final p01 = background.getPixel(x0, y1).r.toDouble();
    final p11 = background.getPixel(x1, y1).r.toDouble();
    final bgVal =
        p00 * (1.0 - tx) * (1.0 - ty) +
        p10 * tx * (1.0 - ty) +
        p01 * (1.0 - tx) * ty +
        p11 * tx * ty;

    final illumination = math.max(8.0, bgVal);
    final scale = 255.0 / illumination;

    pixel.r = (pixel.r.toDouble() * scale).round().clamp(0, 255);
    if (hasColor) {
      pixel.g = (pixel.g.toDouble() * scale).round().clamp(0, 255);
      pixel.b = (pixel.b.toDouble() * scale).round().clamp(0, 255);
    } else {
      pixel.g = pixel.r;
      pixel.b = pixel.r;
    }
    if (!loggedColorSample && (originalR - originalB).abs() > 20) {
      loggedColorSample = true;
      debugPrint(
        '[EnhancementPipeline][ColorDiag] Step 6 sample x=$x y=$y before=($originalR,$originalG,$originalB) after=(${pixel.r.toInt()},${pixel.g.toInt()},${pixel.b.toInt()}) bgVal=${bgVal.toStringAsFixed(2)} scale=${scale.toStringAsFixed(3)}',
      );
    }
  }

  return dst;
}

img.Image _applyHistogramStretch(img.Image source) {
  final histogram = List<int>.filled(256, 0);
  final hasColor = source.numChannels >= 3;
  final totalPixels = source.width * source.height;

  for (final pixel in source) {
    final luminance = hasColor
        ? _luminance(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt())
        : pixel.r.toInt();
    histogram[luminance]++;
  }

  final lowTarget = (totalPixels * 0.02).round();
  final highTarget = (totalPixels * 0.95).round();

  var cumulative = 0;
  var low = 0;
  var high = 255;

  for (var i = 0; i < 256; i++) {
    cumulative += histogram[i];
    if (cumulative >= lowTarget) {
      low = i;
      break;
    }
  }

  cumulative = 0;
  for (var i = 255; i >= 0; i--) {
    cumulative += histogram[i];
    if (cumulative >= totalPixels - highTarget) {
      high = i;
      break;
    }
  }

  if (high <= low + 8) {
    return img.Image.from(source);
  }

  final dst = img.Image.from(source);
  final range = (high - low).toDouble();
  double stretchChannel(num value) {
    final stretched = ((value.toDouble() - low) / range) * 255.0;
    return stretched >= 230.0 ? 255.0 : stretched.clamp(0.0, 255.0);
  }

  for (final pixel in dst) {
    if (!hasColor) {
      final value = pixel.r.toDouble();
      final stretched = ((value - low) / range) * 255.0;
      final intVal = stretched >= 230.0 ? 255 : stretched.round().clamp(0, 255);
      pixel
        ..r = intVal
        ..g = intVal
        ..b = intVal;
    } else {
      pixel
        ..r = stretchChannel(pixel.r).round()
        ..g = stretchChannel(pixel.g).round()
        ..b = stretchChannel(pixel.b).round();
    }
  }

  return dst;
}

img.Image _estimateColorBackground(img.Image source) {
  final small = img.copyResize(
    source,
    width: 120,
    interpolation: img.Interpolation.linear,
  );
  final dilated = _dilateImageColor(small, 2);
  return img.gaussianBlur(dilated, radius: 2);
}

img.Image _applyDocumentScanLook(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  var gray = img.grayscale(source);
  final background = _estimateGrayscaleBackground(gray);

  final bgWidth = background.width;
  final bgHeight = background.height;
  final scaleX = (bgWidth - 1) / (gray.width - 1);
  final scaleY = (bgHeight - 1) / (gray.height - 1);

  final dst = img.Image.from(gray);
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final bx = x * scaleX;
    final by = y * scaleY;

    final x0 = bx.floor();
    final x1 = (x0 + 1).clamp(0, bgWidth - 1);
    final y0 = by.floor();
    final y1 = (y0 + 1).clamp(0, bgHeight - 1);
    final tx = bx - x0;
    final ty = by - y0;

    final p00 = background.getPixel(x0, y0).r.toDouble();
    final p10 = background.getPixel(x1, y0).r.toDouble();
    final p01 = background.getPixel(x0, y1).r.toDouble();
    final p11 = background.getPixel(x1, y1).r.toDouble();

    final bgVal =
        p00 * (1.0 - tx) * (1.0 - ty) +
        p10 * tx * (1.0 - ty) +
        p01 * (1.0 - tx) * ty +
        p11 * tx * ty;

    final L = math.max(1.0, bgVal);
    final P = pixel.r.toDouble();
    final ratio = P / L;
    final flat = ratio * 255.0;

    double val;
    if (flat >= 215.0) {
      val = 255.0;
    } else if (flat <= 70.0) {
      val = 0.0;
    } else {
      val = ((flat - 70.0) / (215.0 - 70.0)) * 255.0;
    }

    final intVal = val.round().clamp(0, 255);
    pixel
      ..r = intVal
      ..g = intVal
      ..b = intVal;
  }

  return _fastSharpen(dst);
}

img.Image _applyColorScanLook(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  final background = _estimateColorBackground(source);

  final bgWidth = background.width;
  final bgHeight = background.height;
  final scaleX = (bgWidth - 1) / (source.width - 1);
  final scaleY = (bgHeight - 1) / (source.height - 1);

  final dst = img.Image.from(source);
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final bx = x * scaleX;
    final by = y * scaleY;

    final x0 = bx.floor();
    final x1 = (x0 + 1).clamp(0, bgWidth - 1);
    final y0 = by.floor();
    final y1 = (y0 + 1).clamp(0, bgHeight - 1);
    final tx = bx - x0;
    final ty = by - y0;

    final p00 = background.getPixel(x0, y0);
    final p10 = background.getPixel(x1, y0);
    final p01 = background.getPixel(x0, y1);
    final p11 = background.getPixel(x1, y1);

    final bgR =
        p00.r.toDouble() * (1.0 - tx) * (1.0 - ty) +
        p10.r.toDouble() * tx * (1.0 - ty) +
        p01.r.toDouble() * (1.0 - tx) * ty +
        p11.r.toDouble() * tx * ty;

    final bgG =
        p00.g.toDouble() * (1.0 - tx) * (1.0 - ty) +
        p10.g.toDouble() * tx * (1.0 - ty) +
        p01.g.toDouble() * (1.0 - tx) * ty +
        p11.g.toDouble() * tx * ty;

    final bgB =
        p00.b.toDouble() * (1.0 - tx) * (1.0 - ty) +
        p10.b.toDouble() * tx * (1.0 - ty) +
        p01.b.toDouble() * (1.0 - tx) * ty +
        p11.b.toDouble() * tx * ty;

    final flatR = (pixel.r.toDouble() / math.max(1.0, bgR)) * 255.0;
    final flatG = (pixel.g.toDouble() / math.max(1.0, bgG)) * 255.0;
    final flatB = (pixel.b.toDouble() / math.max(1.0, bgB)) * 255.0;

    // Hue-preserving contrast enhancement on luminance
    final flatLum = 0.299 * flatR + 0.587 * flatG + 0.114 * flatB;

    double targetLum;
    if (flatLum >= 215.0) {
      targetLum = 255.0;
    } else if (flatLum <= 60.0) {
      targetLum = flatLum * 0.75;
    } else {
      targetLum = 10.0 + ((flatLum - 60.0) / (215.0 - 60.0)) * (255.0 - 10.0);
    }

    final scale = targetLum / math.max(1.0, flatLum);
    var r = flatR * scale;
    var g = flatG * scale;
    var b = flatB * scale;

    // Soft white paper blending for background pixels
    final newLum = targetLum;
    final maxVal = math.max(r, math.max(g, b));
    final minVal = math.min(r, math.min(g, b));
    final colorness = maxVal - minVal;

    final lumWeight = ((newLum - 175.0) / (215.0 - 175.0)).clamp(0.0, 1.0);
    final satWeight = (1.0 - (colorness / 30.0)).clamp(0.0, 1.0);
    final bgWeight = lumWeight * satWeight;

    if (bgWeight > 0.0) {
      r = r + (255.0 - r) * bgWeight;
      g = g + (255.0 - g) * bgWeight;
      b = b + (255.0 - b) * bgWeight;
    }

    pixel
      ..r = r.round().clamp(0, 255)
      ..g = g.round().clamp(0, 255)
      ..b = b.round().clamp(0, 255);
  }

  return _fastColorSharpen(dst);
}

img.Image _applyGrayscaleScanLook(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  var gray = img.grayscale(source);
  final background = _estimateGrayscaleBackground(gray);

  final bgWidth = background.width;
  final bgHeight = background.height;
  final scaleX = (bgWidth - 1) / (gray.width - 1);
  final scaleY = (bgHeight - 1) / (gray.height - 1);

  final dst = img.Image.from(gray);
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final bx = x * scaleX;
    final by = y * scaleY;

    final x0 = bx.floor();
    final x1 = (x0 + 1).clamp(0, bgWidth - 1);
    final y0 = by.floor();
    final y1 = (y0 + 1).clamp(0, bgHeight - 1);
    final tx = bx - x0;
    final ty = by - y0;

    final p00 = background.getPixel(x0, y0).r.toDouble();
    final p10 = background.getPixel(x1, y0).r.toDouble();
    final p01 = background.getPixel(x0, y1).r.toDouble();
    final p11 = background.getPixel(x1, y1).r.toDouble();

    final bgVal =
        p00 * (1.0 - tx) * (1.0 - ty) +
        p10 * tx * (1.0 - ty) +
        p01 * (1.0 - tx) * ty +
        p11 * tx * ty;

    final L = math.max(1.0, bgVal);
    final P = pixel.r.toDouble();
    final ratio = P / L;
    final flat = ratio * 255.0;

    double val;
    if (flat >= 225.0) {
      val = 255.0;
    } else if (flat <= 45.0) {
      val = 15.0;
    } else {
      val = 15.0 + ((flat - 45.0) / (225.0 - 45.0)) * (255.0 - 15.0);
    }

    final intVal = val.round().clamp(0, 255);
    pixel
      ..r = intVal
      ..g = intVal
      ..b = intVal;
  }

  return _fastSharpen(dst);
}

img.Image _applyBlackWhiteDocumentLook(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  var gray = img.grayscale(source);
  final background = _estimateGrayscaleBackground(gray);

  final bgWidth = background.width;
  final bgHeight = background.height;
  final scaleX = (bgWidth - 1) / (gray.width - 1);
  final scaleY = (bgHeight - 1) / (gray.height - 1);

  final dst = img.Image.from(gray);
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final bx = x * scaleX;
    final by = y * scaleY;

    final x0 = bx.floor();
    final x1 = (x0 + 1).clamp(0, bgWidth - 1);
    final y0 = by.floor();
    final y1 = (y0 + 1).clamp(0, bgHeight - 1);
    final tx = bx - x0;
    final ty = by - y0;

    final p00 = background.getPixel(x0, y0).r.toDouble();
    final p10 = background.getPixel(x1, y0).r.toDouble();
    final p01 = background.getPixel(x0, y1).r.toDouble();
    final p11 = background.getPixel(x1, y1).r.toDouble();

    final bgVal =
        p00 * (1.0 - tx) * (1.0 - ty) +
        p10 * tx * (1.0 - ty) +
        p01 * (1.0 - tx) * ty +
        p11 * tx * ty;

    final L = math.max(1.0, bgVal);
    final P = pixel.r.toDouble();
    final ratio = P / L;
    final flat = (ratio * 255.0).round().clamp(0, 255);

    pixel
      ..r = flat
      ..g = flat
      ..b = flat;
  }

  // Compute Otsu on the flattened image
  final T = _computeOtsuThreshold(dst);
  // Slightly adjust threshold to prevent too fat text
  final threshold = (T - 8).clamp(100, 220);

  for (final pixel in dst) {
    final val = pixel.r >= threshold ? 255 : 0;
    pixel
      ..r = val
      ..g = val
      ..b = val;
  }

  return dst;
}

_DocumentQuad? _detectDocumentQuad(
  img.Image source, {
  required ScanProcessingQuality quality,
}) {
  final detectionLongEdge = switch (quality) {
    ScanProcessingQuality.enhanced => 420,
    ScanProcessingQuality.balanced => 320,
    ScanProcessingQuality.preview => 240,
  };
  final longerSide = math.max(source.width, source.height);
  final probe = longerSide > detectionLongEdge
      ? img.copyResize(
          source,
          width: source.width >= source.height ? detectionLongEdge : null,
          height: source.height > source.width ? detectionLongEdge : null,
          interpolation: img.Interpolation.linear,
        )
      : img.Image.from(source);

  var grayscale = img.grayscale(probe);
  grayscale = _flattenPaperLighting(grayscale);
  grayscale = img.gaussianBlur(grayscale, radius: 1);

  final width = grayscale.width;
  final height = grayscale.height;
  final threshold = (_computeOtsuThreshold(grayscale) - 8).clamp(116, 235);
  var mask = _buildPaperMask(grayscale, threshold);

  // Apply Morphological Closing to bridge shadows/fold marks in crumpled paper
  final closeRadius = switch (quality) {
    ScanProcessingQuality.enhanced => 3,
    ScanProcessingQuality.balanced => 2,
    ScanProcessingQuality.preview => 1,
  };
  mask = _closeMask(mask, width, height, closeRadius);

  mask = _smoothMask(
    mask,
    width,
    height,
    passes: quality == ScanProcessingQuality.enhanced ? 2 : 1,
  );
  final component = _findLargestMaskComponent(mask, width, height);
  if (component == null) {
    return null;
  }

  final areaRatio = component.area / (width * height);
  final bboxWidthRatio = component.width / width;
  final bboxHeightRatio = component.height / height;
  final touchesEveryBorder =
      component.minX <= 2 &&
      component.minY <= 2 &&
      component.maxX >= width - 3 &&
      component.maxY >= height - 3;

  if (areaRatio < 0.18) {
    return null;
  }
  if (bboxWidthRatio < 0.5 || bboxHeightRatio < 0.5) {
    return null;
  }
  if (touchesEveryBorder && areaRatio > 0.92) {
    return null;
  }

  final scaleX = source.width / width;
  final scaleY = source.height / height;
  final quad = _DocumentQuad(
    topLeft: img.Point(
      component.topLeft.x * scaleX,
      component.topLeft.y * scaleY,
    ),
    topRight: img.Point(
      component.topRight.x * scaleX,
      component.topRight.y * scaleY,
    ),
    bottomLeft: img.Point(
      component.bottomLeft.x * scaleX,
      component.bottomLeft.y * scaleY,
    ),
    bottomRight: img.Point(
      component.bottomRight.x * scaleX,
      component.bottomRight.y * scaleY,
    ),
  );

  return _isValidQuad(quad, source) ? quad : null;
}

List<bool> _buildPaperMask(img.Image source, int threshold) {
  final mask = List<bool>.filled(source.width * source.height, false);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final luminance = source.getPixel(x, y).r.toInt();
      final isPaper = luminance >= threshold;
      mask[y * source.width + x] = isPaper;
    }
  }
  return mask;
}

List<bool> _closeMask(List<bool> mask, int width, int height, int radius) {
  // 1. Dilate
  final temp = List<bool>.filled(mask.length, false);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (mask[y * width + x]) {
        for (var dy = -radius; dy <= radius; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            temp[ny * width + nx] = true;
          }
        }
      }
    }
  }
  // 2. Erode
  final result = List<bool>.filled(mask.length, false);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (temp[y * width + x]) {
        var allTrue = true;
        for (var dy = -radius; dy <= radius; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) {
            allTrue = false;
            break;
          }
          for (var dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) {
              allTrue = false;
              break;
            }
            if (!temp[ny * width + nx]) {
              allTrue = false;
              break;
            }
          }
          if (!allTrue) break;
        }
        result[y * width + x] = allTrue;
      }
    }
  }
  return result;
}

List<bool> _smoothMask(
  List<bool> source,
  int width,
  int height, {
  int passes = 1,
}) {
  var current = source;
  for (var pass = 0; pass < passes; pass++) {
    final next = List<bool>.filled(current.length, false);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var activeNeighbors = 0;
        var totalNeighbors = 0;
        for (var offsetY = -1; offsetY <= 1; offsetY++) {
          final ny = y + offsetY;
          if (ny < 0 || ny >= height) continue;
          for (var offsetX = -1; offsetX <= 1; offsetX++) {
            final nx = x + offsetX;
            if (nx < 0 || nx >= width) continue;
            totalNeighbors++;
            if (current[ny * width + nx]) {
              activeNeighbors++;
            }
          }
        }
        next[y * width + x] =
            activeNeighbors >= math.max(4, totalNeighbors ~/ 2);
      }
    }
    current = next;
  }
  return current;
}

_MaskComponent? _findLargestMaskComponent(
  List<bool> mask,
  int width,
  int height,
) {
  final visited = List<bool>.filled(mask.length, false);
  _MaskComponent? best;
  final queue = <int>[];

  for (var index = 0; index < mask.length; index++) {
    if (!mask[index] || visited[index]) {
      continue;
    }

    visited[index] = true;
    queue
      ..clear()
      ..add(index);
    final component = _MaskComponent(index % width, index ~/ width);

    for (var cursor = 0; cursor < queue.length; cursor++) {
      final current = queue[cursor];
      final x = current % width;
      final y = current ~/ width;
      component.include(x, y);

      if (x > 0) {
        final left = current - 1;
        if (mask[left] && !visited[left]) {
          visited[left] = true;
          queue.add(left);
        }
      }
      if (x < width - 1) {
        final right = current + 1;
        if (mask[right] && !visited[right]) {
          visited[right] = true;
          queue.add(right);
        }
      }
      if (y > 0) {
        final up = current - width;
        if (mask[up] && !visited[up]) {
          visited[up] = true;
          queue.add(up);
        }
      }
      if (y < height - 1) {
        final down = current + width;
        if (mask[down] && !visited[down]) {
          visited[down] = true;
          queue.add(down);
        }
      }
    }

    if (best == null || component.area > best.area) {
      best = component;
    }
  }

  return best;
}

bool _isValidQuad(_DocumentQuad quad, img.Image source) {
  final topWidth = _distance(quad.topLeft, quad.topRight);
  final bottomWidth = _distance(quad.bottomLeft, quad.bottomRight);
  final leftHeight = _distance(quad.topLeft, quad.bottomLeft);
  final rightHeight = _distance(quad.topRight, quad.bottomRight);
  final width = math.max(topWidth, bottomWidth);
  final height = math.max(leftHeight, rightHeight);
  if (width < source.width * 0.45 || height < source.height * 0.45) {
    return false;
  }

  final polygonArea = _polygonArea([
    quad.topLeft,
    quad.topRight,
    quad.bottomRight,
    quad.bottomLeft,
  ]);
  final imageArea = source.width * source.height;
  return polygonArea > imageArea * 0.18 && polygonArea < imageArea * 0.98;
}

img.Image _rectifyDocumentPerspective(img.Image source, _DocumentQuad quad) {
  final topWidth = _distance(quad.topLeft, quad.topRight);
  final bottomWidth = _distance(quad.bottomLeft, quad.bottomRight);
  final leftHeight = _distance(quad.topLeft, quad.bottomLeft);
  final rightHeight = _distance(quad.topRight, quad.bottomRight);

  var targetWidth = math.max(topWidth, bottomWidth).round();
  var targetHeight = math.max(leftHeight, rightHeight).round();

  final longestSide = math.max(targetWidth, targetHeight);
  if (longestSide > 1900) {
    final scale = 1900 / longestSide;
    targetWidth = math.max(400, (targetWidth * scale).round());
    targetHeight = math.max(560, (targetHeight * scale).round());
  }

  final destination = img.Image(
    width: targetWidth.clamp(400, 1900),
    height: targetHeight.clamp(560, 2300),
    numChannels: 3,
  );

  final rectified = img.copyRectify(
    source,
    topLeft: quad.topLeft,
    topRight: quad.topRight,
    bottomLeft: quad.bottomLeft,
    bottomRight: quad.bottomRight,
    interpolation: img.Interpolation.linear,
    toImage: destination,
  );

  return _trimResidualBorder(rectified);
}

img.Image _trimResidualBorder(img.Image source) {
  final probe = img.grayscale(img.Image.from(source));
  final width = probe.width;
  final height = probe.height;

  int top = 0;
  int bottom = height - 1;
  int left = 0;
  int right = width - 1;

  double rowInkRatio(int y) {
    var darkPixels = 0;
    for (var x = 0; x < width; x++) {
      if (probe.getPixel(x, y).r.toInt() < 245) {
        darkPixels++;
      }
    }
    return darkPixels / width;
  }

  double columnInkRatio(int x) {
    var darkPixels = 0;
    for (var y = 0; y < height; y++) {
      if (probe.getPixel(x, y).r.toInt() < 245) {
        darkPixels++;
      }
    }
    return darkPixels / height;
  }

  while (top < bottom && rowInkRatio(top) < 0.012) {
    top++;
  }
  while (bottom > top && rowInkRatio(bottom) < 0.012) {
    bottom--;
  }
  while (left < right && columnInkRatio(left) < 0.012) {
    left++;
  }
  while (right > left && columnInkRatio(right) < 0.012) {
    right--;
  }

  final cropWidth = right - left + 1;
  final cropHeight = bottom - top + 1;
  if (cropWidth < width * 0.72 || cropHeight < height * 0.72) {
    return source;
  }

  return img.copyCrop(
    source,
    x: left,
    y: top,
    width: cropWidth,
    height: cropHeight,
  );
}

img.Image _flattenPaperLighting(img.Image source) {
  final backgroundWidth = math.max(40, math.min(96, source.width ~/ 12));
  var background = img.copyResize(
    source,
    width: backgroundWidth,
    interpolation: img.Interpolation.linear,
  );
  background = img.gaussianBlur(background, radius: 1);

  final dst = img.Image.from(source);
  final maxX = background.width - 1;
  final maxY = background.height - 1;

  for (final pixel in dst) {
    final backgroundX = ((pixel.x / dst.width) * maxX).round().clamp(0, maxX);
    final backgroundY = ((pixel.y / dst.height) * maxY).round().clamp(0, maxY);
    final bgPixel = background.getPixel(backgroundX, backgroundY);
    final backgroundLum = math.max(70, bgPixel.r.toInt());
    final foregroundLum = pixel.r.toInt();

    final corrected = ((foregroundLum * 210) / backgroundLum).round().clamp(
      0,
      255,
    );

    pixel
      ..r = corrected
      ..g = corrected
      ..b = corrected;
  }

  return dst;
}

img.Image _fastSharpen(img.Image source) {
  final hasColor = source.numChannels >= 3;
  const radius = 2;
  const strength = 0.18;
  final width = source.width;
  final height = source.height;

  if (!hasColor) {
    final data = _buildIntegralDataGrayscale(source);
    final dst = img.Image.from(source);
    for (final p in dst) {
      final x = p.x;
      final y = p.y;
      final x1 = x - radius;
      final y1 = y - radius;
      final x2 = x + radius;
      final y2 = y + radius;

      final cx1 = x1.clamp(0, width - 1);
      final cy1 = y1.clamp(0, height - 1);
      final cx2 = x2.clamp(0, width - 1);
      final cy2 = y2.clamp(0, height - 1);
      final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);
      final blurred =
          _getIntegralSum(data.integral, width, height, x1, y1, x2, y2) / count;
      final value = (p.r + strength * (p.r - blurred)).round().clamp(0, 255);
      p
        ..r = value
        ..g = value
        ..b = value;
    }
    return dst;
  }

  final lumIntegral = _buildIntegralLuminance(source);
  final dst = img.Image.from(source);
  for (final p in dst) {
    final x = p.x;
    final y = p.y;
    final x1 = x - radius;
    final y1 = y - radius;
    final x2 = x + radius;
    final y2 = y + radius;

    final cx1 = x1.clamp(0, width - 1);
    final cy1 = y1.clamp(0, height - 1);
    final cx2 = x2.clamp(0, width - 1);
    final cy2 = y2.clamp(0, height - 1);
    final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);

    final l = _luminance(p.r.toInt(), p.g.toInt(), p.b.toInt());
    final blurred =
        _getIntegralSum(lumIntegral, width, height, x1, y1, x2, y2) / count;
    final diff = strength * (l - blurred);
    p.r = (p.r + diff).round().clamp(0, 255);
    p.g = (p.g + diff).round().clamp(0, 255);
    p.b = (p.b + diff).round().clamp(0, 255);
  }
  return dst;
}

img.Image _applyUnsharpMask(
  img.Image source,
  img.Image blurred,
  double strength,
) {
  final dst = img.Image.from(source);
  for (final p in dst) {
    final b = blurred.getPixel(p.x, p.y).r.toInt();
    p.r = (p.r + strength * (p.r - b)).round().clamp(0, 255);
    p.g = (p.g + strength * (p.g - b)).round().clamp(0, 255);
    p.b = (p.b + strength * (p.b - b)).round().clamp(0, 255);
  }
  return dst;
}

img.Image _fastColorSharpen(img.Image source) {
  final width = source.width;
  final height = source.height;
  final dst = img.Image.from(source);

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final center = source.getPixel(x, y);
      if (center.r >= 248 && center.g >= 248 && center.b >= 248) {
        continue;
      }
      final left = source.getPixel(x - 1, y);
      final right = source.getPixel(x + 1, y);
      final up = source.getPixel(x, y - 1);
      final down = source.getPixel(x, y + 1);

      final blurredR = (left.r + right.r + up.r + down.r) ~/ 4;
      final blurredG = (left.g + right.g + up.g + down.g) ~/ 4;
      final blurredB = (left.b + right.b + up.b + down.b) ~/ 4;

      final r = (center.r + 0.25 * (center.r - blurredR)).round().clamp(0, 255);
      final g = (center.g + 0.25 * (center.g - blurredG)).round().clamp(0, 255);
      final b = (center.b + 0.25 * (center.b - blurredB)).round().clamp(0, 255);

      dst.setPixelRgb(x, y, r, g, b);
    }
  }
  return dst;
}

int _computeOtsuThreshold(img.Image source) {
  final histogram = List<int>.filled(256, 0);
  var total = 0;

  for (final pixel in source) {
    final luminance = _luminance(
      pixel.r.toInt(),
      pixel.g.toInt(),
      pixel.b.toInt(),
    );
    histogram[luminance]++;
    total++;
  }

  var sum = 0.0;
  for (var i = 0; i < histogram.length; i++) {
    sum += i * histogram[i];
  }

  var sumBackground = 0.0;
  var weightBackground = 0;
  var maxVariance = -1.0;
  var threshold = 145;

  for (var i = 0; i < histogram.length; i++) {
    weightBackground += histogram[i];
    if (weightBackground == 0) {
      continue;
    }

    final weightForeground = total - weightBackground;
    if (weightForeground == 0) {
      break;
    }

    sumBackground += i * histogram[i];
    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sum - sumBackground) / weightForeground;
    final variance =
        weightBackground *
        weightForeground *
        math.pow(meanBackground - meanForeground, 2);

    if (variance > maxVariance) {
      maxVariance = variance.toDouble();
      threshold = i;
    }
  }

  return threshold;
}

int _luminance(int r, int g, int b) {
  final value = (0.299 * r + 0.587 * g + 0.114 * b).round();
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value;
}

double _distance(img.Point a, img.Point b) {
  final dx = (a.x - b.x).toDouble();
  final dy = (a.y - b.y).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}

double _polygonArea(List<img.Point> points) {
  var area = 0.0;
  for (var i = 0; i < points.length; i++) {
    final current = points[i];
    final next = points[(i + 1) % points.length];
    area +=
        (current.x.toDouble() * next.y.toDouble()) -
        (next.x.toDouble() * current.y.toDouble());
  }
  return area.abs() / 2;
}

class _IntegralDataGrayscale {
  final List<int> integral;
  final List<int> integralSq;
  final int width;
  final int height;
  _IntegralDataGrayscale(
    this.integral,
    this.integralSq,
    this.width,
    this.height,
  );
}

_IntegralDataGrayscale _buildIntegralDataGrayscale(img.Image source) {
  final width = source.width;
  final height = source.height;
  final integral = List<int>.filled(width * height, 0);
  final integralSq = List<int>.filled(width * height, 0);

  for (var y = 0; y < height; y++) {
    int sum = 0;
    int sumSq = 0;
    for (var x = 0; x < width; x++) {
      final val = source.getPixel(x, y).r.toInt();
      sum += val;
      sumSq += val * val;
      final idx = y * width + x;
      if (y == 0) {
        integral[idx] = sum;
        integralSq[idx] = sumSq;
      } else {
        final prevIdx = (y - 1) * width + x;
        integral[idx] = integral[prevIdx] + sum;
        integralSq[idx] = integralSq[prevIdx] + sumSq;
      }
    }
  }
  return _IntegralDataGrayscale(integral, integralSq, width, height);
}

class _IntegralDataColor {
  final List<int> r, g, b;
  final int width, height;
  _IntegralDataColor(this.r, this.g, this.b, this.width, this.height);
}

_IntegralDataColor _buildIntegralDataColor(img.Image source) {
  final width = source.width;
  final height = source.height;
  final rArr = List<int>.filled(width * height, 0);
  final gArr = List<int>.filled(width * height, 0);
  final bArr = List<int>.filled(width * height, 0);

  for (var y = 0; y < height; y++) {
    int sumR = 0, sumG = 0, sumB = 0;
    for (var x = 0; x < width; x++) {
      final p = source.getPixel(x, y);
      sumR += p.r.toInt();
      sumG += p.g.toInt();
      sumB += p.b.toInt();

      final idx = y * width + x;
      if (y == 0) {
        rArr[idx] = sumR;
        gArr[idx] = sumG;
        bArr[idx] = sumB;
      } else {
        final prevIdx = (y - 1) * width + x;
        rArr[idx] = rArr[prevIdx] + sumR;
        gArr[idx] = gArr[prevIdx] + sumG;
        bArr[idx] = bArr[prevIdx] + sumB;
      }
    }
  }
  return _IntegralDataColor(rArr, gArr, bArr, width, height);
}

List<int> _buildIntegralLuminance(img.Image source) {
  final width = source.width;
  final height = source.height;
  final integral = List<int>.filled(width * height, 0);

  for (var y = 0; y < height; y++) {
    var sum = 0;
    for (var x = 0; x < width; x++) {
      final p = source.getPixel(x, y);
      sum += _luminance(p.r.toInt(), p.g.toInt(), p.b.toInt());
      final idx = y * width + x;
      integral[idx] = y == 0 ? sum : integral[(y - 1) * width + x] + sum;
    }
  }

  return integral;
}

int _getIntegralSum(
  List<int> integral,
  int width,
  int height,
  int x1,
  int y1,
  int x2,
  int y2,
) {
  final cx1 = x1.clamp(0, width - 1);
  final cy1 = y1.clamp(0, height - 1);
  final cx2 = x2.clamp(0, width - 1);
  final cy2 = y2.clamp(0, height - 1);

  final a = (cx1 > 0 && cy1 > 0) ? integral[(cy1 - 1) * width + (cx1 - 1)] : 0;
  final b = (cy1 > 0) ? integral[(cy1 - 1) * width + cx2] : 0;
  final c = (cx1 > 0) ? integral[cy2 * width + (cx1 - 1)] : 0;
  final d = integral[cy2 * width + cx2];

  return d - b - c + a;
}

img.Image _integralBoxBlurGrayscale(img.Image source, int radius) {
  if (radius <= 0) return img.Image.from(source);
  final width = source.width;
  final height = source.height;
  final integral = List<int>.filled(width * height, 0);

  for (var y = 0; y < height; y++) {
    int sum = 0;
    for (var x = 0; x < width; x++) {
      sum += source.getPixel(x, y).r.toInt();
      final idx = y * width + x;
      if (y == 0) {
        integral[idx] = sum;
      } else {
        integral[idx] = integral[(y - 1) * width + x] + sum;
      }
    }
  }

  final dst = img.Image(
    width: width,
    height: height,
    numChannels: source.numChannels,
  );
  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final x1 = x - radius;
    final y1 = y - radius;
    final x2 = x + radius;
    final y2 = y + radius;

    final cx1 = x1.clamp(0, width - 1);
    final cy1 = y1.clamp(0, height - 1);
    final cx2 = x2.clamp(0, width - 1);
    final cy2 = y2.clamp(0, height - 1);
    final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);

    final r = _getIntegralSum(integral, width, height, x1, y1, x2, y2) ~/ count;
    pixel
      ..r = r
      ..g = r
      ..b = r;
  }
  return dst;
}

img.Image _integralBoxBlurColor(img.Image source, int radius) {
  if (radius <= 0) return img.Image.from(source);
  final data = _buildIntegralDataColor(source);
  final width = source.width;
  final height = source.height;
  final dst = img.Image(width: width, height: height, numChannels: 3);

  for (final pixel in dst) {
    final x = pixel.x;
    final y = pixel.y;
    final x1 = x - radius;
    final y1 = y - radius;
    final x2 = x + radius;
    final y2 = y + radius;

    final cx1 = x1.clamp(0, width - 1);
    final cy1 = y1.clamp(0, height - 1);
    final cx2 = x2.clamp(0, width - 1);
    final cy2 = y2.clamp(0, height - 1);
    final count = (cx2 - cx1 + 1) * (cy2 - cy1 + 1);

    final r = _getIntegralSum(data.r, width, height, x1, y1, x2, y2) ~/ count;
    final g = _getIntegralSum(data.g, width, height, x1, y1, x2, y2) ~/ count;
    final b = _getIntegralSum(data.b, width, height, x1, y1, x2, y2) ~/ count;

    pixel
      ..r = r
      ..g = g
      ..b = b;
  }
  return dst;
}

img.Image _blendImages(img.Image base, img.Image blend, double blendRatio) {
  final dst = img.Image.from(base);
  final baseRatio = 1.0 - blendRatio;
  final dstIter = dst.iterator..moveNext();
  final blendIter = blend.iterator..moveNext();
  while (true) {
    final d = dstIter.current;
    final b = blendIter.current;
    d.r = (d.r * baseRatio + b.r * blendRatio).round().clamp(0, 255);
    d.g = (d.g * baseRatio + b.g * blendRatio).round().clamp(0, 255);
    d.b = (d.b * baseRatio + b.b * blendRatio).round().clamp(0, 255);
    if (!dstIter.moveNext() || !blendIter.moveNext()) break;
  }
  return dst;
}
