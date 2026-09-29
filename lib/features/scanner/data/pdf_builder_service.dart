import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/models/document_paper_size.dart';

export '../../../shared/models/document_paper_size.dart';

class PdfBuilderService {
  /// Fast header check (<0.1ms): returns true if the JPEG needs rotation or downscaling (>2048px).
  static bool needsNormalization(Uint8List bytes) {
    final info = _peekJpegInfo(bytes);
    if (info == null) return true;
    return info.orientation != 1 ||
        info.width > _maxDimension ||
        info.height > _maxDimension;
  }

  Future<Uint8List> buildPdf({
    required List<String> imagePaths,
    required List<DocumentPaperSize> paperSizes,
    bool applyEnhancement = false,
  }) async {
    final normalizedPaths = List<String>.from(imagePaths);
    return Isolate.run(
      () => _buildPdfBytes(normalizedPaths, paperSizes, applyEnhancement),
    );
  }
}

Future<Uint8List> _buildPdfBytes(
  List<String> imagePaths,
  List<DocumentPaperSize> paperSizes,
  bool applyEnhancement,
) async {
  debugPrint(
    'PdfBuilderService: Starting PDF build. Total pages: ${imagePaths.length}',
  );
  final sw = Stopwatch()..start();
  final document = pw.Document();

  for (var index = 0; index < imagePaths.length; index++) {
    final imagePath = imagePaths[index];
    final paperSize = index < paperSizes.length
        ? paperSizes[index]
        : DocumentPaperSize.auto;
    final pageStopwatch = Stopwatch()..start();

    debugPrint(
      '[PdfBuilder] Page ${index + 1}/${imagePaths.length} - path: $imagePath, paperSize: ${paperSize.name}',
    );

    final prepared = await _safePrepareImage(imagePath, applyEnhancement);
    final image = pw.MemoryImage(prepared.bytes);

    final width = prepared.width.toDouble();
    final height = prepared.height.toDouble();

    final isLandscape = width > height;
    final format = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pw.Widget imageWidget;
    switch (paperSize) {
      case DocumentPaperSize.idCard:
        final cardWidthMm = isLandscape ? 85.6 : 53.98;
        final cardWidth = cardWidthMm * PdfPageFormat.mm;
        final cardHeight = cardWidth * (height / width);
        imageWidget = pw.SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.receipt:
        final receiptWidth = 80.0 * PdfPageFormat.mm;
        final receiptHeight = receiptWidth * (height / width);
        imageWidget = pw.SizedBox(
          width: receiptWidth,
          height: receiptHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.a4:
      case DocumentPaperSize.auto:
        imageWidget = pw.FittedBox(
          fit: pw.BoxFit.contain,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
    }

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
        ),
        build: (_) => pw.Center(child: imageWidget),
      ),
    );

    debugPrint(
      '[PdfBuilder] Page ${index + 1} ready in ${pageStopwatch.elapsedMilliseconds}ms (read+prepare+layout)',
    );
  }

  final saveStopwatch = Stopwatch()..start();
  final pdfBytes = await document.save();
  debugPrint(
    '[PdfBuilder] PDF encode/save took ${saveStopwatch.elapsedMilliseconds}ms',
  );
  debugPrint(
    '[PdfBuilder] DONE in ${sw.elapsedMilliseconds}ms - output ${pdfBytes.length} bytes',
  );

  return pdfBytes;
}

// ─────────────────────────────────────────────────────────────────────────────
// Fast path: parse JPEG header without full decode
// ─────────────────────────────────────────────────────────────────────────────

/// Reads JPEG dimensions and EXIF orientation from the file header only.
/// Returns null if the file is not a valid JPEG or parsing fails.
/// This is ~100-1000× faster than a full img.decodeImage().
({int width, int height, int orientation})? _peekJpegInfo(Uint8List bytes) {
  // Must start with JPEG SOI marker FF D8
  if (bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  int width = 0;
  int height = 0;
  int orientation = 1; // default: no rotation
  int i = 2;

  while (i + 3 < bytes.length) {
    // Each segment starts with 0xFF
    if (bytes[i] != 0xFF) break;
    final marker = bytes[i + 1];

    // Skip standalone markers (no data segment)
    if (marker == 0xD8 || marker == 0xD9) {
      i += 2;
      continue;
    }
    // RST markers
    if (marker >= 0xD0 && marker <= 0xD7) {
      i += 2;
      continue;
    }

    if (i + 4 > bytes.length) break;
    final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
    if (segLen < 2 || i + 2 + segLen > bytes.length) break;

    // ── APP1: may contain EXIF with orientation ──
    if (marker == 0xE1 && segLen > 6) {
      // Check for "Exif\0\0" signature
      if (i + 9 < bytes.length &&
          bytes[i + 4] == 0x45 && // E
          bytes[i + 5] == 0x78 && // x
          bytes[i + 6] == 0x69 && // i
          bytes[i + 7] == 0x66 && // f
          bytes[i + 8] == 0x00 &&
          bytes[i + 9] == 0x00) {
        final tiffStart = i + 10;
        orientation = _readTiffOrientation(bytes, tiffStart) ?? 1;
      }
    }

    // ── SOF markers: contain image dimensions ──
    // SOF0=C0, SOF1=C1, SOF2=C2 (progressive), SOF3=C3, SOF5-C7, SOF9-CB, SOF13-CF
    final isSOF = (marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3 ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF));

    if (isSOF && i + 8 < bytes.length) {
      // SOF layout: marker(2) + length(2) + precision(1) + height(2) + width(2)
      height = (bytes[i + 5] << 8) | bytes[i + 6];
      width = (bytes[i + 7] << 8) | bytes[i + 8];
    }

    // SOS (Start of Scan) — compressed image data starts, stop scanning
    if (marker == 0xDA) break;

    i += 2 + segLen;
  }

  if (width == 0 || height == 0) return null;
  return (width: width, height: height, orientation: orientation);
}

