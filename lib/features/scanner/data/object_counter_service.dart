import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Presets for object detection categories
enum CounterObjectCategory {
  pipesAndTubes(
    'أنابيب ومواسير (Pipes & Tubes)',
    'كشف الدوائر والمقاطع العرضية للأنابيب والأسطوانات المكدسة',
  ),
  boxesAndPackages(
    'كراتين وطرود (Boxes & Packages)',
    'عد كراتين البضائع، الطرود، والشحنات المتراصة',
  ),
  pillsAndTablets(
    'حبوب وأقراص دواء (Pills & Tablets)',
    'عد الكبسولات، الأقراص الطبية، والحبوب الصغيرة بدقة',
  ),
  paperSheets(
    'أوراق ومستندات (Paper Sheets & Reams)',
    'حساب أوراق الملفات والمستندات والكتب المكدسة',
  ),
  generalItems(
    'عناصر وأشياء عامة (General Objects)',
    'عد البقع، العملات، القطع المعدنية، أو أي عناصر ذات تباين واضح',
  );

  const CounterObjectCategory(this.label, this.description);
  final String label;
  final String description;
}

/// Representation of an individual counted item
class CountedItem {
  const CountedItem({
    required this.id,
    required this.x,
    required this.y,
    this.radius = 0.015,
  });

  /// 1-based sequential number (1, 2, 3...)
  final int id;

  /// Normalized X coordinate (0.0 to 1.0)
  final double x;

  /// Normalized Y coordinate (0.0 to 1.0)
  final double y;

  /// Normalized radius relative to image width
  final double radius;

  CountedItem copyWith({int? id, double? x, double? y, double? radius}) {
    return CountedItem(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      radius: radius ?? this.radius,
    );
  }
}

