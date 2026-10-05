import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum SignatureInkColorMode {
  /// Keep original scanned ink colors (blue/black pen tint)
  original,

  /// Recolor ink to deep executive black
  executiveBlack,

  /// Recolor ink to authentic royal blue ballpoint pen
  royalBlue,
}

class SignatureExtractorService {
  /// Extracts ink strokes from a photo of a handwritten signature on paper,
  /// removes paper background completely (making it 100% transparent PNG),
  /// crops tightly to the ink bounding box, and optionally recolors ink.
  Future<Uint8List> extractTransparentSignatureFromBytes({
    required Uint8List imageBytes,
    double thresholdSensitivity = 0.82, // 0.60 to 0.95
    SignatureInkColorMode colorMode = SignatureInkColorMode.royalBlue,
  }) async {
    return compute(_extractIsolate, {
      'bytes': imageBytes,
      'sensitivity': thresholdSensitivity,
      'colorMode': colorMode.index,
    });
  }

  /// Convenience method taking a file path
  Future<Uint8List> extractTransparentSignatureFromFile({
    required String filePath,
    double thresholdSensitivity = 0.82,
    SignatureInkColorMode colorMode = SignatureInkColorMode.royalBlue,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return extractTransparentSignatureFromBytes(
      imageBytes: bytes,
      thresholdSensitivity: thresholdSensitivity,
      colorMode: colorMode,
    );
  }

  static Uint8List _extractIsolate(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'] as Uint8List;
    final double sensitivity = (params['sensitivity'] as num).toDouble();
    final int colorModeIdx = params['colorMode'] as int;
    final colorMode = SignatureInkColorMode.values[colorModeIdx];

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw StateError('Could not decode signature image');
    }

    // Downscale if image is gigantic (> 1600px) to keep memory & speed optimal
    img.Image source = decoded;
    if (source.width > 1600 || source.height > 1600) {
      final longer = math.max(source.width, source.height);
      final scale = 1600.0 / longer;
      source = img.copyResize(
        source,
        width: (source.width * scale).round(),
        height: (source.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final width = source.width;
    final height = source.height;

    // Create transparent RGBA target
    final output = img.Image(
      width: width,
      height: height,
      numChannels: 4,
    );

    // Compute paper background luminance by sampling the brightest 20%
    int sumLuminance = 0;
    int sampleCount = 0;
    for (int y = 0; y < height; y += 4) {
      for (int x = 0; x < width; x += 4) {
        final pixel = source.getPixel(x, y);
        final lum = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        if (lum > 180) {
          sumLuminance += lum;
          sampleCount++;
        }
      }
    }

    final double avgBackground = sampleCount > 0
        ? (sumLuminance / sampleCount)
        : 235.0;

    // Cutoff threshold: pixels brighter than this become transparent
    final double cutoff = avgBackground * sensitivity;

    int minX = width;
    int minY = height;
    int maxX = 0;
    int maxY = 0;
    bool hasInk = false;

    // Ink color target values for recoloring
    const targetBlueR = 15;
    const targetBlueG = 52;
    const targetBlueB = 148;

    const targetBlackR = 20;
    const targetBlackG = 24;
    const targetBlackB = 33;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final p = source.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

        if (lum < cutoff) {
          // It's ink!
          hasInk = true;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;

          // Alpha curve based on how dark the stroke is
          final inkIntensity = (cutoff - lum) / cutoff;
          final alpha = (inkIntensity * 255).clamp(30, 255).round();

          if (colorMode == SignatureInkColorMode.royalBlue) {
            output.setPixelRgba(x, y, targetBlueR, targetBlueG, targetBlueB, alpha);
          } else if (colorMode == SignatureInkColorMode.executiveBlack) {
            output.setPixelRgba(x, y, targetBlackR, targetBlackG, targetBlackB, alpha);
          } else {
            // Keep original pen color with alpha
            output.setPixelRgba(x, y, p.r.round(), p.g.round(), p.b.round(), alpha);
          }
        } else {
          // Fully transparent paper background
          output.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    if (!hasInk) {
      // Fallback: return entire image if no ink detected
      return Uint8List.fromList(img.encodePng(output));
    }

    // Crop tightly around the ink with 12px breathing margin
    const padding = 12;
    final cropX = math.max(0, minX - padding);
    final cropY = math.max(0, minY - padding);
    final cropW = math.min(width - cropX, (maxX - minX) + (padding * 2));
    final cropH = math.min(height - cropY, (maxY - minY) + (padding * 2));

    final cropped = img.copyCrop(
      output,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    return Uint8List.fromList(img.encodePng(cropped));
  }
}