/// Reads EXIF Orientation tag from a TIFF block inside JPEG APP1.
/// Returns null if tag not found or block is malformed.
int? _readTiffOrientation(Uint8List bytes, int tiffStart) {
  if (tiffStart + 8 > bytes.length) return null;

  // Byte order mark: 'II' = little-endian, 'MM' = big-endian
  final isLE = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
  final isBE = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
  if (!isLE && !isBE) return null;

  int u16(int off) {
    if (off + 1 >= bytes.length) return 0;
    return isLE
        ? bytes[off] | (bytes[off + 1] << 8)
        : (bytes[off] << 8) | bytes[off + 1];
  }

  int u32(int off) {
    if (off + 3 >= bytes.length) return 0;
    return isLE
        ? bytes[off] |
              (bytes[off + 1] << 8) |
              (bytes[off + 2] << 16) |
              (bytes[off + 3] << 24)
        : (bytes[off] << 24) |
              (bytes[off + 1] << 16) |
              (bytes[off + 2] << 8) |
              bytes[off + 3];
  }

  // TIFF magic number must be 42
  if (u16(tiffStart + 2) != 42) return null;

  // Offset of first IFD (IFD0), relative to TIFF start
  final ifd0Offset = u32(tiffStart + 4);
  final ifd0Start = tiffStart + ifd0Offset;
  if (ifd0Start + 2 > bytes.length) return null;

  final numEntries = u16(ifd0Start);

  for (int e = 0; e < numEntries && e < 64; e++) {
    final entryOff = ifd0Start + 2 + e * 12;
    if (entryOff + 12 > bytes.length) break;

    final tag = u16(entryOff);
    if (tag == 0x0112) {
      // Orientation tag — value is stored in bytes 8-9 of the entry
      return u16(entryOff + 8);
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Image preparation
// ─────────────────────────────────────────────────────────────────────────────

const int _maxDimension = 2048;

Future<_PreparedPdfImage> _safePrepareImage(
  String imagePath,
  bool applyEnhancement,
) async {
  final prepareStopwatch = Stopwatch()..start();
  debugPrint('[PdfBuilder] _safePrepareImage START for $imagePath');

  final readStopwatch = Stopwatch()..start();
  final originalBytes = await File(imagePath).readAsBytes();
  debugPrint(
    '[PdfBuilder] File read took ${readStopwatch.elapsedMilliseconds}ms (${originalBytes.length} bytes)',
  );

  // ── FAST PATH ─────────────────────────────────────────────────────────────
  // Skip decode+re-encode when the image is already a valid JPEG
  // with correct orientation and acceptable dimensions (<= 2048px).
  final info = _peekJpegInfo(originalBytes);
  if (info != null &&
      info.orientation == 1 &&
      info.width <= _maxDimension &&
      info.height <= _maxDimension) {
    debugPrint(
      '[PdfBuilder] ✅ FAST PATH: ${info.width}x${info.height} — direct pass-through (${prepareStopwatch.elapsedMilliseconds}ms)',
    );
    return _PreparedPdfImage(
      bytes: originalBytes,
      width: info.width,
      height: info.height,
    );
  }

  // ── DOWNSCALE PATH (Only if image > 2048px or orientation != 1) ───────────
  img.Image? decoded;
  try {
    decoded = img.decodeImage(originalBytes);
  } catch (e) {
    debugPrint('[PdfBuilder] Failed to decode image $imagePath: $e');
    throw Exception('فشل قراءة الصورة، قد تكون تالفة.');
  }

  if (decoded == null) {
    throw Exception('الصورة فارغة أو غير مدعومة.');
  }

  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  if (orientation != 1) {
    decoded = img.bakeOrientation(decoded);
  }

  if (decoded.width > _maxDimension || decoded.height > _maxDimension) {
    debugPrint(
      '[PdfBuilder] Downscaling ${decoded.width}x${decoded.height} to max $_maxDimension...',
    );
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? _maxDimension : null,
      height: decoded.height > decoded.width ? _maxDimension : null,
      interpolation: img.Interpolation.linear,
    );
  }

  final finalBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 85));

  debugPrint(
    '[PdfBuilder] Normalized in ${prepareStopwatch.elapsedMilliseconds}ms (${decoded.width}x${decoded.height})',
  );

  return _PreparedPdfImage(
    bytes: finalBytes,
    width: decoded.width,
    height: decoded.height,
  );
}

class _PreparedPdfImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _PreparedPdfImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
