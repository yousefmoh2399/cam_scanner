import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/services/local_media_storage_service.dart';
import 'document_search_service.dart';
import 'ocr_service.dart';
import 'pdf_builder_service.dart';

enum ExportFormat {
  pdf,
  searchablePdf,
  docx,
  xlsx;

  String get extension => switch (this) {
        ExportFormat.pdf => 'pdf',
        ExportFormat.searchablePdf => 'pdf',
        ExportFormat.docx => 'docx',
        ExportFormat.xlsx => 'xlsx',
      };

  String get title => switch (this) {
        ExportFormat.pdf => 'ملف PDF قياسي سريع (.pdf)',
        ExportFormat.searchablePdf =>
          'ملف PDF قابل للبحث والنسخ (Searchable PDF)',
        ExportFormat.docx => 'مستند Word قابل للتعديل (.docx)',
        ExportFormat.xlsx => 'جدول بيانات Excel ذكي (.xlsx)',
      };

  String get subtitle => switch (this) {
        ExportFormat.pdf =>
          'حفظ الصفحات بأعلى جودة بالمسار السريع (Zero-Decode) مع دعم الضغط بالحجم المستهدف',
        ExportFormat.searchablePdf =>
          'يتضمن طبقة نصية شفافة (عربي/إنجليزي) بـ Tesseract OCR للبحث والنسخ داخل الـ PDF',
        ExportFormat.docx =>
          'ملف OpenXML يحتوي على صور الصفحات + النصوص المستخرجة بـ OCR (RTL/LTR)',
        ExportFormat.xlsx =>
          'إعادة بناء الجداول المطبوعة داخل ملف Excel احترافي مع شبكة خلايا حقيقية، تنسيق كامل، ودعم الأرقام والعربي RTL',
      };

  String get mimeType => switch (this) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.searchablePdf => 'application/pdf',
        ExportFormat.docx =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.xlsx =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };

  bool get usesOcr => switch (this) {
        ExportFormat.pdf => false,
        ExportFormat.searchablePdf => true,
        ExportFormat.docx => true,
        ExportFormat.xlsx => true,
      };
}

class OcrBlockItem {
  const OcrBlockItem({
    required this.text,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.isRtl,
  });

  final String text;
  final double top;
  final double left;
  final double width;
  final double height;
  final bool isRtl;

  double get bottom => top + height;
  double get right => left + width;
  double get centerY => top + height / 2.0;
}

class PageOcrResult {
  const PageOcrResult({
    required this.pageIndex,
    required this.imagePath,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.blocks,
    required this.fullText,
    this.ocrPageData,
  });

  final int pageIndex;
  final String imagePath;
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final List<OcrBlockItem> blocks;
  final String fullText;
  final OcrPageData? ocrPageData;
}

/// Offline OCR & Office Export Service (Standard PDF, Searchable PDF, Word .docx OpenXML, Excel .xlsx).
///
/// Offline OCR Architecture:
/// - Primary Engine: `TesseractOcrEngine` (Tesseract 4/5 LSTM JNI + `ara.traineddata` & `eng.traineddata`
///   bundled in `assets/tessdata/`) with OpenCV 300 DPI illumination normalization, deskew & adaptive threshold.
/// - Fallback Engine: `MlKitLatinOcrEngine` (on-device Latin script recognizer) + visual band detector.
/// - Results are cached per document (`ocr_cache/<doc_id>.json`) and indexed into SQLite FTS4 (`DocumentSearchService`).
class OfficeExporterService {
  OfficeExporterService({
    PdfBuilderService? pdfBuilderService,
    OcrService? ocrService,
    DocumentSearchService? searchService,
  })  : _pdfBuilder = pdfBuilderService ?? PdfBuilderService(),
        _ocrService = ocrService ?? OcrService(),
        _searchService = searchService ?? DocumentSearchService();

  final PdfBuilderService _pdfBuilder;
  final OcrService _ocrService;
  final DocumentSearchService _searchService;

  static final RegExp _arabicRegex =
      RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');

  static bool isRtlText(String text) {
    return _arabicRegex.hasMatch(text);
  }

