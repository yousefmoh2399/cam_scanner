import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/models/document_paper_size.dart';
import 'ocr_service.dart';

export '../../../shared/models/document_paper_size.dart';

/// Compression targets for Phase 3.1 (Government portals, email attachments, etc.)
enum PdfCompressionPreset {
  none,
  under2mb,
  under1mb,
  under500kb,
  under200kb,
  manual;

  String get labelAr => switch (this) {
        PdfCompressionPreset.none => 'بدون ضغط (الجودة الأصلية)',
        PdfCompressionPreset.under2mb => 'أقل من 2 ميجابايت',
        PdfCompressionPreset.under1mb => 'أقل من 1 ميجابايت',
        PdfCompressionPreset.under500kb => 'أقل من 500 كيلوبايت (للنماذج الحكومية)',
        PdfCompressionPreset.under200kb => 'أقل من 200 كيلوبايت (أقصى ضغط)',
        PdfCompressionPreset.manual => 'جودة يدوية مخصصة',
      };

  int? get targetMaxBytes => switch (this) {
        PdfCompressionPreset.none => null,
        PdfCompressionPreset.under2mb => 2 * 1024 * 1024,
        PdfCompressionPreset.under1mb => 1024 * 1024,
        PdfCompressionPreset.under500kb => 500 * 1024,
        PdfCompressionPreset.under200kb => 200 * 1024,
        PdfCompressionPreset.manual => null,
      };
}

class PdfBuildOptions {
  const PdfBuildOptions({
    this.applyEnhancement = false,
    this.searchableOcrPages,
    this.compressionPreset = PdfCompressionPreset.none,
    this.manualJpegQuality = 85,
    this.watermarkText,
    this.includeDateStamp = false,
    this.dateStampText,
  });

  final bool applyEnhancement;
  final List<OcrPageData>? searchableOcrPages;
  final PdfCompressionPreset compressionPreset;
  final int manualJpegQuality;
  final String? watermarkText;
  final bool includeDateStamp;
  final String? dateStampText;

  bool get isSearchable =>
      searchableOcrPages != null && searchableOcrPages!.isNotEmpty;
}

class PdfBuilderService {
  static Uint8List? _cachedCairoFontBytes;

  static Future<Uint8List?> _loadCairoFontBytes() async {
    if (_cachedCairoFontBytes != null) return _cachedCairoFontBytes;
    try {
      final data = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _cachedCairoFontBytes = data.buffer.asUint8List();
      return _cachedCairoFontBytes;
    } catch (e) {
      debugPrint('[PdfBuilderService] Could not load Cairo font: $e');
      return null;
    }
  }

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
    PdfBuildOptions? options,
  }) async {
    final effectiveOptions = options ??
        PdfBuildOptions(applyEnhancement: applyEnhancement);
    final normalizedPaths = List<String>.from(imagePaths);

    Uint8List? fontBytes;
    if (effectiveOptions.isSearchable ||
        (effectiveOptions.watermarkText?.trim().isNotEmpty ?? false) ||
        effectiveOptions.includeDateStamp) {
      fontBytes = await _loadCairoFontBytes();
    }

    return Isolate.run(
      () => _buildPdfWithOptionsInIsolate(
        imagePaths: normalizedPaths,
        paperSizes: paperSizes,
        options: effectiveOptions,
        cairoFontBytes: fontBytes,
      ),
    );
  }

  /// Convenience builder for Searchable PDF with invisible Arabic/English OCR text layer.
  Future<Uint8List> buildSearchablePdf({
    required List<String> imagePaths,
    required List<DocumentPaperSize> paperSizes,
    required List<OcrPageData> ocrPages,
    PdfCompressionPreset compressionPreset = PdfCompressionPreset.none,
    int manualJpegQuality = 85,
    String? watermarkText,
    bool includeDateStamp = false,
  }) {
    return buildPdf(
      imagePaths: imagePaths,
      paperSizes: paperSizes,
      options: PdfBuildOptions(
        searchableOcrPages: ocrPages,
        compressionPreset: compressionPreset,
        manualJpegQuality: manualJpegQuality,
        watermarkText: watermarkText,
        includeDateStamp: includeDateStamp,
      ),
    );
  }
}

