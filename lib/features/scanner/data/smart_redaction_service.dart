import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ocr_service.dart';

class RedactionTarget {
  const RedactionTarget({
    required this.id,
    required this.label,
    required this.normalizedRect, // 0.0 to 1.0 coords (left, top, right, bottom)
    this.isAutoDetected = false,
  });

  final String id;
  final String label;
  final Rect normalizedRect;
  final bool isAutoDetected;
}

class SmartRedactionService {
  /// Burns redaction rectangles permanently into the image pixels,
  /// guaranteeing zero pixel leakage or data recovery.
  Future<String> burnRedactionsToFile({
    required String sourceImagePath,
    required List<RedactionTarget> redactions,
    String? outputDirectory,
  }) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final redactedBytes = await burnRedactionsToBytes(
      imageBytes: bytes,
      redactions: redactions,
    );

    final dir = outputDirectory != null
        ? Directory(outputDirectory)
        : await getApplicationDocumentsDirectory();
    final nameWithoutExt = p.basenameWithoutExtension(sourceImagePath);
    final outPath = p.join(
      dir.path,
      '${nameWithoutExt}_redacted_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    final outFile = File(outPath);
    await outFile.writeAsBytes(redactedBytes);
    return outPath;
  }

  /// In-memory pixel burnout using compute isolate for zero UI stutter
  Future<Uint8List> burnRedactionsToBytes({
    required Uint8List imageBytes,
    required List<RedactionTarget> redactions,
  }) async {
    if (redactions.isEmpty) return imageBytes;

    final rectList = redactions.map((r) => [
      r.normalizedRect.left,
      r.normalizedRect.top,
      r.normalizedRect.width,
      r.normalizedRect.height,
    ]).toList();

    return compute(_burnIsolate, {
      'bytes': imageBytes,
      'rects': rectList,
    });
  }

  static Uint8List _burnIsolate(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'] as Uint8List;
    final List<List<double>> rectList = (params['rects'] as List)
        .map((e) => (e as List).map((n) => (n as num).toDouble()).toList())
        .toList();

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw StateError('Could not decode image for redaction');
    }

    final imgW = decoded.width;
    final imgH = decoded.height;

    // Solid blackout color (#111827 deep charcoal black)
    const blackR = 17;
    const blackG = 24;
    const blackB = 39;

    for (final r in rectList) {
      final left = (r[0] * imgW).clamp(0, imgW - 1).round();
      final top = (r[1] * imgH).clamp(0, imgH - 1).round();
      final w = (r[2] * imgW).clamp(1, imgW - left).round();
      final h = (r[3] * imgH).clamp(1, imgH - top).round();

      img.fillRect(
        decoded,
        x1: left,
        y1: top,
        x2: left + w,
        y2: top + h,
        color: img.ColorRgb8(blackR, blackG, blackB),
      );
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  /// Automatically generates redaction boxes for sensitive data (National ID, Phone numbers, Amounts)
  /// using the OCR page text lines.
  List<RedactionTarget> autoDetectSensitiveTargets({
    required List<OcrTextLine> ocrLines,
    bool redactNationalId = true,
    bool redactPhones = true,
    bool redactAmounts = true,
  }) {
    final targets = <RedactionTarget>[];

    for (int i = 0; i < ocrLines.length; i++) {
      final line = ocrLines[i];
      final lineText = line.text;

      // Check National ID
      if (redactNationalId) {
        final nidMatches = RegExp(r'\b[23]\d{13}\b').allMatches(lineText);
        if (nidMatches.isNotEmpty) {
          targets.add(RedactionTarget(
            id: 'nid_$i',
            label: 'رقم قومي مصري (14 رقم)',
            normalizedRect: Rect.fromLTWH(
              line.normLeft,
              line.normTop,
              line.normWidth,
              line.normHeight,
            ),
            isAutoDetected: true,
          ));
          continue;
        }
      }

      // Check Egyptian phone numbers
      if (redactPhones) {
        final phoneMatches = RegExp(r'\b(01[0125])\d{8}\b').allMatches(lineText);
        if (phoneMatches.isNotEmpty) {
          targets.add(RedactionTarget(
            id: 'phone_$i',
            label: 'رقم هاتف محمول',
            normalizedRect: Rect.fromLTWH(
              line.normLeft,
              line.normTop,
              line.normWidth,
              line.normHeight,
            ),
            isAutoDetected: true,
          ));
          continue;
        }
      }

      // Check monetary amounts
      if (redactAmounts) {
        final amountMatches = RegExp(
          r'\b\d{1,3}(?:[,.]\d{3})*(?:\.\d{2})?\s*(?:جنيه|ج\.م|EGP|USD|\$|€)',
        ).allMatches(lineText);
        if (amountMatches.isNotEmpty) {
          targets.add(RedactionTarget(
            id: 'amount_$i',
            label: 'مبلغ مالي',
            normalizedRect: Rect.fromLTWH(
              line.normLeft,
              line.normTop,
              line.normWidth,
              line.normHeight,
            ),
            isAutoDetected: true,
          ));
          continue;
        }
      }
    }

    return targets;
  }
}
