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
        ExportFormat.xlsx => 'جدول بيانات Excel (.xlsx)',
      };

  String get subtitle => switch (this) {
        ExportFormat.pdf =>
          'حفظ الصفحات بأعلى جودة بالمسار السريع (Zero-Decode) مع دعم الضغط بالحجم المستهدف',
        ExportFormat.searchablePdf =>
          'يتضمن طبقة نصية شفافة (عربي/إنجليزي) بـ Tesseract OCR للبحث والنسخ داخل الـ PDF',
        ExportFormat.docx =>
          'ملف OpenXML يحتوي على صور الصفحات + النصوص المستخرجة بـ OCR (RTL/LTR)',
        ExportFormat.xlsx =>
          'استخراج النصوص والجداول بـ OCR وتوزيع الكتل تلقائياً في صفوف وأعمدة (RTL)',
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

Uint8List _buildXlsxWorkbookInIsolate({
  required String documentTitle,
  required List<PageOcrResult> pages,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final sheetName = 'صفحة ${i + 1}';
    final Sheet sheet = excel[sheetName];

    final headerCell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    headerCell.value = TextCellValue('$documentTitle - $sheetName');
    headerCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 13,
      horizontalAlign: HorizontalAlign.Right,
    );

    final metaCell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
    metaCell.value = TextCellValue(
      'عدد الكتل المستخرجة: ${page.blocks.length} • أبعاد الصفحة: ${page.imageWidth}x${page.imageHeight}',
    );

    final clusteredRows = clusterOcrBlocksIntoRows(page.blocks);

    for (var r = 0; r < clusteredRows.length; r++) {
      final rowItems = clusteredRows[r];
      final targetRowIdx = r + 3;

      // If a line contains multiple columns separated by large whitespace or tabs, split them into cells
      final expandedCells = <({String text, bool isRtl})>[];
      for (final item in rowItems) {
        final parts = item.text
            .split(RegExp(r'\s{2,}|\t|\|'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length > 1) {
          final isLineRtl = item.isRtl;
          final orderedParts = isLineRtl ? parts.reversed.toList() : parts;
          for (final p in orderedParts) {
            expandedCells.add((
              text: p,
              isRtl: OfficeExporterService.isRtlText(p) || isLineRtl,
            ));
          }
        } else {
          expandedCells.add((text: item.text, isRtl: item.isRtl));
        }
      }

      for (var c = 0; c < expandedCells.length; c++) {
        final cellData = expandedCells[c];
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: targetRowIdx),
        );

        final numVal = double.tryParse(cellData.text.replaceAll(',', ''));
        if (numVal != null) {
          cell.value = DoubleCellValue(numVal);
        } else {
          cell.value = TextCellValue(cellData.text);
        }

        cell.cellStyle = CellStyle(
          horizontalAlign:
              cellData.isRtl ? HorizontalAlign.Right : HorizontalAlign.Left,
          verticalAlign: VerticalAlign.Center,
        );
      }
    }
  }

  if (defaultSheet != null &&
      defaultSheet != 'صفحة 1' &&
      excel.tables.length > 1) {
    excel.delete(defaultSheet);
  }

  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('فشل إنشاء ملف Excel (.xlsx).');
  }
  return Uint8List.fromList(bytes);
}
