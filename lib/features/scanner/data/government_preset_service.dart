import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────────────────────────────────────
// Enumerations
// ─────────────────────────────────────────────────────────────────────────────

/// Supported official document and identity types.
enum GovDocType {
  /// National ID or driving license card (ISO/IEC 7810 ID-1: 85.6 mm × 53.98 mm).
  nationalId,

  /// Passport booklet page (ICAO Doc 9303).
  passport,

  /// Official certificate or document.
  certificate,

  /// Personal photograph 3 cm × 4 cm.
  personalPhoto3x4,

  /// Personal photograph 4 cm × 6 cm.
  personalPhoto4x6,

  /// Schengen / EU / UK Passport Photo 3.5 cm × 4.5 cm (35×45 mm).
  personalPhoto35x45,

  /// US Visa / Green Card / India 2 × 2 inches (5.08 cm × 5.08 cm).
  personalPhoto2x2,
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Builds PDF layouts and image presets conforming to international identity
/// standards and official submission portal specifications.
///
/// All PDF files are written to the application documents directory and their
/// paths are returned so the caller can share/print them.
class GovernmentPresetService {
  const GovernmentPresetService();

  // ── Portal compression presets ─────────────────────────────────────────────

  /// Universal portal and email file-size limits with icons for use in a UI list.
  static const List<({String label, int kb, IconData icon})> portalPresets = [
    (
      label: 'ضغط فائق للمواقع المحدودة (<100KB)',
      kb: 100,
      icon: Icons.speed_rounded,
    ),
    (
      label: 'معظم بوابات التوظيف والخدمات (<200KB)',
      kb: 200,
      icon: Icons.admin_panel_settings_rounded,
    ),
    (
      label: 'منصات التأشيرات والسفارات والجامعات (<500KB)',
      kb: 500,
      icon: Icons.workspace_premium_rounded,
    ),
    (
      label: 'البريد والمراسلات القياسية (<1MB)',
      kb: 1024,
      icon: Icons.email_rounded,
    ),
    (
      label: 'جودة عالية للأرشفة الرسمية (<2MB)',
      kb: 2048,
      icon: Icons.high_quality_rounded,
    ),
  ];

  // ── PDF builders ───────────────────────────────────────────────────────────

