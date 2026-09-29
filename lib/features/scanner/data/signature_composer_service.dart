import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'native_scanner_bridge.dart';

/// Composites a signature PNG on top of a scanned page image.
/// Uses native hardware-accelerated Bitmap/Canvas on Android (~15ms) and
/// falls back to an [Isolate] on other platforms.
class SignatureComposerService {
  /// Merges [signatureBytes] (PNG with transparency) onto the page at [pageImagePath]
  /// (or [pageImageBytes]) at [relativeX], [relativeY] (0.0–1.0 relative to page dimensions)
  /// with [relativeWidth] (0.0–1.0 relative to page width).
  ///
  /// Returns the final composited JPEG bytes capped at 2048px with EXIF orientation 1
  /// so `PdfBuilderService` hits its zero-decode fast path.
  Future<Uint8List> compositeSignatureOnImage({
    String? pageImagePath,
    Uint8List? pageImageBytes,
    required Uint8List signatureBytes,
    required double relativeX,
    required double relativeY,
    required double relativeWidth,
  }) async {
    if (pageImagePath != null && pageImagePath.isNotEmpty) {
      final nativeResult = await NativeScannerBridge.compositeSignature(
        pagePath: pageImagePath,
        signatureBytes: signatureBytes,
        relativeX: relativeX,
        relativeY: relativeY,
        relativeWidth: relativeWidth,
        maxSide: 2048,
      );
      if (nativeResult != null && nativeResult.isNotEmpty) {
        return nativeResult;
      }
    }

    final bytes = pageImageBytes ??
        (pageImagePath != null ? await File(pageImagePath).readAsBytes() : null);
    if (bytes == null) {
      throw ArgumentError('Either pageImagePath or pageImageBytes must be provided.');
    }

    return Isolate.run(() {
      return _composite(
        bytes,
        signatureBytes,
        relativeX,
        relativeY,
        relativeWidth,
      );
    });
  }
}

Uint8List _composite(
  Uint8List pageBytes,
  Uint8List sigBytes,
  double relX,
  double relY,
  double relW,
) {
  // Decode page
  final page = img.decodeImage(pageBytes);
  if (page == null) throw Exception('تعذر فك ضغط صورة الصفحة.');

  // Bake EXIF orientation if needed
  var bakedPage = page.exif.imageIfd.orientation != null &&
          page.exif.imageIfd.orientation != 1
      ? img.bakeOrientation(page)
      : page;

  // Cap at 2048px so PdfBuilderService always hits the 0ms fast path
  const maxDim = 2048;
  if (bakedPage.width > maxDim || bakedPage.height > maxDim) {
    bakedPage = img.copyResize(
      bakedPage,
      width: bakedPage.width >= bakedPage.height ? maxDim : null,
      height: bakedPage.height > bakedPage.width ? maxDim : null,
      interpolation: img.Interpolation.linear,
    );
  }

  // Clear EXIF orientation so _peekJpegInfo sees orientation == 1
  bakedPage.exif.clear();

  // Decode signature (PNG with alpha)
  final sig = img.decodeImage(sigBytes);
  if (sig == null) throw Exception('تعذر فك ضغط صورة التوقيع.');

  // Compute target dimensions for the signature
  final targetWidth = (bakedPage.width * relW).round().clamp(10, bakedPage.width);
  final aspectRatio = sig.height / sig.width;
  final targetHeight = (targetWidth * aspectRatio).round().clamp(1, bakedPage.height);

  // Resize signature
  final resizedSig = img.copyResize(
    sig,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );

  // Compute pixel offsets (clamp so signature stays inside the page)
  final offsetX = (bakedPage.width * relX).round().clamp(0, bakedPage.width - targetWidth);
  final offsetY = (bakedPage.height * relY).round().clamp(0, bakedPage.height - targetHeight);

  // Composite — blends the transparent PNG on top of the page
  img.compositeImage(
    bakedPage,
    resizedSig,
    dstX: offsetX,
    dstY: offsetY,
  );

  debugPrint(
    '[SignatureComposer] Composited ${targetWidth}x${targetHeight}px sig at ($offsetX,$offsetY) on ${bakedPage.width}x${bakedPage.height}px page.',
  );

  return Uint8List.fromList(img.encodeJpg(bakedPage, quality: 92));
}

