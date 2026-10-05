import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────────────────────────────────────
// Enumerations
// ─────────────────────────────────────────────────────────────────────────────

/// Supported Egyptian-government document types.
enum GovDocType {
  /// National ID card (ISO/IEC 7810 ID-1: 85.6 mm × 53.98 mm).
  nationalId,

  /// Passport booklet page.
  passport,

  /// Official certificate (e.g. birth/death/graduation).
  certificate,

  /// Personal photograph 3 cm × 4 cm.
  personalPhoto3x4,

  /// Personal photograph 4 cm × 6 cm.
  personalPhoto4x6,
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Builds PDF layouts and image presets tailored for Egyptian government
/// submission portals.
///
/// All PDF files are written to the application documents directory and their
/// paths are returned so the caller can share/print them.
class GovernmentPresetService {
  const GovernmentPresetService();

  // ── Portal compression presets ─────────────────────────────────────────────

  /// Common Egyptian portal file-size limits with icons for use in a UI list.
  static const List<({String label, int kb, IconData icon})> portalPresets = [
    (
      label: 'بوابة ميزانية الدولة (<100KB)',
      kb: 100,
      icon: Icons.account_balance_rounded,
    ),
    (
      label: 'معظم البوابات الحكومية (<200KB)',
      kb: 200,
      icon: Icons.admin_panel_settings_rounded,
    ),
    (
      label: 'منصة الشهادات والتراخيص (<500KB)',
      kb: 500,
      icon: Icons.workspace_premium_rounded,
    ),
    (
      label: 'البريد المصري الإلكتروني (<1MB)',
      kb: 1024,
      icon: Icons.email_rounded,
    ),
  ];

  // ── PDF builders ───────────────────────────────────────────────────────────

  /// Creates an A4 PDF with the national-ID front image on the top half and
  /// the back image on the bottom half.
  ///
  /// The national ID physical size (ISO/IEC 7810 ID-1) is 85.6 mm × 53.98 mm;
  /// the images are scaled to fill each half of the A4 page.
  Future<String> buildNationalIdA4(
    String frontImagePath,
    String backImagePath,
  ) async {
    final frontBytes = await File(frontImagePath).readAsBytes();
    final backBytes = await File(backImagePath).readAsBytes();

    final pdf = pw.Document();

    final frontImage = pw.MemoryImage(frontBytes);
    final backImage = pw.MemoryImage(backBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          final pageWidth = PdfPageFormat.a4.availableWidth;
          final halfHeight = PdfPageFormat.a4.availableHeight / 2;

          return pw.Column(
            children: [
              // Front image – top half
              pw.Container(
                width: pageWidth,
                height: halfHeight,
                child: pw.Image(
                  frontImage,
                  fit: pw.BoxFit.contain,
                  width: pageWidth,
                  height: halfHeight,
                ),
              ),
              // Back image – bottom half
              pw.Container(
                width: pageWidth,
                height: halfHeight,
                child: pw.Image(
                  backImage,
                  fit: pw.BoxFit.contain,
                  width: pageWidth,
                  height: halfHeight,
                ),
              ),
            ],
          );
        },
      ),
    );

    return _savePdf(pdf, 'national_id_a4');
  }

  /// Creates an A4 PDF with [imagePath] centred on the page.
  Future<String> buildPassportPage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );

    return _savePdf(pdf, 'passport_page');
  }

  /// Creates a **landscape** A4 PDF with [imagePath] centred on the page.
  Future<String> buildCertificatePage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );

    return _savePdf(pdf, 'certificate_page');
  }

  /// Creates an A4 PDF with a grid of copies of [imagePath].
  ///
  /// | [type]            | Photo size | Grid   | Copies |
  /// |-------------------|-----------|--------|--------|
  /// | personalPhoto3x4  | 3 × 4 cm  | 4 × 2  | 8      |
  /// | personalPhoto4x6  | 4 × 6 cm  | 2 × 2  | 4      |
  ///
  /// A 2 mm margin separates each copy.
  Future<String> buildPersonalPhotoGrid(
    String imagePath,
    GovDocType type,
  ) async {
    assert(
      type == GovDocType.personalPhoto3x4 ||
          type == GovDocType.personalPhoto4x6,
      'buildPersonalPhotoGrid only supports personalPhoto3x4 and personalPhoto4x6',
    );

    final bytes = await File(imagePath).readAsBytes();
    final memImage = pw.MemoryImage(bytes);
    final pdf = pw.Document();

    // Physical sizes in PDF points (1 pt = 1/72 inch; 1 cm ≈ 28.346 pt)
    const cmToPt = 28.3465;
    const marginPt = 2 * cmToPt / 10; // 2 mm

    final double photoW;
    final double photoH;
    final int cols;
    final int rows;

    if (type == GovDocType.personalPhoto3x4) {
      photoW = 3 * cmToPt;
      photoH = 4 * cmToPt;
      cols = 4;
      rows = 2;
    } else {
      // personalPhoto4x6
      photoW = 4 * cmToPt;
      photoH = 6 * cmToPt;
      cols = 2;
      rows = 2;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Wrap(
            spacing: marginPt,
            runSpacing: marginPt,
            children: List.generate(
              cols * rows,
              (_) => pw.Container(
                width: photoW,
                height: photoH,
                child: pw.Image(
                  memImage,
                  fit: pw.BoxFit.cover,
                  width: photoW,
                  height: photoH,
                ),
              ),
            ),
          );
        },
      ),
    );

    final label = type == GovDocType.personalPhoto3x4 ? '3x4' : '4x6';
    return _savePdf(pdf, 'photo_grid_$label');
  }

  // ── Compression ────────────────────────────────────────────────────────────

  /// Loads [imagePath] and binary-searches for the JPEG quality level that
  /// produces a file within 10 % of [targetKb].
  ///
  /// Quality is bounded between 10 and 95.
  Future<Uint8List> compressToTargetSize(
    String imagePath, {
    required int targetKb,
  }) async {
    return compute(_compressIsolate, _CompressParams(
      bytes: await File(imagePath).readAsBytes(),
      targetKb: targetKb,
    ));
  }

  /// Compresses [imagePath] to [targetKb] and saves the result.
  ///
  /// If [outPath] is provided the file is written there; otherwise a
  /// timestamped file is created in the application documents directory.
  ///
  /// Returns the path of the saved file.
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

/// Binary-search JPEG quality so the output is within 10 % of [params.targetKb].
/// Runs in a separate isolate via [compute].
Uint8List _compressIsolate(_CompressParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) return params.bytes;

  final targetBytes = params.targetKb * 1024;
  final tolerance = (targetBytes * 0.10).round(); // 10 %

  int lo = 10;
  int hi = 95;
  Uint8List best = Uint8List.fromList(img.encodeJpg(decoded, quality: hi));

  // If even max quality is below target, return max-quality result.
  if (best.length <= targetBytes) return best;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final candidate =
        Uint8List.fromList(img.encodeJpg(decoded, quality: mid));

    if ((candidate.length - targetBytes).abs() <= tolerance) {
      // Close enough – accept.
      return candidate;
    }

    if (candidate.length > targetBytes) {
      hi = mid - 1;
      best = candidate; // keep as fallback even if slightly over
    } else {
      lo = mid + 1;
      best = candidate;
    }
  }

  return best;
}