  static const Map<String, String> _easternToArabicDigits = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '٫': '.',
    '٬': '',
  };

  /// Normalizes Eastern Arabic numerals (٠-٩) and Arabic decimal/thousands separators.
  static String normalizeArabicDigits(String input) {
    var s = input;
    _easternToArabicDigits.forEach((ar, en) {
      s = s.replaceAll(ar, en);
    });
    return s;
  }

  /// Parses numeric strings including Eastern Arabic digits, currencies, and percentages.
  /// Preserves phone numbers, codes with leading zeros, and dates by returning null.
  static num? parseFlexibleNumber(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    final normalized = normalizeArabicDigits(trimmed);

    // Keep dates as text (e.g. 2026/10/03 or 15-05-2024 or 01.01.2025)
    if (RegExp(r'^\d{1,4}[/\-.]\d{1,2}[/\-.]\d{1,4}$').hasMatch(normalized)) {
      return null;
    }

    // Strip currency symbols and percentage signs
    var cleaned = normalized
        .replaceAll(
          RegExp(
            r'(ج\.م|ر\.س|د\.إ|د\.ك|د\.أ|جنيه|ريال|دولار|\$|€|£|¥|LE|EGP|SAR|USD|EUR)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll('%', '')
        .replaceAll('٪', '')
        .trim();

    // Check for negative signs (accounting parentheses or trailing/leading minus)
    var isNegative = false;
    if (cleaned.endsWith('-')) {
      isNegative = true;
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    } else if (cleaned.startsWith('-')) {
      isNegative = true;
      cleaned = cleaned.substring(1).trim();
    } else if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      isNegative = true;
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    if (cleaned.isEmpty) return null;

    // Preserve codes/phone numbers with leading zeros (e.g. "01012345678" or "0025")
    if (cleaned.length > 1 &&
        cleaned.startsWith('0') &&
        !cleaned.startsWith('0.') &&
        !cleaned.startsWith('0,')) {
      return null;
    }

    // Handle European/Arabic comma format vs US comma thousands
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    if (lastDot != -1 && lastComma != -1) {
      if (lastComma > lastDot) {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    } else if (lastComma != -1) {
      final parts = cleaned.split(',');
      if (parts.length == 2 && parts[1].length <= 2) {
        cleaned = '${parts[0]}.${parts[1]}';
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    }

    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
      return null;
    }

    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;

    final finalVal = isNegative ? -parsed : parsed;
    if (finalVal % 1 == 0 &&
        finalVal >= -9007199254740991 &&
        finalVal <= 9007199254740991) {
      return finalVal.toInt();
    }
    return finalVal;
  }

  /// Builds a complete Excel (.xlsx) workbook directly from OCR page results.
  static Uint8List buildXlsxWorkbook({
    required String documentTitle,
    required List<PageOcrResult> pages,
  }) =>
      _buildXlsxWorkbookInIsolate(
        documentTitle: documentTitle,
        pages: pages,
      );

  /// Exports a [PendingUpload] document into the requested [ExportFormat].
  Future<String> exportDocument({
    required PendingUpload document,
    required ExportFormat format,
    OcrLanguageMode languageMode = OcrLanguageMode.arabicEnglish,
    PdfCompressionPreset compressionPreset = PdfCompressionPreset.none,
    int manualJpegQuality = 85,
    String? watermarkText,
    bool includeDateStamp = false,
    OcrCancellationToken? cancellationToken,
    ValueChanged<String>? onProgress,
  }) async {
    final imagePaths = document.pages
        .map((p) => p.imagePath)
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();

    if (imagePaths.isEmpty &&
        document.effectiveThumbnailPath != null &&
        File(document.effectiveThumbnailPath!).existsSync()) {
      imagePaths.add(document.effectiveThumbnailPath!);
    }

    final baseName = stripFileExtension(document.fileName);
    final paperSizes = document.pages.map((p) => p.paperSize).toList();
    final hasCustomPdfOptions =
        compressionPreset != PdfCompressionPreset.none ||
            (watermarkText?.trim().isNotEmpty ?? false) ||
            includeDateStamp;

    switch (format) {
      case ExportFormat.pdf:
        if (!hasCustomPdfOptions && File(document.filePath).existsSync()) {
          onProgress?.call('ملف الـ PDF جاهز!');
          return document.filePath;
        }
        if (imagePaths.isEmpty) {
          throw Exception('لا توجد صور صفحات متاحة لتوليد ملف PDF.');
        }
        onProgress?.call(
          compressionPreset == PdfCompressionPreset.none
              ? 'جارٍ بناء ملف PDF بالمسار السريع...'
              : 'جارٍ ضغط وبناء ملف PDF (${compressionPreset.labelAr})...',
        );
        final pdfBytes = await _pdfBuilder.buildPdf(
          imagePaths: imagePaths,
          paperSizes: paperSizes,
          options: PdfBuildOptions(
            compressionPreset: compressionPreset,
            manualJpegQuality: manualJpegQuality,
            watermarkText: watermarkText,
            includeDateStamp: includeDateStamp,
          ),
        );
        final outDir =
            await const LocalMediaStorageService().exportsDirectory();
        final safeName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final suffix = compressionPreset == PdfCompressionPreset.none
            ? ''
            : '_${compressionPreset.name}';
        final pdfPath =
            p.join(outDir.path, '${document.id}_$safeName$suffix.pdf');
        await File(pdfPath).writeAsBytes(pdfBytes, flush: true);
        onProgress?.call(
          'تم تجهيز ملف PDF (${formatFileSize(pdfBytes.length)}) بنجاح!',
        );
        return pdfPath;

      case ExportFormat.searchablePdf:
        if (imagePaths.isEmpty) {
          throw Exception('لا توجد صفحات لتوليد Searchable PDF.');
        }
        final ocrDoc = await _ocrService.recognizeDocument(
          documentId: document.id,
          imagePaths: imagePaths,
          languageMode: languageMode,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );
        await _searchService.indexDocumentOcr(
          documentId: document.id,
          title: baseName,
          fullText: ocrDoc.fullText,
          smartTitle: ocrDoc.suggestedTitle,
        );
        onProgress?.call('جارٍ دمج طبقة النص المخفية (Searchable PDF)...');
        final pdfBytes = await _pdfBuilder.buildSearchablePdf(
          imagePaths: imagePaths,
          paperSizes: paperSizes,
          ocrPages: ocrDoc.pages,
          compressionPreset: compressionPreset,
          manualJpegQuality: manualJpegQuality,
          watermarkText: watermarkText,
          includeDateStamp: includeDateStamp,
        );
        final outDir =
            await const LocalMediaStorageService().exportsDirectory();
        final safeName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final pdfPath = p.join(
          outDir.path,
          '${document.id}_${safeName}_searchable.pdf',
        );
        await File(pdfPath).writeAsBytes(pdfBytes, flush: true);
        onProgress?.call(
          'تم إنشاء Searchable PDF (${formatFileSize(pdfBytes.length)}) بنجاح!',
        );
        return pdfPath;

      case ExportFormat.docx:
        return exportToDocx(
          documentId: document.id,
          documentTitle: baseName,
          imagePaths: imagePaths,
          languageMode: languageMode,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );

      case ExportFormat.xlsx:
        return exportToXlsx(
          documentId: document.id,
          documentTitle: baseName,
          imagePaths: imagePaths,
          languageMode: languageMode,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );
    }
  }

  /// Extracts OCR blocks asynchronously using `OcrService` (Tesseract Arabic/English + ML Kit fallback).
  Future<List<PageOcrResult>> extractPagesOcr({
    required String documentId,
    required String documentTitle,
    required List<String> imagePaths,
    OcrLanguageMode languageMode = OcrLanguageMode.arabicEnglish,
    OcrCancellationToken? cancellationToken,
    ValueChanged<String>? onProgress,
  }) async {
    final ocrDoc = await _ocrService.recognizeDocument(
      documentId: documentId,
      imagePaths: imagePaths,
      languageMode: languageMode,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

    // Index into SQLite FTS4 for instant Library Search
    await _searchService.indexDocumentOcr(
      documentId: documentId,
      title: documentTitle,
      fullText: ocrDoc.fullText,
      smartTitle: ocrDoc.suggestedTitle,
    );

    final results = <PageOcrResult>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final file = File(path);
      if (!await file.exists()) continue;
      final imageBytes = await file.readAsBytes();
      final pageData = i < ocrDoc.pages.length ? ocrDoc.pages[i] : null;

      final engineBlocks = <OcrBlockItem>[];
      if (pageData != null) {
        for (final line in pageData.lines) {
          if (line.text.trim().isEmpty) continue;
          engineBlocks.add(
            OcrBlockItem(
              text: line.text.trim(),
              top: line.top,
              left: line.left,
              width: math.max(1.0, line.width),
              height: math.max(12.0, line.height),
              isRtl: line.isRtl,
            ),
          );
        }
      }

      final pageResult = await Isolate.run(
        () => _buildPageOcrResultInIsolate(
          pageIndex: i,
          imagePath: path,
          imageBytes: imageBytes,
          mlKitBlocks: engineBlocks,
          ocrPageData: pageData,
        ),
      );
      results.add(pageResult);
    }

    return results;
  }

  /// Generates a real OpenXML Word (.docx) file containing embedded page images
  /// and editable OCR text paragraphs with full RTL/LTR support.
  Future<String> exportToDocx({
    required String documentId,
    required String documentTitle,
    required List<String> imagePaths,
    OcrLanguageMode languageMode = OcrLanguageMode.arabicEnglish,
    OcrCancellationToken? cancellationToken,
    ValueChanged<String>? onProgress,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception('لا توجد صفحات لتصديرها إلى Word.');
    }

    final ocrPages = await extractPagesOcr(
      documentId: documentId,
      documentTitle: documentTitle,
      imagePaths: imagePaths,
      languageMode: languageMode,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

    onProgress?.call(
      'جارٍ بناء ملف Word OpenXML (.docx) وتضمين الصور والنصوص...',
    );

    final docxBytes = await Isolate.run(
      () => _buildDocxArchiveInIsolate(
        documentTitle: documentTitle,
        pages: ocrPages,
      ),
    );

    final outDir = await const LocalMediaStorageService().exportsDirectory();
    final safeName = documentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = p.join(outDir.path, '${documentId}_$safeName.docx');
    await File(outPath).writeAsBytes(docxBytes, flush: true);

    onProgress?.call('تم إنشاء ملف Word (.docx) بنجاح!');
    return outPath;
  }

  /// Generates an Excel (.xlsx) workbook by sorting OCR blocks by `top` and `left`
  /// and grouping vertically proximate blocks into the same table row (RTL column ordering for Arabic).
  Future<String> exportToXlsx({
    required String documentId,
    required String documentTitle,
    required List<String> imagePaths,
    OcrLanguageMode languageMode = OcrLanguageMode.arabicEnglish,
    OcrCancellationToken? cancellationToken,
    ValueChanged<String>? onProgress,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception('لا توجد صفحات لتصديرها إلى Excel.');
    }

    final ocrPages = await extractPagesOcr(
      documentId: documentId,
      documentTitle: documentTitle,
      imagePaths: imagePaths,
      languageMode: languageMode,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );

    onProgress?.call('جارٍ تجميع الكتل النصية وبناء جدول Excel (.xlsx)...');

    final xlsxBytes = await Isolate.run(
      () => _buildXlsxWorkbookInIsolate(
        documentTitle: documentTitle,
        pages: ocrPages,
      ),
    );

    final outDir = await const LocalMediaStorageService().exportsDirectory();
    final safeName = documentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = p.join(outDir.path, '${documentId}_$safeName.xlsx');
    await File(outPath).writeAsBytes(xlsxBytes, flush: true);

    onProgress?.call('تم إنشاء ملف Excel (.xlsx) بنجاح!');
    return outPath;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Isolate Workers (Zero UI Jank)
// ─────────────────────────────────────────────────────────────────────────────

PageOcrResult _buildPageOcrResultInIsolate({
  required int pageIndex,
  required String imagePath,
  required Uint8List imageBytes,
  required List<OcrBlockItem> mlKitBlocks,
  OcrPageData? ocrPageData,
}) {
  var width = ocrPageData?.imageWidth ?? 1200;
  var height = ocrPageData?.imageHeight ?? 1600;

  img.Image? decoded;
  if (mlKitBlocks.isEmpty || width <= 0 || height <= 0) {
    decoded = img.decodeImage(imageBytes);
    if (decoded != null) {
      width = decoded.width;
      height = decoded.height;
    }
  }

  final blocks = List<OcrBlockItem>.from(mlKitBlocks);

  blocks.sort((a, b) {
    final dy = (a.top - b.top).abs();
    final avgH = (a.height + b.height) * 0.5;
    if (dy <= avgH * 0.6) {
      return a.left.compareTo(b.left);
    }
    return a.top.compareTo(b.top);
  });

  if (blocks.isEmpty && decoded != null) {
    final detectedRegions = _detectHorizontalTextBands(decoded);
    for (var idx = 0; idx < detectedRegions.length; idx++) {
      final band = detectedRegions[idx];
      blocks.add(
        OcrBlockItem(
          text: 'سطر مستخرج ${idx + 1} (قابل للتعديل - ص ${pageIndex + 1})',
          top: band.top,
          left: band.left,
          width: band.width,
          height: band.height,
          isRtl: true,
        ),
      );
    }
  }

  if (blocks.isEmpty) {
    blocks.add(
      OcrBlockItem(
        text: 'محتوى الصفحة ${pageIndex + 1} (نص قابل للتعديل)',
        top: 40,
        left: 40,
        width: width - 80.0,
        height: 32,
        isRtl: true,
      ),
    );
  }

  final fullText = blocks.map((b) => b.text).join('\n');

  return PageOcrResult(
    pageIndex: pageIndex,
    imagePath: imagePath,
    imageBytes: imageBytes,
    imageWidth: width,
    imageHeight: height,
    blocks: blocks,
    fullText: fullText,
    ocrPageData: ocrPageData,
  );
}

List<({double top, double left, double width, double height})>
    _detectHorizontalTextBands(img.Image source) {
  final sampleH = math.min(400, source.height);
  final sampleW = math.min(300, source.width);
  final small = img.copyResize(source, width: sampleW, height: sampleH);

  final rowInkCounts = List<int>.filled(sampleH, 0);
  for (var y = 0; y < sampleH; y++) {
    var darkCount = 0;
    for (var x = 0; x < sampleW; x++) {
      final p = small.getPixel(x, y);
      final lum = (p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000;
      if (lum < 165) darkCount++;
    }
    rowInkCounts[y] = darkCount;
  }

  final scaleY = source.height / sampleH;
  final bands = <({double top, double left, double width, double height})>[];
  final threshold = (sampleW * 0.04).round().clamp(3, 40);

  int? bandStart;
  for (var y = 0; y < sampleH; y++) {
    if (rowInkCounts[y] >= threshold) {
      bandStart ??= y;
    } else if (bandStart != null) {
      final bandHeight = y - bandStart;
      if (bandHeight >= 3) {
        bands.add((
          top: bandStart * scaleY,
          left: source.width * 0.08,
          width: source.width * 0.84,
          height: math.max(18.0, bandHeight * scaleY),
        ));
      }
      bandStart = null;
      if (bands.length >= 18) break;
    }
  }
  return bands;
}

/// Clusters OCR blocks into rows by sorting by `top` and `left` and grouping blocks
/// whose vertical coordinates are close (within `0.65 * averageHeight`).
List<List<OcrBlockItem>> clusterOcrBlocksIntoRows(List<OcrBlockItem> blocks) {
  if (blocks.isEmpty) return const [];

  final sorted = List<OcrBlockItem>.from(blocks)
    ..sort((a, b) {
      final topCmp = a.top.compareTo(b.top);
      if (topCmp != 0) return topCmp;
      return a.left.compareTo(b.left);
    });

  final rows = <List<OcrBlockItem>>[];
  for (final block in sorted) {
    if (rows.isEmpty) {
      rows.add([block]);
      continue;
    }

    final currentRow = rows.last;
    final avgRowCenterY =
        currentRow.map((e) => e.centerY).reduce((a, b) => a + b) /
            currentRow.length;
    final avgRowHeight =
        currentRow.map((e) => e.height).reduce((a, b) => a + b) /
            currentRow.length;

    final tolerance = math.max(14.0, avgRowHeight * 0.65);
    if ((block.centerY - avgRowCenterY).abs() <= tolerance) {
      currentRow.add(block);
    } else {
      rows.add([block]);
    }
  }

  // Sort blocks inside each row by `left` (or right-to-left if predominantly Arabic RTL)
  for (final row in rows) {
    final rtlCount = row.where((b) => b.isRtl).length;
    final isRowRtl = rtlCount > (row.length / 2);
    if (isRowRtl) {
      row.sort((a, b) => b.left.compareTo(a.left));
    } else {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
  }

  return rows;
}

Uint8List _buildDocxArchiveInIsolate({
  required String documentTitle,
  required List<PageOcrResult> pages,
}) {
  final archive = Archive();

  const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';
  _addXmlToArchive(archive, '[Content_Types].xml', contentTypesXml);

  const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
  _addXmlToArchive(archive, '_rels/.rels', rootRelsXml);

  final relsBuilder = XmlBuilder();
  relsBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  relsBuilder.element(
    'Relationships',
    namespaces: {
      'http://schemas.openxmlformats.org/package/2006/relationships': '',
    },
    nest: () {
      relsBuilder.element(
        'Relationship',
        attributes: {
          'Id': 'rIdStyles',
          'Type':
              'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles',
          'Target': 'styles.xml',
        },
      );
      for (var i = 0; i < pages.length; i++) {
        relsBuilder.element(
          'Relationship',
          attributes: {
            'Id': 'rIdImg${i + 1}',
            'Type':
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image',
            'Target': 'media/page_${i + 1}.jpg',
          },
        );
      }
    },
  );
  _addXmlToArchive(
    archive,
    'word/_rels/document.xml.rels',
    relsBuilder.buildDocument().toXmlString(pretty: true),
  );

  const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Cairo" w:hAnsi="Cairo" w:cs="Cairo"/>
        <w:sz w:val="24"/>
        <w:szCs w:val="24"/>
        <w:lang w:val="en-US" w:bidi="ar-SA"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
</w:styles>''';
  _addXmlToArchive(archive, 'word/styles.xml', stylesXml);

  for (var i = 0; i < pages.length; i++) {
    final bytes = pages[i].imageBytes;
    archive.addFile(
      ArchiveFile('word/media/page_${i + 1}.jpg', bytes.length, bytes),
    );
  }

  final docBuilder = XmlBuilder();
  docBuilder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  docBuilder.element(
    'w:document',
    attributes: {
      'xmlns:w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
      'xmlns:r':
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
      'xmlns:wp':
          'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
      'xmlns:a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'xmlns:pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
    },
    nest: () {
      docBuilder.element('w:body', nest: () {
        _buildWordParagraph(
          docBuilder,
          text: documentTitle,
          isRtl: true,
          isBold: true,
          fontSizeHalfPt: 32,
        );

        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final relId = 'rIdImg${i + 1}';

          _buildWordParagraph(
            docBuilder,
            text: '─── الصفحة ${i + 1} من ${pages.length} ───',
            isRtl: true,
            isBold: true,
            fontSizeHalfPt: 26,
          );

          const maxWidthEmu = 5303520;
          final aspect = page.imageHeight > 0 && page.imageWidth > 0
              ? page.imageHeight / page.imageWidth
              : 1.414;
          final widthEmu = maxWidthEmu;
          final heightEmu = (widthEmu * aspect).round().clamp(1000000, 7400000);

          docBuilder.element('w:p', nest: () {
            docBuilder.element('w:pPr', nest: () {
              docBuilder.element('w:jc', attributes: {'w:val': 'center'});
            });
            docBuilder.element('w:r', nest: () {
              docBuilder.element('w:drawing', nest: () {
                docBuilder.element(
                  'wp:inline',
                  attributes: {
                    'distT': '0',
                    'distB': '0',
                    'distL': '0',
                    'distR': '0',
                  },
                  nest: () {
                    docBuilder.element(
                      'wp:extent',
                      attributes: {
                        'cx': '$widthEmu',
                        'cy': '$heightEmu',
                      },
                    );
                    docBuilder.element(
                      'wp:docPr',
                      attributes: {
                        'id': '${i + 1}',
                        'name': 'Page ${i + 1}',
                      },
                    );
                    docBuilder.element('a:graphic', nest: () {
                      docBuilder.element(
                        'a:graphicData',
                        attributes: {
                          'uri':
                              'http://schemas.openxmlformats.org/drawingml/2006/picture',
                        },
                        nest: () {
                          docBuilder.element('pic:pic', nest: () {
                            docBuilder.element('pic:nvPicPr', nest: () {
                              docBuilder.element(
                                'pic:cNvPr',
                                attributes: {
                                  'id': '${i + 1}',
                                  'name': 'page_${i + 1}.jpg',
                                },
                              );
                              docBuilder.element('pic:cNvPicPr');
                            });
                            docBuilder.element('pic:blipFill', nest: () {
                              docBuilder.element(
                                'a:blip',
                                attributes: {'r:embed': relId},
                              );
                              docBuilder.element('a:stretch', nest: () {
                                docBuilder.element('a:fillRect');
                              });
                            });
                            docBuilder.element('pic:spPr', nest: () {
                              docBuilder.element('a:xfrm', nest: () {
                                docBuilder.element(
                                  'a:off',
                                  attributes: {'x': '0', 'y': '0'},
                                );
                                docBuilder.element(
                                  'a:ext',
                                  attributes: {
                                    'cx': '$widthEmu',
                                    'cy': '$heightEmu',
                                  },
                                );
                              });
                              docBuilder.element(
                                'a:prstGeom',
                                attributes: {'prst': 'rect'},
                                nest: () {
                                  docBuilder.element('a:avLst');
                                },
                              );
                            });
                          });
                        },
                      );
                    });
                  },
                );
              });
            });
          });

          _buildWordParagraph(
            docBuilder,
            text: 'النص المستخرج (قابل للتعديل - الصفحة ${i + 1}):',
            isRtl: true,
            isBold: true,
            fontSizeHalfPt: 24,
          );

          final rows = clusterOcrBlocksIntoRows(page.blocks);
          for (final row in rows) {
            final rowText = row.map((b) => b.text).join('   ');
            final isRtl = row.any((b) => b.isRtl) ||
                OfficeExporterService.isRtlText(rowText);
            _buildWordParagraph(
              docBuilder,
              text: rowText,
              isRtl: isRtl,
              isBold: false,
              fontSizeHalfPt: 24,
            );
          }

          if (i < pages.length - 1) {
            docBuilder.element('w:p', nest: () {
              docBuilder.element('w:r', nest: () {
                docBuilder.element('w:br', attributes: {'w:type': 'page'});
              });
            });
          }
        }

        docBuilder.element('w:sectPr', nest: () {
          docBuilder.element(
            'w:pgSz',
            attributes: {'w:w': '11906', 'w:h': '16838'},
          );
          docBuilder.element(
            'w:pgMar',
            attributes: {
              'w:top': '1134',
              'w:right': '1134',
              'w:bottom': '1134',
              'w:left': '1134',
            },
          );
          docBuilder.element('w:bidi');
        });
      });
    },
  );

  _addXmlToArchive(
    archive,
    'word/document.xml',
    docBuilder.buildDocument().toXmlString(pretty: true),
  );

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw Exception('فشل ضغط ملف Word (.docx).');
  }
  return Uint8List.fromList(encoded);
}

void _buildWordParagraph(
  XmlBuilder builder, {
  required String text,
  required bool isRtl,
  required bool isBold,
  required int fontSizeHalfPt,
}) {
  builder.element('w:p', nest: () {
    builder.element('w:pPr', nest: () {
      builder.element('w:bidi', attributes: {'w:val': isRtl ? '1' : '0'});
      builder.element(
        'w:jc',
        attributes: {'w:val': isRtl ? 'right' : 'left'},
      );
    });
    builder.element('w:r', nest: () {
      builder.element('w:rPr', nest: () {
        builder.element(
          'w:rFonts',
          attributes: {'w:ascii': 'Cairo', 'w:hAnsi': 'Cairo', 'w:cs': 'Cairo'},
        );
        if (isBold) {
          builder.element('w:b');
          builder.element('w:bCs');
        }
        builder.element('w:sz', attributes: {'w:val': '$fontSizeHalfPt'});
        builder.element('w:szCs', attributes: {'w:val': '$fontSizeHalfPt'});
        if (isRtl) {
          builder.element('w:rtl');
        }
      });
      builder.element(
        'w:t',
        attributes: {'xml:space': 'preserve'},
        nest: text,
      );
    });
  });
}

void _addXmlToArchive(Archive archive, String fileName, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
}

// ─────────────────────────────────────────────────────────────────────────────
// Intelligent Table Recognition & Excel (.xlsx) Rebuilding
// ─────────────────────────────────────────────────────────────────────────────

class _TableCellCandidate {
  const _TableCellCandidate({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.isRtl,
  });

  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final bool isRtl;

  double get width => math.max(1.0, right - left);
  double get height => math.max(1.0, bottom - top);
  double get centerX => left + width / 2.0;
  double get centerY => top + height / 2.0;
}

class _ColumnBand {
  _ColumnBand({
    required this.left,
    required this.right,
    required this.centerX,
  });

  double left;
  double right;
  double centerX;
  int sampleCount = 1;
}

List<_TableCellCandidate> _extractCellCandidates(OcrBlockItem block) {
  final text = block.text.trim();
  if (text.isEmpty) return const [];

  final delimiterRegex = RegExp(r'(\t|\||\s{2,})');
  final matches = delimiterRegex.allMatches(text).toList();

  if (matches.isEmpty) {
    return [
      _TableCellCandidate(
        text: text,
        left: block.left,
        right: block.right,
        top: block.top,
        bottom: block.bottom,
        isRtl: block.isRtl,
      ),
    ];
  }

  final candidates = <_TableCellCandidate>[];
  var lastEnd = 0;
  final totalChars = math.max(1, text.length);

  void addSlice(int start, int end) {
    final slice = text.substring(start, end).trim();
    if (slice.isEmpty) return;

    final startRatio = start / totalChars;
    final endRatio = end / totalChars;

    final cellLeft = block.left + startRatio * block.width;
    final cellRight = block.left + endRatio * block.width;

    candidates.add(
      _TableCellCandidate(
        text: slice,
        left: cellLeft,
        right: math.max(cellLeft + 8.0, cellRight),
        top: block.top,
        bottom: block.bottom,
        isRtl: OfficeExporterService.isRtlText(slice) || block.isRtl,
      ),
    );
  }

  for (final match in matches) {
    if (match.start > lastEnd) {
      addSlice(lastEnd, match.start);
    }
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    addSlice(lastEnd, text.length);
  }

  return candidates.isEmpty
      ? [
          _TableCellCandidate(
            text: text,
            left: block.left,
            right: block.right,
            top: block.top,
            bottom: block.bottom,
            isRtl: block.isRtl,
          ),
        ]
      : candidates;
}

List<List<_TableCellCandidate>> _clusterCandidatesIntoRows(
  List<_TableCellCandidate> candidates,
) {
  if (candidates.isEmpty) return const [];

  final sorted = List<_TableCellCandidate>.from(candidates)
    ..sort((a, b) {
      final topCmp = a.top.compareTo(b.top);
      if (topCmp != 0) return topCmp;
      return a.left.compareTo(b.left);
    });

  final rows = <List<_TableCellCandidate>>[];
  for (final item in sorted) {
    if (rows.isEmpty) {
      rows.add([item]);
      continue;
    }

    final currentRow = rows.last;
    final avgRowCenterY =
        currentRow.map((e) => e.centerY).reduce((a, b) => a + b) /
            currentRow.length;
    final avgRowHeight =
        currentRow.map((e) => e.height).reduce((a, b) => a + b) /
            currentRow.length;

    final tolerance = math.max(14.0, avgRowHeight * 0.65);
    if ((item.centerY - avgRowCenterY).abs() <= tolerance) {
      currentRow.add(item);
    } else {
      rows.add([item]);
    }
  }

  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
  }

  return rows;
}

List<_ColumnBand> _detectColumnBands(List<List<_TableCellCandidate>> rows) {
  final multiItemRows = rows.where((r) => r.length >= 2).toList();
  if (multiItemRows.isEmpty) {
    return const [];
  }

  final maxCols = multiItemRows.map((r) => r.length).reduce(math.max);
  if (maxCols <= 1) {
    return const [];
  }

  final templateRows = multiItemRows.where((r) => r.length == maxCols).toList();

  final bands = <_ColumnBand>[];
  for (var c = 0; c < maxCols; c++) {
    var sumLeft = 0.0;
    var sumRight = 0.0;
    var sumCenter = 0.0;
    for (final row in templateRows) {
      final cell = row[c];
      sumLeft += cell.left;
      sumRight += cell.right;
      sumCenter += cell.centerX;
    }
    final count = templateRows.length;
    bands.add(
      _ColumnBand(
        left: sumLeft / count,
        right: sumRight / count,
        centerX: sumCenter / count,
      )..sampleCount = count,
    );
  }

  final avgWidth = bands.isEmpty
      ? 100.0
      : (bands.last.centerX - bands.first.centerX) / math.max(1, bands.length);
  final gapThreshold = avgWidth * 0.8;

  for (final row in multiItemRows) {
    for (final cell in row) {
      final minDistance = bands
          .map((b) => (b.centerX - cell.centerX).abs())
          .reduce(math.min);
      if (minDistance > gapThreshold) {
        bands.add(
          _ColumnBand(
            left: cell.left,
            right: cell.right,
            centerX: cell.centerX,
          ),
        );
      }
    }
  }

  bands.sort((a, b) => a.centerX.compareTo(b.centerX));
  return bands;
}

Map<int, _TableCellCandidate> _alignRowToBands({
  required List<_TableCellCandidate> row,
  required List<_ColumnBand> bands,
  required double tableWidth,
}) {
  final result = <int, _TableCellCandidate>{};
  if (row.isEmpty || bands.isEmpty) {
    return result;
  }

  if (row.length == 1) {
    final item = row.first;
    if (item.width >= tableWidth * 0.45) {
      result[0] = item;
      return result;
    }
    var bestBand = 0;
    var bestDist = double.infinity;
    for (var b = 0; b < bands.length; b++) {
      final dist = (item.centerX - bands[b].centerX).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestBand = b;
      }
    }
    result[bestBand] = item;
    return result;
  }

  final m = row.length;
  final M = bands.length;

  if (m > M) {
    for (var i = 0; i < m; i++) {
      result[math.min(i, M - 1)] = row[i];
    }
    return result;
  }

  final dp = List.generate(m, (_) => List<double>.filled(M, double.infinity));
  final parent = List.generate(m, (_) => List<int>.filled(M, -1));

  for (var j = 0; j <= M - m; j++) {
    dp[0][j] = (row[0].centerX - bands[j].centerX).abs();
  }

  for (var i = 1; i < m; i++) {
    for (var j = i; j <= M - (m - i); j++) {
      var minPrevCost = double.infinity;
      var bestPrevBand = -1;
      for (var k = i - 1; k < j; k++) {
        if (dp[i - 1][k] < minPrevCost) {
          minPrevCost = dp[i - 1][k];
          bestPrevBand = k;
        }
      }
      if (minPrevCost < double.infinity) {
        final dist = (row[i].centerX - bands[j].centerX).abs();
        dp[i][j] = minPrevCost + dist;
        parent[i][j] = bestPrevBand;
      }
    }
  }

  var bestLastBand = -1;
  var minTotalCost = double.infinity;
  for (var j = m - 1; j < M; j++) {
    if (dp[m - 1][j] < minTotalCost) {
      minTotalCost = dp[m - 1][j];
      bestLastBand = j;
    }
  }

  if (bestLastBand == -1) {
    for (var i = 0; i < m; i++) {
      result[i] = row[i];
    }
    return result;
  }

  var currBand = bestLastBand;
  for (var i = m - 1; i >= 0; i--) {
    result[currBand] = row[i];
    currBand = parent[i][currBand];
  }

  return result;
}

Uint8List _buildXlsxWorkbookInIsolate({
  required String documentTitle,
  required List<PageOcrResult> pages,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  final headerBgColor = ExcelColor.fromHexString('#1B5E20'); // Emerald Green
  final whiteColor = ExcelColor.fromHexString('#FFFFFF');
  final zebraTintBgColor = ExcelColor.fromHexString('#F8FAF8');
  final summaryBgColor = ExcelColor.fromHexString('#E8F5E9');
  final summaryTextColor = ExcelColor.fromHexString('#1B5E20');
  final gridBorderColor = ExcelColor.fromHexString('#CBD5E1');
  final headerBorderColor = ExcelColor.fromHexString('#144A19');
  final subTitleBgColor = ExcelColor.fromHexString('#F1F5F9');
  final subTitleTextColor = ExcelColor.fromHexString('#475569');

  final thinGridBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: gridBorderColor,
  );
  final headerBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: headerBorderColor,
  );
  final doubleBottomBorder = Border(
    borderStyle: BorderStyle.Double,
    borderColorHex: summaryTextColor,
  );

  var isAnySheetRtl = false;

  for (var pageIdx = 0; pageIdx < pages.length; pageIdx++) {
    final page = pages[pageIdx];
    final sheetName = 'صفحة ${pageIdx + 1}';
    final Sheet sheet;
    if (pageIdx == 0 && defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
      sheet = excel[sheetName];
    } else {
      sheet = excel[sheetName];
    }

    // Extract all candidate cells across blocks
    final allCandidates = <_TableCellCandidate>[];
    for (final block in page.blocks) {
      allCandidates.addAll(_extractCellCandidates(block));
    }

    // Determine Sheet RTL direction based on language content
    final rtlCount = allCandidates.where((c) => c.isRtl).length;
    final isSheetRtl = rtlCount >= (allCandidates.length * 0.35);
    sheet.isRTL = isSheetRtl;
    if (isSheetRtl) isAnySheetRtl = true;

    final clusteredRows = _clusterCandidatesIntoRows(allCandidates);

    // Compute bounding table width
    var minTableLeft = double.infinity;
    var maxTableRight = 0.0;
    for (final c in allCandidates) {
      if (c.left < minTableLeft) minTableLeft = c.left;
      if (c.right > maxTableRight) maxTableRight = c.right;
    }
    final tableWidth = math.max(100.0, maxTableRight - minTableLeft);

    // Detect column bands
    final bands = _detectColumnBands(clusteredRows);
    final totalColumns = math.max(1, bands.length);

    int toExcelCol(int bandIndex) {
      if (totalColumns <= 1) return 0;
      return isSheetRtl ? (totalColumns - 1 - bandIndex) : bandIndex;
    }

    final maxCharsPerColumn = <int, int>{};

    // ─────────────────────────────────────────────────────────────────────────
    // Row 0: Document Title Banner
    // ─────────────────────────────────────────────────────────────────────────
    final titleCell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('$documentTitle - $sheetName');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 13,
      fontFamily: 'Cairo',
      fontColorHex: whiteColor,
      backgroundColorHex: headerBgColor,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: headerBorder,
      rightBorder: headerBorder,
      topBorder: headerBorder,
      bottomBorder: headerBorder,
    );
    sheet.setRowHeight(0, 30.0);

    // ─────────────────────────────────────────────────────────────────────────
    // Row 1: Page Metadata Banner
    // ─────────────────────────────────────────────────────────────────────────
    final metaCell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
    metaCell.value = TextCellValue(
      'تحويل ذكي بـ CamScanner Offline • جدول بيانات كامل قابل للتعديل • الكتل المستخرجة: ${page.blocks.length} • الأبعاد: ${page.imageWidth}x${page.imageHeight}',
    );
    metaCell.cellStyle = CellStyle(
      fontSize: 9,
      fontFamily: 'Cairo',
      fontColorHex: subTitleTextColor,
      backgroundColorHex: subTitleBgColor,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thinGridBorder,
      rightBorder: thinGridBorder,
      topBorder: thinGridBorder,
      bottomBorder: thinGridBorder,
    );
    sheet.setRowHeight(1, 20.0);

    if (totalColumns > 1) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(
          columnIndex: totalColumns - 1,
          rowIndex: 0,
        ),
      );
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
        CellIndex.indexByColumnRow(
          columnIndex: totalColumns - 1,
          rowIndex: 1,
        ),
      );
    }

    // Row 2: Spacer
    sheet.setRowHeight(2, 10.0);

    // ─────────────────────────────────────────────────────────────────────────
    // Detect Header Row & Process Table Rows
    // ─────────────────────────────────────────────────────────────────────────
    int? detectedHeaderRowIdx;
    for (var r = 0; r < clusteredRows.length; r++) {
      final row = clusteredRows[r];
      if (row.length >= 2 || (bands.isNotEmpty && row.length >= bands.length - 1)) {
        final numericCount = row
            .where(
              (c) => OfficeExporterService.parseFlexibleNumber(c.text) != null,
            )
            .length;
        if (numericCount <= (row.length * 0.4)) {
          detectedHeaderRowIdx = r;
          break;
        }
      }
    }
    detectedHeaderRowIdx ??= clusteredRows.isNotEmpty ? 0 : null;

    final summaryKeywords = [
      'المجموع',
      'الإجمالي',
      'المجموع الكلي',
      'الصافي',
      'صافي',
      'total',
      'grand total',
      'sum',
      'net',
      'subtotal',
    ];

    var excelRowOffset = 3;

    for (var r = 0; r < clusteredRows.length; r++) {
      final rowItems = clusteredRows[r];
      final targetRowIdx = excelRowOffset++;

      final isHeaderRow = (r == detectedHeaderRowIdx);
      final isSingleWideItem = (rowItems.length == 1 &&
          rowItems.first.width >= tableWidth * 0.45);

      final rowFullText =
          rowItems.map((e) => e.text.toLowerCase()).join(' ');
      final isSummaryRow = summaryKeywords.any(
        (kw) => rowFullText.contains(kw),
      );

      final isEvenDataRow = (targetRowIdx % 2 == 0);
      final rowBgColor = isHeaderRow
          ? headerBgColor
          : isSummaryRow
              ? summaryBgColor
              : isEvenDataRow
                  ? whiteColor
                  : zebraTintBgColor;

      sheet.setRowHeight(
        targetRowIdx,
        isHeaderRow || isSummaryRow ? 26.0 : 22.0,
      );

      // Initialize all grid cells in this table row with borders
      if (totalColumns > 1 && !isSingleWideItem) {
        for (var col = 0; col < totalColumns; col++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: targetRowIdx,
            ),
          );
          cell.cellStyle = CellStyle(
            backgroundColorHex: rowBgColor,
            leftBorder: isHeaderRow ? headerBorder : thinGridBorder,
            rightBorder: isHeaderRow ? headerBorder : thinGridBorder,
            topBorder: isHeaderRow ? headerBorder : thinGridBorder,
            bottomBorder: isHeaderRow
                ? headerBorder
                : isSummaryRow
                    ? doubleBottomBorder
                    : thinGridBorder,
          );
        }
      }

      if (isSingleWideItem) {
        final item = rowItems.first;
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: targetRowIdx),
        );
        cell.value = TextCellValue(item.text);
        cell.cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontFamily: 'Cairo',
          fontColorHex: ExcelColor.fromHexString('#0F172A'),
          backgroundColorHex: subTitleBgColor,
          horizontalAlign:
              item.isRtl ? HorizontalAlign.Right : HorizontalAlign.Left,
          verticalAlign: VerticalAlign.Center,
          leftBorder: thinGridBorder,
          rightBorder: thinGridBorder,
          topBorder: thinGridBorder,
          bottomBorder: thinGridBorder,
        );

        if (totalColumns > 1) {
          sheet.merge(
            CellIndex.indexByColumnRow(
              columnIndex: 0,
              rowIndex: targetRowIdx,
            ),
            CellIndex.indexByColumnRow(
              columnIndex: totalColumns - 1,
              rowIndex: targetRowIdx,
            ),
          );
        }
        continue;
      }

      // Align cells to column bands
      final alignment = bands.isEmpty
          ? {for (var i = 0; i < rowItems.length; i++) i: rowItems[i]}
          : _alignRowToBands(
              row: rowItems,
              bands: bands,
              tableWidth: tableWidth,
            );

      for (final entry in alignment.entries) {
        final bandIndex = entry.key;
        final cellItem = entry.value;
        final colIdx = toExcelCol(bandIndex);

        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIdx,
            rowIndex: targetRowIdx,
          ),
        );

        final numVal = OfficeExporterService.parseFlexibleNumber(cellItem.text);
        final isNumber = (numVal != null && !isHeaderRow);

        if (isNumber) {
          if (numVal is int) {
            cell.value = IntCellValue(numVal);
          } else {
            cell.value = DoubleCellValue(numVal.toDouble());
          }
        } else {
          cell.value = TextCellValue(cellItem.text);
        }

        // Track max characters for auto-fit column width
        final charLength = cellItem.text.trim().length;
        if (charLength > (maxCharsPerColumn[colIdx] ?? 0)) {
          maxCharsPerColumn[colIdx] = charLength;
        }

        final cellHorizontalAlign = isHeaderRow
            ? HorizontalAlign.Center
            : isNumber
                ? HorizontalAlign.Center
                : cellItem.isRtl
                    ? HorizontalAlign.Right
                    : HorizontalAlign.Left;

        cell.cellStyle = CellStyle(
          bold: isHeaderRow || isSummaryRow,
          fontSize: isHeaderRow || isSummaryRow ? 11 : 10,
          fontFamily: 'Cairo',
          fontColorHex: isHeaderRow
              ? whiteColor
              : isSummaryRow
                  ? summaryTextColor
                  : ExcelColor.fromHexString('#0F172A'),
          backgroundColorHex: rowBgColor,
          horizontalAlign: cellHorizontalAlign,
          verticalAlign: VerticalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          leftBorder: isHeaderRow ? headerBorder : thinGridBorder,
          rightBorder: isHeaderRow ? headerBorder : thinGridBorder,
          topBorder: isHeaderRow ? headerBorder : thinGridBorder,
          bottomBorder: isHeaderRow
              ? headerBorder
              : isSummaryRow
                  ? doubleBottomBorder
                  : thinGridBorder,
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Proportional Auto-Fit Column Widths
    // ─────────────────────────────────────────────────────────────────────────
    for (var c = 0; c < totalColumns; c++) {
      final maxLen = maxCharsPerColumn[c] ?? 8;
      final calculatedWidth =
          math.max(14.0, math.min(48.0, (maxLen * 1.45) + 4.0));
      sheet.setColumnWidth(c, calculatedWidth);
    }
  }

  if (defaultSheet != null &&
      defaultSheet != 'صفحة 1' &&
      excel.tables.containsKey(defaultSheet) &&
      excel.tables.length > 1) {
    excel.delete(defaultSheet);
  }

  var bytes = excel.save();
  if (bytes == null) {
    throw Exception('فشل إنشاء ملف Excel (.xlsx).');
  }

  if (isAnySheetRtl) {
    final decoded = ZipDecoder().decodeBytes(bytes);
    final newArchive = Archive();
    var modified = false;
    for (final file in decoded.files) {
      file.decompress();
      if (file.name.contains('worksheets/sheet') && file.name.endsWith('.xml')) {
        final contentStr = utf8.decode(file.content as List<int>);
        if (!contentStr.contains('rightToLeft="1"')) {
          final updated = contentStr.replaceFirst(
            '<sheetView ',
            '<sheetView rightToLeft="1" ',
          );
          if (updated != contentStr) {
            final newBytes = utf8.encode(updated);
            newArchive.addFile(
              ArchiveFile(file.name, newBytes.length, newBytes),
            );
            modified = true;
            continue;
          }
        }
      }
      newArchive.addFile(file);
    }
    if (modified) {
      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) {
        bytes = encoded;
      }
    }
  }

  return Uint8List.fromList(bytes);
}