Future<Uint8List> _buildPdfWithOptionsInIsolate({
  required List<String> imagePaths,
  required List<DocumentPaperSize> paperSizes,
  required PdfBuildOptions options,
  Uint8List? cairoFontBytes,
}) async {
  final targetBytes = options.compressionPreset.targetMaxBytes;
  if (targetBytes == null) {
    final forceQuality = options.compressionPreset == PdfCompressionPreset.manual
        ? options.manualJpegQuality.clamp(15, 95)
        : null;
    final maxDim = forceQuality != null
        ? (forceQuality < 50 ? 1280 : (forceQuality < 75 ? 1600 : _maxDimension))
        : _maxDimension;
    return _buildPdfBytes(
      imagePaths,
      paperSizes,
      options.applyEnhancement,
      ocrPages: options.searchableOcrPages,
      cairoFontBytes: cairoFontBytes,
      forceJpegQuality: forceQuality,
      maxDimension: maxDim,
      watermarkText: options.watermarkText,
      includeDateStamp: options.includeDateStamp,
      dateStampText: options.dateStampText,
    );
  }

  // Target-Size Binary Search Compression (Phase 3.1)
  // First try standard pass-through if already smaller than targetBytes
  final initialPdf = await _buildPdfBytes(
    imagePaths,
    paperSizes,
    options.applyEnhancement,
    ocrPages: options.searchableOcrPages,
    cairoFontBytes: cairoFontBytes,
    watermarkText: options.watermarkText,
    includeDateStamp: options.includeDateStamp,
    dateStampText: options.dateStampText,
  );

  if (initialPdf.length <= targetBytes) {
    return initialPdf;
  }

  // Binary search over compression profiles (0 = most aggressive, 7 = high quality)
  const profiles = <({int quality, int maxDim})>[
    (quality: 18, maxDim: 720),
    (quality: 28, maxDim: 900),
    (quality: 38, maxDim: 1080),
    (quality: 48, maxDim: 1240),
    (quality: 58, maxDim: 1440),
    (quality: 68, maxDim: 1650),
    (quality: 76, maxDim: 1850),
    (quality: 84, maxDim: 2048),
  ];

  int low = 0;
  int high = profiles.length - 1;
  Uint8List? bestFit;

  while (low <= high) {
    final mid = (low + high) ~/ 2;
    final profile = profiles[mid];
    final candidate = await _buildPdfBytes(
      imagePaths,
      paperSizes,
      options.applyEnhancement,
      ocrPages: options.searchableOcrPages,
      cairoFontBytes: cairoFontBytes,
      forceJpegQuality: profile.quality,
      maxDimension: profile.maxDim,
      watermarkText: options.watermarkText,
      includeDateStamp: options.includeDateStamp,
      dateStampText: options.dateStampText,
    );

    if (candidate.length <= targetBytes) {
      bestFit = candidate;
      low = mid + 1; // try higher quality
    } else {
      high = mid - 1; // need stronger compression
    }
  }

  if (bestFit != null) return bestFit;

  // Fallback to most aggressive profile if still above target
  return _buildPdfBytes(
    imagePaths,
    paperSizes,
    options.applyEnhancement,
    ocrPages: options.searchableOcrPages,
    cairoFontBytes: cairoFontBytes,
    forceJpegQuality: profiles.first.quality,
    maxDimension: profiles.first.maxDim,
    watermarkText: options.watermarkText,
    includeDateStamp: options.includeDateStamp,
    dateStampText: options.dateStampText,
  );
}

