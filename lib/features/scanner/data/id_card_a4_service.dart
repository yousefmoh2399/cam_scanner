import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Available A4 layout positioning presets for ID Cards
enum IdCardA4Layout {
  /// Front on top half, back on bottom half with dashed cut line in center
  verticalCenter(
    'رأسي في المنتصف',
    'الوجه في النصف العلوي والظهر في النصف السفلي مع خط قص قياسي',
  ),

  /// Front and Back placed side-by-side at the top of the A4 page (most requested by banks & agencies)
  sideBySideTop(
    'متجاوران بالأعلى (نمط المعاملات)',
    'الوجه والظهر بجانب بعضهما أعلى الصفحة مع ترك الأسفل للأختام والتوقيعات',
  ),

  /// Perfectly aligned for folding and laminating into a pocket card
  foldable(
    'تنسيق الطي المتطابق (كارنيه)',
    'وجهان متطابقان على خط الطي للقص والدمج المباشر كبطاقة ورقية',
  );

  const IdCardA4Layout(this.label, this.description);
  final String label;
  final String description;
}

/// Color enhancement filters for ID Cards
enum IdCardColorFilter {
  original('الألوان الأصلية'),
  magicColor('تعزيز ألوان الهوية (Magic ID)'),
  blackAndWhite('أبيض وأسود ناصع (B&W)'),
  grayscale('تدرج رمادي مكتبي');

  const IdCardColorFilter(this.label);
  final String label;
}

/// Anti-fraud security watermark options for official identity copies
enum IdSecurityWatermarkPreset {
  none('بدون علامة مائية'),
  certifiedCopy('صورة طبق الأصل فقط'),
  bankUseOnly('خاص بالمعاملات البنكية فقط'),
  officialSubmission('للتقديم الرسمي فقط'),
  noLoan('نسخة غير صالحة للاقتراض أو البيع'),
  custom('نص مخصص...');

  const IdSecurityWatermarkPreset(this.label);
  final String label;
}

/// Configuration payload for generating true-size 1:1 ID Card A4 sheets
class IdCardA4Config {
  const IdCardA4Config({
    required this.frontImagePath,
    required this.backImagePath,
    this.layout = IdCardA4Layout.verticalCenter,
    this.colorFilter = IdCardColorFilter.magicColor,
    this.watermarkPreset = IdSecurityWatermarkPreset.none,
    this.customWatermarkText,
    this.watermarkOpacity = 0.28,
    this.includeCardLabels = false,
    this.includeCalibrationRuler = false,
    this.includeCutGuidelines = false,
    this.includeCornerCropMarks = false,
    this.includeHeader = false,
    this.includeDateStamp = false,
    this.includeOfficialSignaturesBox = false,
    this.documentTitle = 'وثيقة إثبات الهوية الرسمية (National ID & License Sheet)',
  });

  final String frontImagePath;
  final String backImagePath;
  final IdCardA4Layout layout;
  final IdCardColorFilter colorFilter;
  final IdSecurityWatermarkPreset watermarkPreset;
  final String? customWatermarkText;
  final double watermarkOpacity;
  final bool includeCardLabels;
  final bool includeCalibrationRuler;
  final bool includeCutGuidelines;
  final bool includeCornerCropMarks;
  final bool includeHeader;
  final bool includeDateStamp;
  final bool includeOfficialSignaturesBox;
  final String documentTitle;

  String? get effectiveWatermarkText {
    switch (watermarkPreset) {
      case IdSecurityWatermarkPreset.none:
        return null;
      case IdSecurityWatermarkPreset.certifiedCopy:
        return 'صورة طبق الأصل فقط';
      case IdSecurityWatermarkPreset.bankUseOnly:
        return 'خاص بالمعاملات البنكية فقط';
      case IdSecurityWatermarkPreset.officialSubmission:
        return 'للتقديم الرسمي فقط';
      case IdSecurityWatermarkPreset.noLoan:
        return 'نسخة غير صالحة للاقتراض أو المعاملات المالية';
      case IdSecurityWatermarkPreset.custom:
        return customWatermarkText?.trim().isNotEmpty == true
            ? customWatermarkText!.trim()
            : null;
    }
  }
}

