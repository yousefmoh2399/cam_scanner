import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum SmartIdCardType {
  nationalId('بطاقة هوية وطنية', 'National ID', 0xFF007AFF),
  drivingLicense('رخصة قيادة', 'Driver License', 0xFF10B981),
  bankCard('بطاقة بنكية / ائتمان', 'Bank / Credit Card', 0xFF6366F1),
  workBadge('كارنيه عمل / نقابة', 'Work / Syndicate Badge', 0xFFF59E0B),
  healthInsurance('تأمين صحي وطبي', 'Health Insurance', 0xFF0D9488),
  transitClub('اشتراك نادي / مواصلات', 'Club / Transit Pass', 0xFFEC4899),
  other('بطاقة أخرى', 'Other Card', 0xFF64748B);

  const SmartIdCardType(this.arabicLabel, this.englishLabel, this.colorValue);
  final String arabicLabel;
  final String englishLabel;
  final int colorValue;
}

class SmartIdCard {
  const SmartIdCard({
    required this.id,
    required this.title,
    required this.cardType,
    required this.frontImagePath,
    this.backImagePath,
    this.holderName,
    this.cardNumber,
    this.expiryDate,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final SmartIdCardType cardType;
  final String frontImagePath;
  final String? backImagePath;
  final String? holderName;
  final String? cardNumber;
  final String? expiryDate;
  final String? notes;
  final DateTime createdAt;

  bool get hasBack => backImagePath != null && File(backImagePath!).existsSync();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cardType': cardType.name,
        'frontImagePath': frontImagePath,
        'backImagePath': backImagePath,
        'holderName': holderName,
        'cardNumber': cardNumber,
        'expiryDate': expiryDate,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SmartIdCard.fromJson(Map<String, dynamic> json) {
    return SmartIdCard(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'بطاقة',
      cardType: SmartIdCardType.values.firstWhere(
        (e) => e.name == json['cardType'],
        orElse: () => SmartIdCardType.other,
      ),
      frontImagePath: json['frontImagePath'] as String,
      backImagePath: json['backImagePath'] as String?,
      holderName: json['holderName'] as String?,
      cardNumber: json['cardNumber'] as String?,
      expiryDate: json['expiryDate'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SmartIdWalletService {
  SmartIdWalletService._();
  static final SmartIdWalletService instance = SmartIdWalletService._();

  static const String _dbFileName = 'smart_id_wallet.json';

  /// Standard CR-80 physical dimensions in millimeters
  static const double cr80WidthMm = 85.60;
  static const double cr80HeightMm = 53.98;

  Future<Directory> _getWalletDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'scans', 'smart_id_wallet'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _getDbFile() async {
    final dir = await _getWalletDirectory();
    return File(p.join(dir.path, _dbFileName));
  }

  Future<List<SmartIdCard>> loadCards() async {
    try {
      final dbFile = await _getDbFile();
      if (!await dbFile.exists()) return [];

      final content = await dbFile.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      final cards = list
          .map((e) => SmartIdCard.fromJson(e as Map<String, dynamic>))
          .where((c) => File(c.frontImagePath).existsSync())
          .toList();

      cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(cards);
    } catch (e) {
      debugPrint('[SmartIdWalletService] Error loading cards: $e');
      return [];
    }
  }

  Future<void> _saveCards(List<SmartIdCard> cards) async {
    try {
      final dbFile = await _getDbFile();
      final jsonStr = jsonEncode(cards.map((e) => e.toJson()).toList());
      await dbFile.writeAsString(jsonStr, flush: true);
    } catch (e) {
      debugPrint('[SmartIdWalletService] Error saving cards: $e');
    }
  }

  Future<SmartIdCard> addCard({
    required String title,
    required SmartIdCardType cardType,
    required String frontSourcePath,
    String? backSourcePath,
    String? holderName,
    String? cardNumber,
    String? expiryDate,
    String? notes,
  }) async {
    final dir = await _getWalletDirectory();
    final id = 'card_${DateTime.now().millisecondsSinceEpoch}';

    // Copy front image
    final frontExt = p.extension(frontSourcePath);
    final frontDest = p.join(dir.path, '${id}_front$frontExt');
    await File(frontSourcePath).copy(frontDest);

    // Copy back image if present
    String? backDest;
    if (backSourcePath != null && File(backSourcePath).existsSync()) {
      final backExt = p.extension(backSourcePath);
      backDest = p.join(dir.path, '${id}_back$backExt');
      await File(backSourcePath).copy(backDest);
    }

    final newCard = SmartIdCard(
      id: id,
      title: title.trim().isEmpty ? cardType.arabicLabel : title.trim(),
      cardType: cardType,
      frontImagePath: frontDest,
      backImagePath: backDest,
      holderName: holderName?.trim().isEmpty == true ? null : holderName?.trim(),
      cardNumber: cardNumber?.trim().isEmpty == true ? null : cardNumber?.trim(),
      expiryDate: expiryDate?.trim().isEmpty == true ? null : expiryDate?.trim(),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      createdAt: DateTime.now(),
    );

    final current = await loadCards();
    final updated = [newCard, ...current];
    await _saveCards(updated);
    return newCard;
  }

  Future<void> deleteCard(String id) async {
    final current = await loadCards();
    final target = current.where((c) => c.id == id).firstOrNull;
    if (target != null) {
      try {
        final fFront = File(target.frontImagePath);
        if (await fFront.exists()) await fFront.delete();
        if (target.backImagePath != null) {
          final fBack = File(target.backImagePath!);
          if (await fBack.exists()) await fBack.delete();
        }
      } catch (_) {}
    }

    final updated = current.where((c) => c.id != id).toList();
    await _saveCards(updated);
  }

  /// Builds a 1:1 true-size PDF strictly sized to CR-80 standard ($85.6 \times 53.98$ mm).
  /// Perfect for direct printing on PVC Card Printers (Fargo, Zebra, Evolis, Badgy).
  Future<Uint8List> buildPvcCardPdf(SmartIdCard card) async {
    final doc = pw.Document();

    final cardFormat = const PdfPageFormat(
      cr80WidthMm * PdfPageFormat.mm,
      cr80HeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );

    // Front Side
    final frontBytes = await File(card.frontImagePath).readAsBytes();
    final frontImage = pw.MemoryImage(frontBytes);

    doc.addPage(
      pw.Page(
        pageFormat: cardFormat,
        build: (pw.Context ctx) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(frontImage, fit: pw.BoxFit.cover),
          );
        },
      ),
    );

    // Back Side (if available)
    if (card.hasBack) {
      final backBytes = await File(card.backImagePath!).readAsBytes();
      final backImage = pw.MemoryImage(backBytes);

      doc.addPage(
        pw.Page(
          pageFormat: cardFormat,
          build: (pw.Context ctx) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(backImage, fit: pw.BoxFit.cover),
            );
          },
        ),
      );
    }

    return doc.save();
  }

  /// Builds an A4 PDF sheet containing both sides of the card at exact 1:1 scale (85.6mm x 53.98mm)
  /// with precision printer crop marks (cutting guidelines) and a 1cm scale calibration bar.
  Future<Uint8List> buildA4PrintSheetPdf(SmartIdCard card) async {
    final doc = pw.Document();

    final frontBytes = await File(card.frontImagePath).readAsBytes();
    final frontImage = pw.MemoryImage(frontBytes);

    pw.MemoryImage? backImage;
    if (card.hasBack) {
      final backBytes = await File(card.backImagePath!).readAsBytes();
      backImage = pw.MemoryImage(backBytes);
    }

    final cardWidthPt = cr80WidthMm * PdfPageFormat.mm;
    final cardHeightPt = cr80HeightMm * PdfPageFormat.mm;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header & instructions
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 12),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'طباعة بطاقة بلاستيكية قياسية (Standard CR-80 PVC Sheet)',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'المقاس الفعلي الحقيقي 100%: 85.60 mm x 53.98 mm (بدون تصغير أو تكبير)',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    // Calibration ruler: exactly 50mm
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.black, width: 0.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            width: 50 * PdfPageFormat.mm,
                            height: 4,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'مسطرة معايرة: 50 ملم (5 سم)',
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 40),

              // Cards Center Layout (Side-by-side or stacked with crop marks)
              pw.Wrap(
                spacing: 40,
                runSpacing: 40,
                alignment: pw.WrapAlignment.center,
                children: [
                  _buildCardWithCropMarks(
                    title: 'الوجه الأمامي (Front)',
                    image: frontImage,
                    width: cardWidthPt,
                    height: cardHeightPt,
                  ),
                  if (backImage != null)
                    _buildCardWithCropMarks(
                      title: 'الوجه الخلفي (Back)',
                      image: backImage,
                      width: cardWidthPt,
                      height: cardHeightPt,
                    ),
                ],
              ),

              pw.Spacer(),

              // Cutting guide note
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      '✂️ إرشادات القص: اتبع علامات القص الزاوية عند الأطراف. للحصول على أفضل نتيجة، اطبع على ورق مقوى 250-300 جم أو شرائح PVC مع ضبط حجم الطباعة في إعدادات الطابعة على "حجم فعلي 100%" (Actual Size / Do Not Scale).',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _buildCardWithCropMarks({
    required String title,
    required pw.MemoryImage image,
    required double width,
    required double height,
  }) {
    const markLength = 12.0;

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Stack(
          children: [
            // Precision corner crop marks
            pw.Container(
              width: width + 24,
              height: height + 24,
              child: pw.CustomPaint(
                painter: (PdfGraphics canvas, PdfPoint size) {
                  canvas.setStrokeColor(PdfColors.black);
                  canvas.setLineWidth(0.6);

                  // Top-Left marks
                  canvas.drawLine(12, size.y - 12, 12 - markLength, size.y - 12);
                  canvas.drawLine(12, size.y - 12, 12, size.y - 12 + markLength);

                  // Top-Right marks
                  canvas.drawLine(size.x - 12, size.y - 12, size.x - 12 + markLength, size.y - 12);
                  canvas.drawLine(size.x - 12, size.y - 12, size.x - 12, size.y - 12 + markLength);

                  // Bottom-Left marks
                  canvas.drawLine(12, 12, 12 - markLength, 12);
                  canvas.drawLine(12, 12, 12, 12 - markLength);

                  // Bottom-Right marks
                  canvas.drawLine(size.x - 12, 12, size.x - 12 + markLength, 12);
                  canvas.drawLine(size.x - 12, 12, size.x - 12, 12 - markLength);
                },
              ),
            ),

            // Exact Size Card
            pw.Positioned(
              left: 12,
              top: 12,
              child: pw.Container(
                width: width,
                height: height,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 9,
                  verticalRadius: 9,
                  child: pw.Image(image, fit: pw.BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