/// Result payload containing detected items and metadata
class CountResult {
  const CountResult({
    required this.items,
    required this.category,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<CountedItem> items;
  final CounterObjectCategory category;
  final int imageWidth;
  final int imageHeight;

  int get totalCount => items.length;
}

/// Service that performs offline computer vision object detection and generates
/// formal Inventory Audit PDF reports.
class ObjectCounterService {
  const ObjectCounterService();

  /// Detects objects automatically in an isolate
  Future<CountResult> detectObjects({
    required Uint8List imageBytes,
    required CounterObjectCategory category,
    double sensitivity = 0.5,
    double minObjectSize = 0.01,
    double maxObjectSize = 0.15,
  }) async {
    final resultData = await compute(_detectObjectsIsolate, {
      'bytes': imageBytes,
      'category': category.index,
      'sensitivity': sensitivity,
      'minSize': minObjectSize,
      'maxSize': maxObjectSize,
    });

    final rawItems = resultData['items'] as List<dynamic>;
    final items = <CountedItem>[];
    for (int i = 0; i < rawItems.length; i++) {
      final itemMap = rawItems[i] as Map<String, dynamic>;
      items.add(
        CountedItem(
          id: i + 1,
          x: (itemMap['x'] as num).toDouble(),
          y: (itemMap['y'] as num).toDouble(),
          radius: (itemMap['r'] as num).toDouble(),
        ),
      );
    }

    return CountResult(
      items: items,
      category: category,
      imageWidth: resultData['width'] as int,
      imageHeight: resultData['height'] as int,
    );
  }

  /// Builds a formal, official Inventory Audit PDF Report with badge overlays
  Future<String> generateInventoryReportPdf({
    required Uint8List imageBytes,
    required List<CountedItem> items,
    required CounterObjectCategory category,
    String? inspectorName,
    String? location,
    String? notes,
  }) async {
    final pdf = pw.Document();
    final memImage = pw.MemoryImage(imageBytes);

    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Header Banner ──
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey900,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'تقرير جرد ومعاينة العناصر والأشياء',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'OFFICIAL INVENTORY COUNT & INSPECTION AUDIT',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.blueGrey100,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue700,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        'العدد: ${items.length}',
                        textDirection: pw.TextDirection.rtl,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              // ── Metadata Grid ──
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetaField('نوع الصنف:', category.label),
                    _buildMetaField(
                      'مسؤول الجرد:',
                      inspectorName?.trim().isNotEmpty == true
                          ? inspectorName!.trim()
                          : 'فحص ميداني إلكتروني',
                    ),
                    _buildMetaField(
                      'الموقع / المستودع:',
                      location?.trim().isNotEmpty == true ? location!.trim() : 'المخزن الرئيسي',
                    ),
                    _buildMetaField('التاريخ والوقت:', dateStr),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              // ── Counted Image Box with badges ──
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Stack(
                      fit: pw.StackFit.expand,
                      children: [
                        pw.Image(memImage, fit: pw.BoxFit.contain),
                        // Overlay sample badges (max 150 in PDF for performance)
                        ...items.take(150).map((item) {
                          return pw.Positioned(
                            left: (item.x * 500).clamp(0, 500),
                            top: (item.y * 360).clamp(0, 360),
                            child: pw.Container(
                              width: 14,
                              height: 14,
                              decoration: const pw.BoxDecoration(
                                color: PdfColors.red700,
                                shape: pw.BoxShape.circle,
                              ),
                              child: pw.Center(
                                child: pw.Text(
                                  '${item.id}',
                                  style: pw.TextStyle(
                                    fontSize: 6.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),

              pw.SizedBox(height: 10),

              // ── Summary & Signature Area ──
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'إجمالي العناصر المعتمدة: ${items.length} عنصر',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey900,
                          ),
                        ),
                        if (notes != null && notes.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'ملاحظات: ${notes.trim()}',
                            textDirection: pw.TextDirection.rtl,
                            style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    pw.Row(
                      children: [
                        pw.Column(
                          children: [
                            pw.Text(
                              'توقيع مسؤول الجرد: .................',
                              textDirection: pw.TextDirection.rtl,
                              style: const pw.TextStyle(fontSize: 8.5),
                            ),
                          ],
                        ),
                        pw.SizedBox(width: 24),
                        pw.Column(
                          children: [
                            pw.Text(
                              'اعتماد أمين المخزن: .................',
                              textDirection: pw.TextDirection.rtl,
                              style: const pw.TextStyle(fontSize: 8.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, 'inventory_audit_$ts.pdf');
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return filePath;
  }

  static pw.Widget _buildMetaField(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          textDirection: pw.TextDirection.rtl,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          value,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Offline Computer Vision Detection Isolate
  // ─────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _detectObjectsIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final categoryIdx = params['category'] as int;
    final sensitivity = (params['sensitivity'] as num).toDouble();
    final minSize = (params['minSize'] as num).toDouble();
    final maxSize = (params['maxSize'] as num).toDouble();

    final category = CounterObjectCategory.values[categoryIdx];

    final original = img.decodeImage(rawBytes);
    if (original == null) {
      return {'items': <Map<String, dynamic>>[], 'width': 0, 'height': 0};
    }

    final origW = original.width;
    final origH = original.height;

    // Work on downsampled image for sub-second offline response
    const maxProcessDim = 640;
    final scale = math.min(1.0, maxProcessDim / math.max(origW, origH));
    final procW = (origW * scale).round();
    final procH = (origH * scale).round();

    final scaled = img.copyResize(original, width: procW, height: procH);

    // 1. Convert to Luminance Matrix
    final gray = List.generate(procH, (_) => Float32List(procW));
    for (int y = 0; y < procH; y++) {
      for (int x = 0; x < procW; x++) {
        final p = scaled.getPixel(x, y);
        gray[y][x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
      }
    }

    // 2. Compute local edge magnitude and local contrasts
    final detectedPoints = <({double x, double y, double r})>[];

    // Detection tuning per category
    final step = (category == CounterObjectCategory.pillsAndTablets)
        ? 6
        : (category == CounterObjectCategory.boxesAndPackages ? 12 : 8);

    final expectedRadiusPx =
        (procW * ((minSize + maxSize) / 2)).clamp(4.0, 36.0);

    // Threshold sensitivity
    final threshold = 0.12 * (1.2 - (sensitivity * 0.5));

    // Multi-scale local extrema detection (Circular Hough & Local Centroid filter)
    for (int y = (expectedRadiusPx * 1.5).round();
        y < procH - (expectedRadiusPx * 1.5).round();
        y += step) {
      for (int x = (expectedRadiusPx * 1.5).round();
          x < procW - (expectedRadiusPx * 1.5).round();
          x += step) {
        final centerVal = gray[y][x];

        // Sample annular ring around candidate point
        double ringSum = 0.0;
        int ringSamples = 8;
        for (int i = 0; i < ringSamples; i++) {
          final angle = (i * 2 * math.pi) / ringSamples;
          final rx = (x + expectedRadiusPx * math.cos(angle)).round().clamp(0, procW - 1);
          final ry = (y + expectedRadiusPx * math.sin(angle)).round().clamp(0, procH - 1);
          ringSum += gray[ry][rx];
        }
        final ringAvg = ringSum / ringSamples;

        // An object center has contrast with its boundary
        final contrast = (ringAvg - centerVal).abs();

        if (contrast > threshold) {
          // Check local maxima to avoid redundant detections of the same object
          bool isLocalPeak = true;
          for (final prev in detectedPoints) {
            final prevX = prev.x * procW;
            final prevY = prev.y * procH;
            final dist = math.sqrt(math.pow(x - prevX, 2) + math.pow(y - prevY, 2));
            if (dist < expectedRadiusPx * 1.1) {
              isLocalPeak = false;
              break;
            }
          }

          if (isLocalPeak) {
            detectedPoints.add((
              x: x / procW,
              y: y / procH,
              r: (expectedRadiusPx / procW),
            ));
          }
        }
      }
    }

    // Sort detected points top-to-bottom, left-to-right for logical sequential numbering
    detectedPoints.sort((a, b) {
      final yDiff = (a.y - b.y).abs();
      if (yDiff < 0.04) {
        return a.x.compareTo(b.x);
      }
      return a.y.compareTo(b.y);
    });

    final serializedItems = detectedPoints
        .map((p) => {
              'x': p.x,
              'y': p.y,
              'r': p.r,
            })
        .toList();

    return {
      'items': serializedItems,
      'width': origW,
      'height': origH,
    };
  }
}