  /// Loads bundled Cairo font if available for crisp Arabic typesetting in PDF.
  Future<pw.Font?> _loadCairoFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      return pw.Font.ttf(fontData.buffer.asByteData());
    } catch (_) {
      return null;
    }
  }

  /// Creates an A4 PDF with the identity card front image on the top half and
  /// the back image on the bottom half.
  ///
  /// Features:
  /// - Exact official dimensions: ID-1 standard (85.6 mm × 53.98 mm) or enlarged (1.35x)
  /// - Centered layout with card frames and rounded corners
  /// - International standard header and cut guideline separator (✂)
  /// - Official verification footer
  Future<String> buildNationalIdA4(
    String frontImagePath,
    String backImagePath, {
    bool isActualSize = false,
    String? title,
    bool includeHeader = false,
    bool includeCutGuideline = false,
    bool includeLabels = false,
    bool includeFooter = false,
  }) async {
    final frontBytes = await File(frontImagePath).readAsBytes();
    final backBytes = await File(backImagePath).readAsBytes();
    final font = await _loadCairoFont();

    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: font)
        : pw.ThemeData();

    final pdf = pw.Document(theme: theme);
    final frontImage = pw.MemoryImage(frontBytes);
    final backImage = pw.MemoryImage(backBytes);

    // 1 mm = 2.83465 pt.
    // Standard ISO/IEC 7810 ID-1: 85.60 mm × 53.98 mm.
    const mmToPt = 2.83465;
    final cardW = isActualSize ? (85.6 * mmToPt) : (116.0 * mmToPt);
    final cardH = isActualSize ? (53.98 * mmToPt) : (73.2 * mmToPt);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ── Optional Header ──
              if (includeHeader) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.only(bottom: 12),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        title ?? 'وثيقة إثبات الهوية الرسمية',
                        textDirection: pw.TextDirection.rtl,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey900,
                        ),
                      ),
                      pw.Text(
                        'OFFICIAL IDENTITY CARD (ISO/IEC 7810 ID-1)',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 18),
              ],

              // ── Front Card Section ──
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (includeLabels) ...[
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        margin: const pw.EdgeInsets.only(bottom: 8),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          'الوجه الأمامي (Front)',
                          textDirection: pw.TextDirection.rtl,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                    pw.Container(
                      width: cardW,
                      height: cardH,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(10),
                        border: pw.Border.all(
                          color: PdfColors.grey500,
                          width: 1,
                        ),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 10,
                        verticalRadius: 10,
                        child: pw.Image(
                          frontImage,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Optional Cut guideline ──
              if (includeCutGuideline) ...[
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        '-- ✂ --',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey500,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          height: 0.5,
                          margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: PdfColors.grey400,
                                width: 0.5,
                                style: pw.BorderStyle.dashed,
                              ),
                            ),
                          ),
                        ),
                      ),
                      pw.Text(
                        'خط القص القياسي المعتمد',
                        textDirection: pw.TextDirection.rtl,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Back Card Section ──
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (includeLabels) ...[
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        margin: const pw.EdgeInsets.only(bottom: 8),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          'الوجه الخلفي (Back)',
                          textDirection: pw.TextDirection.rtl,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                    pw.Container(
                      width: cardW,
                      height: cardH,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(10),
                        border: pw.Border.all(
                          color: PdfColors.grey500,
                          width: 1,
                        ),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 10,
                        verticalRadius: 10,
                        child: pw.Image(
                          backImage,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Optional Footer ──
              if (includeFooter) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey300, width: 0.75),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        isActualSize
                            ? 'المقاس الفعلي القياسي: 85.6 × 54 مم (ISO/IEC 7810 ID-1)'
                            : 'المقاس المكبر عالي الوضوح: 1.35x للتقديم الإلكتروني والبنكي',
                        textDirection: pw.TextDirection.rtl,
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        'نسخة رسمية معتمدة • مسح ضوئي عالي الدقة',
                        textDirection: pw.TextDirection.rtl,
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    return _savePdf(pdf, 'identity_card_a4');
  }

  /// Creates an A4 PDF with [imagePath] centred on the page with official framing.
  Future<String> buildPassportPage(
    String imagePath, {
    bool isLandscape = false,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final font = await _loadCairoFont();

    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: font)
        : pw.ThemeData();

    final pdf = pw.Document(theme: theme);
    final image = pw.MemoryImage(bytes);

    pdf.addPage(
      pw.Page(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        build: (context) => pw.Column(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 12),
              margin: const pw.EdgeInsets.only(bottom: 20),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'وثيقة سفر رسمية - صورة الجواز',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.Text(
                    'PASSPORT COPY (ICAO DOC 9303)',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Center(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(
                      color: PdfColors.grey400,
                      width: 1,
                    ),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Image(
                      image,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'نسخة معتمدة مطابقة لأصل وثيقة السفر لغايات استخراج التأشيرات والتقديم الرسمي والدولي',
              textDirection: pw.TextDirection.rtl,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
      ),
    );

    return _savePdf(pdf, 'passport_page');
  }

  /// Creates an A4 PDF with [imagePath] centred with an official document border.
  Future<String> buildCertificatePage(
    String imagePath, {
    bool isLandscape = true,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final font = await _loadCairoFont();

    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: font)
        : pw.ThemeData();

    final pdf = pw.Document(theme: theme);
    final image = pw.MemoryImage(bytes);

    pdf.addPage(
      pw.Page(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.amber800, width: 2),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.75),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      image,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'وثيقة رسمية معتمدة - صالحة للجهات الحكومية والجامعات والشركات',
                      textDirection: pw.TextDirection.rtl,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'OFFICIAL CERTIFICATE & ARCHIVE',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return _savePdf(pdf, 'certificate_page');
  }

  /// Creates an A4 PDF with a grid of copies of [imagePath].
  ///
  /// Supports:
  /// - [GovDocType.personalPhoto3x4]: 3 × 4 cm (8 copies, 4×2)
  /// - [GovDocType.personalPhoto4x6]: 4 × 6 cm (4 copies, 2×2)
  /// - [GovDocType.personalPhoto35x45]: 3.5 × 4.5 cm (8 copies, 4×2) - Schengen/UK/EU
  /// - [GovDocType.personalPhoto2x2]: 5.08 × 5.08 cm (6 copies, 3×2) - US Visa / 2x2"
  Future<String> buildPersonalPhotoGrid(
    String imagePath,
    GovDocType type,
  ) async {
    final bytes = await File(imagePath).readAsBytes();
    final memImage = pw.MemoryImage(bytes);
    final font = await _loadCairoFont();

    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: font)
        : pw.ThemeData();

    final pdf = pw.Document(theme: theme);

    // Physical sizes in PDF points (1 pt = 1/72 inch; 1 cm ≈ 28.346 pt)
    const cmToPt = 28.3465;
    const spacingPt = 12.0;

    final double photoW;
    final double photoH;
    final int cols;
    final int rows;
    final String typeTitle;
    final String typeDesc;

    switch (type) {
      case GovDocType.personalPhoto3x4:
        photoW = 3.0 * cmToPt; // 85.04 pt
        photoH = 4.0 * cmToPt; // 113.39 pt
        cols = 4;
        rows = 2;
        typeTitle = 'استوديو الصور الشخصية - مقاس 3×4 سم (8 صور)';
        typeDesc = 'مخصصة لبطاقات الهوية، رخص القيادة، والكارنيهات';
        break;
      case GovDocType.personalPhoto4x6:
        photoW = 4.0 * cmToPt; // 113.39 pt
        photoH = 6.0 * cmToPt; // 170.08 pt
        cols = 2;
        rows = 2;
        typeTitle = 'استوديو الصور الشخصية - مقاس 4×6 سم (4 صور)';
        typeDesc = 'مخصصة لجوازات السفر واستمارات التقديم والمعاملات الرسمية';
        break;
      case GovDocType.personalPhoto35x45:
        photoW = 3.5 * cmToPt; // 99.21 pt
        photoH = 4.5 * cmToPt; // 127.56 pt
        cols = 4;
        rows = 2;
        typeTitle = 'استوديو صور التأشيرة - مقاس 35×45 مم (8 صور)';
        typeDesc = 'معتمدة لتأشيرات شنغن الأوروبية، بريطانيا، كندا، وأستراليا';
        break;
      case GovDocType.personalPhoto2x2:
        photoW = 5.08 * cmToPt; // 144 pt (2 inches)
        photoH = 5.08 * cmToPt; // 144 pt (2 inches)
        cols = 3;
        rows = 2;
        typeTitle = 'استوديو صور التأشيرة - مقاس 2×2 بوصة / 5×5 سم (6 صور)';
        typeDesc = 'معتمدة لتأشيرات الولايات المتحدة الأمريكية (US Visa) والجرين كارد والهند';
        break;
      default:
        photoW = 4.0 * cmToPt;
        photoH = 6.0 * cmToPt;
        cols = 2;
        rows = 2;
        typeTitle = 'استوديو الصور الشخصية (4 صور)';
        typeDesc = 'مجهزة للطباعة المباشرة على ورقة A4';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 8),
                margin: const pw.EdgeInsets.only(bottom: 24),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      typeTitle,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900,
                      ),
                    ),
                    pw.Text(
                      'PRINT-READY PHOTO SHEET',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),

              // Centered Photos Grid with cut guidelines
              pw.Expanded(
                child: pw.Center(
                  child: pw.Wrap(
                    spacing: spacingPt,
                    runSpacing: spacingPt,
                    alignment: pw.WrapAlignment.center,
                    children: List.generate(
                      cols * rows,
                      (_) => pw.Container(
                        width: photoW,
                        height: photoH,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.grey400,
                            width: 0.75,
                          ),
                        ),
                        child: pw.Image(
                          memImage,
                          fit: pw.BoxFit.cover,
                          width: photoW,
                          height: photoH,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Footer with scissors guide
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey300, width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      typeDesc,
                      textDirection: pw.TextDirection.rtl,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      '✂ قم بالقص بمحاذاة الإطار الرمادي الخارجي لكل صورة',
                      textDirection: pw.TextDirection.rtl,
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final String label;
    switch (type) {
      case GovDocType.personalPhoto3x4:
        label = '3x4';
        break;
      case GovDocType.personalPhoto4x6:
        label = '4x6';
        break;
      case GovDocType.personalPhoto35x45:
        label = '35x45mm';
        break;
      case GovDocType.personalPhoto2x2:
        label = '2x2inch';
        break;
      default:
        label = 'custom';
    }
    return _savePdf(pdf, 'photo_grid_$label');
  }

  // ── Compression ────────────────────────────────────────────────────────────

  /// Loads [imagePath] and ensures the compressed JPEG is strictly
  /// less than or equal to [targetKb].
  ///
  /// Automatically optimizes quality and scales resolution if necessary
  /// to guarantee the hard limit required by Egyptian government portals.
  Future<Uint8List> compressToTargetSize(
    String imagePath, {
    required int targetKb,
  }) async {
    return compute(_compressIsolate, _CompressParams(
      bytes: await File(imagePath).readAsBytes(),
      targetKb: targetKb,
    ));
  }

  /// Compresses [imagePath] to strictly <= [targetKb] and saves the result.
  Future<String> compressToTargetSizeAndSave(
    String imagePath, {
    required int targetKb,
    String? outPath,
  }) async {
    final compressed = await compressToTargetSize(
      imagePath,
      targetKb: targetKb,
    );

    final String destination;
    if (outPath != null && outPath.isNotEmpty) {
      destination = outPath;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      destination = p.join(dir.path, 'compressed_${targetKb}kb_$ts.jpg');
    }

    await File(destination).writeAsBytes(compressed, flush: true);
    return destination;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Saves [pdf] as `<baseName>_<timestamp>.pdf` in the app documents dir.
  Future<String> _savePdf(pw.Document pdf, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(dir.path, '${baseName}_$ts.pdf');
    final bytes = await pdf.save();
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate helpers
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _CompressParams {
  const _CompressParams({required this.bytes, required this.targetKb});
  final Uint8List bytes;
  final int targetKb;
}

/// Binary-search JPEG quality & downscale dimensions so the output is
/// strictly <= [params.targetKb] bytes (hard ceiling for government upload).
Uint8List _compressIsolate(_CompressParams params) {
  var decoded = img.decodeImage(params.bytes);
  if (decoded == null) return params.bytes;

  final targetBytes = params.targetKb * 1024;

  // 1. Binary search quality between 10 and 95
  int lo = 10;
  int hi = 95;
  Uint8List? bestUnderCeiling;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final candidate = Uint8List.fromList(img.encodeJpg(decoded, quality: mid));
    if (candidate.length <= targetBytes) {
      bestUnderCeiling = candidate;
      lo = mid + 1; // Try higher quality while staying strictly under ceiling
    } else {
      hi = mid - 1; // Exceeded target, reduce quality
    }
  }

  // 2. If even quality 10 is > targetBytes, downscale dimensions progressively
  if (bestUnderCeiling == null || bestUnderCeiling.length > targetBytes) {
    var curImage = decoded;
    // Downscale steps: 0.85, 0.70, 0.55, 0.40, 0.30, 0.20
    for (final scale in [0.85, 0.70, 0.55, 0.40, 0.30, 0.20]) {
      final newW = (decoded.width * scale).round();
      final newH = (decoded.height * scale).round();
      if (newW < 120 || newH < 120) break;

      curImage = img.copyResize(
        decoded,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );

      // Try candidate at medium quality
      var candidate = Uint8List.fromList(img.encodeJpg(curImage, quality: 65));
      if (candidate.length <= targetBytes) {
        bestUnderCeiling = candidate;
        break;
      }
      // If still over, try lower quality
      candidate = Uint8List.fromList(img.encodeJpg(curImage, quality: 35));
      if (candidate.length <= targetBytes) {
        bestUnderCeiling = candidate;
        break;
      }
    }
  }

  // Fallback to lowest possible quality if still null
  bestUnderCeiling ??= Uint8List.fromList(img.encodeJpg(decoded, quality: 10));

  return bestUnderCeiling;
}