Future<Uint8List> _buildPdfBytes(
  List<String> imagePaths,
  List<DocumentPaperSize> paperSizes,
  bool applyEnhancement, {
  List<OcrPageData>? ocrPages,
  Uint8List? cairoFontBytes,
  int? forceJpegQuality,
  int maxDimension = _maxDimension,
  String? watermarkText,
  bool includeDateStamp = false,
  String? dateStampText,
}) async {
  debugPrint(
    'PdfBuilderService: Starting PDF build. Total pages: ${imagePaths.length}',
  );
  final sw = Stopwatch()..start();
  final document = pw.Document();
  final pw.Font? cairoFont = cairoFontBytes != null
      ? pw.Font.ttf(cairoFontBytes.buffer.asByteData())
      : null;

  for (var index = 0; index < imagePaths.length; index++) {
    final imagePath = imagePaths[index];
    final paperSize = index < paperSizes.length
        ? paperSizes[index]
        : DocumentPaperSize.auto;
    final pageStopwatch = Stopwatch()..start();

    final prepared = await _safePrepareImage(
      imagePath,
      applyEnhancement,
      forceJpegQuality: forceJpegQuality,
      maxDimension: maxDimension,
    );
    final image = pw.MemoryImage(prepared.bytes);

    final width = prepared.width.toDouble();
    final height = prepared.height.toDouble();

    final isLandscape = width > height;
    final format = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    const margin = 8 * PdfPageFormat.mm;
    final availW = format.width - (margin * 2);
    final availH = format.height - (margin * 2);

    double renderW = availW;
    double renderH = availH;
    final imgAspect = width / math.max(1.0, height);
    if (availW / availH > imgAspect) {
      renderH = availH;
      renderW = renderH * imgAspect;
    } else {
      renderW = availW;
      renderH = renderW / imgAspect;
    }

    pw.Widget imageWidget;
    switch (paperSize) {
      case DocumentPaperSize.idCard:
        final cardWidthMm = isLandscape ? 85.6 : 53.98;
        final cardWidth = cardWidthMm * PdfPageFormat.mm;
        final cardHeight = cardWidth * (height / width);
        renderW = cardWidth;
        renderH = cardHeight;
        imageWidget = pw.SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.receipt:
        final receiptWidth = 80.0 * PdfPageFormat.mm;
        final receiptHeight = receiptWidth * (height / width);
        renderW = receiptWidth;
        renderH = receiptHeight;
        imageWidget = pw.SizedBox(
          width: receiptWidth,
          height: receiptHeight,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        );
        break;
      case DocumentPaperSize.a4:
      case DocumentPaperSize.auto:
        imageWidget = pw.SizedBox(
          width: renderW,
          height: renderH,
          child: pw.Image(image, fit: pw.BoxFit.fill),
        );
        break;
    }

    // Check if we have OCR lines for this page (Searchable PDF invisible text layer)
    final OcrPageData? pageOcr = (ocrPages != null && index < ocrPages.length)
        ? ocrPages[index]
        : null;

    final stackChildren = <pw.Widget>[imageWidget];

    if (pageOcr != null && pageOcr.lines.isNotEmpty) {
      for (final line in pageOcr.lines) {
        if (line.text.trim().isEmpty) continue;
        final leftPt = (line.normLeft.clamp(0.0, 0.98)) * renderW;
        final topPt = (line.normTop.clamp(0.0, 0.98)) * renderH;
        final widthPt = (line.normWidth.clamp(0.02, 1.0 - line.normLeft)) * renderW;
        final heightPt = (line.normHeight.clamp(0.015, 0.25)) * renderH;
        final fontSize = (heightPt * 0.72).clamp(6.0, 28.0);

        stackChildren.add(
          pw.Positioned(
            left: leftPt,
            top: topPt,
            child: pw.Opacity(
              opacity: 0.004, // Visually transparent, selectable by PDF viewers
              child: pw.Directionality(
                textDirection:
                    line.isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                child: pw.SizedBox(
                  width: widthPt,
                  height: heightPt * 1.25,
                  child: pw.Text(
                    line.text,
                    style: pw.TextStyle(
                      font: cairoFont,
                      fontSize: fontSize,
                      color: PdfColors.black,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Optional custom watermark (off by default)
    if (watermarkText != null && watermarkText.trim().isNotEmpty) {
      stackChildren.add(
        pw.Positioned.fill(
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: -0.52,
              child: pw.Opacity(
                opacity: 0.16,
                child: pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Text(
                    watermarkText.trim(),
                    style: pw.TextStyle(
                      font: cairoFont,
                      fontSize: 34,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Optional date stamp in bottom corner (off by default)
    if (includeDateStamp) {
      final stamp = dateStampText ??
          DateTime.now().toIso8601String().split('T').first;
      stackChildren.add(
        pw.Positioned(
          bottom: 4,
          left: 6,
          child: pw.Opacity(
            opacity: 0.65,
            child: pw.Text(
              stamp,
              style: pw.TextStyle(
                font: cairoFont,
                fontSize: 8.5,
                color: PdfColors.grey800,
              ),
            ),
          ),
        ),
      );
    }

    final pageContent = stackChildren.length == 1
        ? imageWidget
        : pw.SizedBox(
            width: renderW,
            height: renderH,
            child: pw.Stack(children: stackChildren),
          );

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(margin),
        ),
        build: (_) => pw.Center(child: pageContent),
      ),
    );

    debugPrint(
      '[PdfBuilder] Page ${index + 1} ready in ${pageStopwatch.elapsedMilliseconds}ms',
    );
  }

  final pdfBytes = await document.save();
  debugPrint(
    '[PdfBuilder] DONE in ${sw.elapsedMilliseconds}ms - output ${pdfBytes.length} bytes',
  );

  return pdfBytes;
}

// ─────────────────────────────────────────────────────────────────────────────
// Fast path: parse JPEG header without full decode
// ─────────────────────────────────────────────────────────────────────────────

({int width, int height, int orientation})? _peekJpegInfo(Uint8List bytes) {
  if (bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  int width = 0;
  int height = 0;
  int orientation = 1;
  int i = 2;

  while (i + 3 < bytes.length) {
    if (bytes[i] != 0xFF) break;
    final marker = bytes[i + 1];

    if (marker == 0xD8 || marker == 0xD9) {
      i += 2;
      continue;
    }
    if (marker >= 0xD0 && marker <= 0xD7) {
      i += 2;
      continue;
    }

    if (i + 4 > bytes.length) break;
    final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
    if (segLen < 2 || i + 2 + segLen > bytes.length) break;

    if (marker == 0xE1 && segLen > 6) {
      if (i + 9 < bytes.length &&
          bytes[i + 4] == 0x45 &&
          bytes[i + 5] == 0x78 &&
          bytes[i + 6] == 0x69 &&
          bytes[i + 7] == 0x66 &&
          bytes[i + 8] == 0x00 &&
          bytes[i + 9] == 0x00) {
        final tiffStart = i + 10;
        orientation = _readTiffOrientation(bytes, tiffStart) ?? 1;
      }
    }

    final isSOF = (marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3 ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF));

    if (isSOF && i + 8 < bytes.length) {
      height = (bytes[i + 5] << 8) | bytes[i + 6];
      width = (bytes[i + 7] << 8) | bytes[i + 8];
    }

    if (marker == 0xDA) break;

    i += 2 + segLen;
  }

  if (width == 0 || height == 0) return null;
  return (width: width, height: height, orientation: orientation);
}

int? _readTiffOrientation(Uint8List bytes, int tiffStart) {
  if (tiffStart + 8 > bytes.length) return null;

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

  if (u16(tiffStart + 2) != 42) return null;

  final ifd0Offset = u32(tiffStart + 4);
  final ifd0Start = tiffStart + ifd0Offset;
  if (ifd0Start + 2 > bytes.length) return null;

  final numEntries = u16(ifd0Start);

  for (int e = 0; e < numEntries && e < 64; e++) {
    final entryOff = ifd0Start + 2 + e * 12;
    if (entryOff + 12 > bytes.length) break;

    final tag = u16(entryOff);
    if (tag == 0x0112) {
      return u16(entryOff + 8);
    }
  }
  return null;
}

const int _maxDimension = 2048;

Future<_PreparedPdfImage> _safePrepareImage(
  String imagePath,
  bool applyEnhancement, {
  int? forceJpegQuality,
  int maxDimension = _maxDimension,
}) async {
  final originalBytes = await File(imagePath).readAsBytes();

  // ── FAST PATH (Zero Decode) ───────────────────────────────────────────────
  // Skip decode+re-encode when no forced compression is requested and the image
  // is already a valid JPEG with orientation=1 and dimensions <= 2048px.
  final info = _peekJpegInfo(originalBytes);
  if (forceJpegQuality == null &&
      maxDimension >= _maxDimension &&
      info != null &&
      info.orientation == 1 &&
      info.width <= _maxDimension &&
      info.height <= _maxDimension) {
    return _PreparedPdfImage(
      bytes: originalBytes,
      width: info.width,
      height: info.height,
    );
  }

  img.Image? decoded;
  try {
    decoded = img.decodeImage(originalBytes);
  } catch (e) {
    throw Exception('فشل قراءة الصورة، قد تكون تالفة.');
  }

  if (decoded == null) {
    throw Exception('الصورة فارغة أو غير مدعومة.');
  }

  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  if (orientation != 1) {
    decoded = img.bakeOrientation(decoded);
  }

  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? maxDimension : null,
      height: decoded.height >= decoded.width ? maxDimension : null,
      interpolation: img.Interpolation.linear,
    );
  }

  final finalBytes = Uint8List.fromList(
    img.encodeJpg(decoded, quality: forceJpegQuality ?? 85),
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