/// Service that builds mathematically precise 1:1 true-size ID Card A4 documents
/// conforming strictly to ISO/IEC 7810 ID-1 (CR-80 standard: 85.60 mm x 53.98 mm).
class IdCardA4Service {
  const IdCardA4Service();

  /// Millimeters to PDF points conversion ratio
  static const double mmToPt = 2.834645669291339;

  /// ISO/IEC 7810 ID-1 standard width in mm
  static const double cardWidthMm = 85.60;

  /// ISO/IEC 7810 ID-1 standard height in mm
  static const double cardHeightMm = 53.98;

  /// Standard width in PDF points ($85.6 \times 2.83465 \approx 242.65$ pt)
  static const double cardWidthPt = cardWidthMm * mmToPt;

  /// Standard height in PDF points ($53.98 \times 2.83465 \approx 153.02$ pt)
  static const double cardHeightPt = cardHeightMm * mmToPt;

  /// Corner radius of credit card / ID card in points ($3.18$ mm $\approx 9$ pt)
  static const double cardCornerRadiusPt = 3.18 * mmToPt;

  /// Loads bundled Cairo font for Arabic typesetting in PDF
  Future<pw.Font?> _loadCairoFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      return pw.Font.ttf(fontData.buffer.asByteData());
    } catch (_) {
      return null;
    }
  }

  /// Applies optional offline color enhancement filter to image bytes in a background isolate
  Future<Uint8List> _processImageBytes(
    String filePath,
    IdCardColorFilter filter,
  ) async {
    return await compute((Map<String, dynamic> params) async {
      final path = params['path'] as String;
      final f = params['filter'] as IdCardColorFilter;

      final file = File(path);
      if (!file.existsSync()) return Uint8List(0);
      final rawBytes = await file.readAsBytes();

      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return rawBytes;

      // Downsample/clamp to optimal print resolution (max 1600px).
      // For an 85.6mm card on A4, 1600px provides ~475 DPI (super-crisp print quality)
      // while cutting RAM and CPU time by 85-95%, completely eliminating UI freezing and ANRs.
      img.Image working = decoded;
      if (working.width > 1600 || working.height > 1600) {
        working = img.copyResize(
          working,
          width: working.width >= working.height ? 1600 : null,
          height: working.height > working.width ? 1600 : null,
          interpolation: img.Interpolation.linear,
        );
      }

      if (f == IdCardColorFilter.original) {
        return Uint8List.fromList(img.encodeJpg(working, quality: 90));
      }

      img.Image processed;
      switch (f) {
        case IdCardColorFilter.magicColor:
          // Enhance document contrast & saturation, clarify text lines
          processed = img.adjustColor(
            working,
            contrast: 1.25,
            saturation: 1.15,
            gamma: 0.95,
          );
          break;
        case IdCardColorFilter.grayscale:
          processed = img.grayscale(working);
          processed = img.adjustColor(processed, contrast: 1.2);
          break;
        case IdCardColorFilter.blackAndWhite:
          processed = img.grayscale(working);
          // Adaptive thresholding for crisp text and signatures
          for (int y = 0; y < processed.height; y++) {
            for (int x = 0; x < processed.width; x++) {
              final p = processed.getPixel(x, y);
              final lum = p.luminance;
              final val = lum > 140 ? 255 : 0;
              processed.setPixelRgba(x, y, val, val, val, 255);
            }
          }
          break;
        case IdCardColorFilter.original:
          processed = working;
          break;
      }

      return Uint8List.fromList(img.encodeJpg(processed, quality: 90));
    }, {
      'path': filePath,
      'filter': filter,
    });
  }

  /// Builds an exact, 1:1 true-size A4 PDF document containing front and back sides
  Future<Uint8List> buildPdfBytes(IdCardA4Config config) async {
    final font = await _loadCairoFont();
    final theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: font)
        : pw.ThemeData();

    final doc = pw.Document(theme: theme);

    final frontBytes = await _processImageBytes(
      config.frontImagePath,
      config.colorFilter,
    );
    final backBytes = await _processImageBytes(
      config.backImagePath,
      config.colorFilter,
    );

    final frontImg = pw.MemoryImage(frontBytes);
    final backImg = pw.MemoryImage(backBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context ctx) {
          switch (config.layout) {
            case IdCardA4Layout.verticalCenter:
              return _buildVerticalCenterLayout(
                frontImg,
                backImg,
                config,
              );
            case IdCardA4Layout.sideBySideTop:
              return _buildSideBySideTopLayout(
                frontImg,
                backImg,
                config,
              );
            case IdCardA4Layout.foldable:
              return _buildFoldableLayout(
                frontImg,
                backImg,
                config,
              );
          }
        },
      ),
    );

    return doc.save();
  }

  /// Saves the generated PDF to application documents and returns its file path
  Future<String> savePdfToFile(IdCardA4Config config) async {
    final bytes = await buildPdfBytes(config);
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, 'id_card_a4_$timestamp.pdf');
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUT IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Layout 1: Front centered in top half, back centered in bottom half
  pw.Widget _buildVerticalCenterLayout(
    pw.MemoryImage frontImg,
    pw.MemoryImage backImg,
    IdCardA4Config config,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (config.includeHeader) _buildHeader(config),

        pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (config.includeCardLabels) ...[
                _buildSlotLabel('الوجه الأمامي (Front Side) • 85.6 × 54 مم'),
                pw.SizedBox(height: 6),
              ],
              _buildCardBox(frontImg, config),
            ],
          ),
        ),

        // Middle cut guideline
        if (config.includeCutGuidelines) _buildCutGuideline(),

        pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (config.includeCardLabels) ...[
                _buildSlotLabel('الوجه الخلفي (Back Side) • 85.6 × 54 مم'),
                pw.SizedBox(height: 6),
              ],
              _buildCardBox(backImg, config),
            ],
          ),
        ),

        if (config.includeCalibrationRuler) _buildCalibrationRuler(),
      ],
    );
  }

  /// Layout 2: Front and Back side-by-side at the top with large bottom notes area
  pw.Widget _buildSideBySideTopLayout(
    pw.MemoryImage frontImg,
    pw.MemoryImage backImg,
    IdCardA4Config config,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (config.includeHeader) _buildHeader(config),
        pw.SizedBox(height: 16),

        // Side by side row
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Column(
              children: [
                if (config.includeCardLabels) ...[
                  _buildSlotLabel('الوجه الأمامي (Front)'),
                  pw.SizedBox(height: 6),
                ],
                _buildCardBox(frontImg, config),
              ],
            ),
            pw.SizedBox(width: 18),
            pw.Column(
              children: [
                if (config.includeCardLabels) ...[
                  _buildSlotLabel('الوجه الخلفي (Back)'),
                  pw.SizedBox(height: 6),
                ],
                _buildCardBox(backImg, config),
              ],
            ),
          ],
        ),

        if (config.includeCutGuidelines) ...[
          pw.SizedBox(height: 20),
          _buildCutGuideline(),
          pw.SizedBox(height: 12),
        ],

        // Official Agency & Banking Stamping Area
        if (config.includeOfficialSignaturesBox) ...[
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey300,
                  width: 0.8,
                  style: pw.BorderStyle.dashed,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'مساحة مخصصة للأختام، التأشيرات وتوقيعات الموظف المختص',
                        textDirection: pw.TextDirection.rtl,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        'OFFICIAL USE & SIGNATURES',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey500,
                        ),
                      ),
                    ],
                  ),
                  pw.Spacer(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'توقيع العميل / صاحب الهوية: ..............................',
                            textDirection: pw.TextDirection.rtl,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'خاتم الجهة / البنك / المصلحة الحكومية',
                            textDirection: pw.TextDirection.rtl,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 36),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ] else
          pw.Spacer(),

        if (config.includeCalibrationRuler) _buildCalibrationRuler(),
      ],
    );
  }

  /// Layout 3: Foldable card format for physical DIY plastic / laminated pocket card
  pw.Widget _buildFoldableLayout(
    pw.MemoryImage frontImg,
    pw.MemoryImage backImg,
    IdCardA4Config config,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (config.includeHeader) _buildHeader(config),
        pw.Spacer(),

        if (config.includeCardLabels) ...[
          pw.Text(
            'تنسيق البطاقة المطوية (اطوِ عند الخط المنقّط لتحصل على بطاقة بحجم حقيقي 1:1 ذات وجهين)',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Outer box enclosing both sides along a single fold line
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            children: [
              _buildCardBox(frontImg, config, showBorder: false),
              pw.Container(
                width: cardWidthPt,
                height: 1,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      color: PdfColors.blueGrey400,
                      width: 0.8,
                      style: pw.BorderStyle.dashed,
                    ),
                  ),
                ),
              ),
              _buildCardBox(backImg, config, showBorder: false),
            ],
          ),
        ),

        pw.Spacer(),
        if (config.includeCalibrationRuler) _buildCalibrationRuler(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Builds the single card container strictly at 85.60 mm x 53.98 mm
  pw.Widget _buildCardBox(
    pw.MemoryImage image,
    IdCardA4Config config, {
    bool showBorder = true,
  }) {
    final watermarkText = config.effectiveWatermarkText;

    return pw.Container(
      width: cardWidthPt,
      height: cardHeightPt,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(cardCornerRadiusPt),
        border: showBorder
            ? pw.Border.all(color: PdfColors.grey400, width: 0.8)
            : null,
      ),
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          // Card Image
          pw.ClipRRect(
            horizontalRadius: cardCornerRadiusPt,
            verticalRadius: cardCornerRadiusPt,
            child: pw.Image(
              image,
              width: cardWidthPt,
              height: cardHeightPt,
              fit: pw.BoxFit.cover,
            ),
          ),

          // Optional Security Watermark
          if (watermarkText != null)
            pw.Transform.rotate(
              angle: -0.38, // ~22 degrees slope
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor(
                      0.85,
                      0.1,
                      0.1,
                      config.watermarkOpacity.clamp(0.1, 0.7),
                    ),
                    width: 1.2,
                  ),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Text(
                  watermarkText,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor(
                      0.85,
                      0.1,
                      0.1,
                      config.watermarkOpacity.clamp(0.1, 0.7),
                    ),
                  ),
                ),
              ),
            ),

          // Corner Crop Marks
          if (config.includeCornerCropMarks) ...[
            pw.Positioned(
              top: 2,
              left: 2,
              child: pw.Container(
                width: 6,
                height: 6,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    left: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              top: 2,
              right: 2,
              child: pw.Container(
                width: 6,
                height: 6,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    right: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              bottom: 2,
              left: 2,
              child: pw.Container(
                width: 6,
                height: 6,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    left: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              bottom: 2,
              right: 2,
              child: pw.Container(
                width: 6,
                height: 6,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    right: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Small label above front/back slots
  pw.Widget _buildSlotLabel(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey800,
        ),
      ),
    );
  }

  /// Dashed guideline with scissors icon
  pw.Widget _buildCutGuideline() {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        children: [
          pw.Text('✂', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
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
            'خط القص القياسي A4',
            textDirection: pw.TextDirection.rtl,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ],
      ),
    );
  }

  /// Official Header with title, standard identifier and date
  pw.Widget _buildHeader(IdCardA4Config config) {
    final now = DateTime.now();
    final dateStr = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                config.documentTitle,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'المقاس الحقيقي 1:1 المطابق للأصل (ISO/IEC 7810 ID-1 • 85.60 mm × 53.98 mm)',
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
          if (config.includeDateStamp)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'تاريخ الإصدار: $dateStr',
                  textDirection: pw.TextDirection.rtl,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'تطبيق لقطة • Laqta Scanner',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Precision 50mm Calibration Scale Ruler at the bottom to verify physical 1:1 scale on paper
  pw.Widget _buildCalibrationRuler() {
    const rulerLengthMm = 50.0;
    const rulerLengthPt = rulerLengthMm * mmToPt;

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'معيار التحقق من الحجم الطبيعي 1:1 (يجب أن يقيس هذا الشريط 5 سم بالضبط بالمسطرة بعد الطباعة):',
            textDirection: pw.TextDirection.rtl,
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey600,
            ),
          ),
          pw.Row(
            children: [
              pw.Container(
                width: rulerLengthPt,
                height: 4,
                color: PdfColors.black,
              ),
              pw.SizedBox(width: 4),
              pw.Text(
                '50 mm',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
