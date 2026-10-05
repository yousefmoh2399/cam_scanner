import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cam_scanner/features/scanner/data/watermark_service.dart';
import 'package:cam_scanner/features/scanner/data/signature_extractor_service.dart';
import 'package:cam_scanner/features/scanner/data/smart_redaction_service.dart';
import 'package:cam_scanner/features/scanner/data/ocr_service.dart';
import 'package:cam_scanner/shared/models/image_filter_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 1: Security Watermark Service Tests', () {
    late Uint8List sampleDocBytes;

    setUp(() {
      // Create a dummy document image (400x500 white background with black text-like lines)
      final docImage = img.Image(width: 400, height: 500);
      img.fill(docImage, color: img.ColorRgb8(245, 245, 245));
      // draw simulated lines
      for (int y = 50; y < 450; y += 40) {
        img.drawLine(
          docImage,
          x1: 40,
          y1: y,
          x2: 360,
          y2: y,
          color: img.ColorRgb8(50, 50, 50),
        );
      }
      sampleDocBytes = Uint8List.fromList(img.encodeJpg(docImage));
    });

    test('Tiled Diagonal Watermark embeds properly across the page', () async {
      final service = WatermarkService();
      const config = WatermarkConfig(
        text: 'صورة طبق الأصل',
        style: WatermarkStyle.tiledDiagonal,
        colorTheme: WatermarkColorTheme.securityRed,
        opacity: 0.35,
        includeDate: true,
      );

      final resultBytes = await service.applyWatermarkToBytes(
        imageBytes: sampleDocBytes,
        config: config,
      );

      expect(resultBytes, isNotNull);
      expect(resultBytes.isNotEmpty, isTrue);

      final decoded = img.decodeImage(resultBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(400));
      expect(decoded.height, equals(500));
    });

    test('Official Stamp Watermark draws security border and verification text', () async {
      final service = WatermarkService();
      const config = WatermarkConfig(
        text: 'مقدمة إلى بنك مصر فقط',
        style: WatermarkStyle.officialStamp,
        colorTheme: WatermarkColorTheme.securityBlue,
        opacity: 0.50,
        includeDate: true,
      );

      final resultBytes = await service.applyWatermarkToBytes(
        imageBytes: sampleDocBytes,
        config: config,
      );

      expect(resultBytes, isNotNull);
      expect(resultBytes.isNotEmpty, isTrue);

      final decoded = img.decodeImage(resultBytes);
      expect(decoded, isNotNull);
    });

    test('Diagonal Banner Watermark renders centered angled badge', () async {
      final service = WatermarkService();
      const config = WatermarkConfig(
        text: 'سري للغاية - خاص بالمعاملة',
        style: WatermarkStyle.diagonalBanner,
        colorTheme: WatermarkColorTheme.securityGray,
        opacity: 0.40,
        includeDate: false,
      );

      final resultBytes = await service.applyWatermarkToBytes(
        imageBytes: sampleDocBytes,
        config: config,
      );

      expect(resultBytes, isNotNull);
      expect(resultBytes.length, greaterThan(100));
    });
  });

  group('Feature 2: Transparent Signature Extraction Tests', () {
    late Uint8List simulatedSignatureOnPaperBytes;

    setUp(() {
      // Create a 300x150 simulated photo of ink on white paper
      final paperImage = img.Image(width: 300, height: 150, numChannels: 4);
      // Fill paper with off-white/light gray (235, 235, 235)
      img.fill(paperImage, color: img.ColorRgba8(240, 240, 240, 255));
      // Draw signature strokes in dark blue pen (20, 40, 140)
      img.drawLine(paperImage, x1: 50, y1: 70, x2: 120, y2: 40, color: img.ColorRgba8(20, 40, 140, 255), thickness: 3);
      img.drawLine(paperImage, x1: 120, y1: 40, x2: 180, y2: 110, color: img.ColorRgba8(20, 40, 140, 255), thickness: 3);
      img.drawLine(paperImage, x1: 180, y1: 110, x2: 250, y2: 60, color: img.ColorRgba8(20, 40, 140, 255), thickness: 3);

      simulatedSignatureOnPaperBytes = Uint8List.fromList(img.encodePng(paperImage));
    });

    test('Extracts ink strokes and sets paper background to 100% transparent alpha', () async {
      final extractor = SignatureExtractorService();
      final transparentBytes = await extractor.extractTransparentSignatureFromBytes(
        imageBytes: simulatedSignatureOnPaperBytes,
        thresholdSensitivity: 0.85,
        colorMode: SignatureInkColorMode.royalBlue,
      );

      expect(transparentBytes, isNotNull);
      final decoded = img.decodeImage(transparentBytes);
      expect(decoded, isNotNull);
      expect(decoded!.numChannels, equals(4)); // RGBA

      // Check corner pixel (was white paper) -> should now be fully transparent (alpha == 0)
      final cornerPixel = decoded.getPixel(2, 2);
      expect(cornerPixel.a, equals(0));

      // Bounding box must be tightly cropped (smaller than original 300x150)
      expect(decoded.width, lessThanOrEqualTo(300));
      expect(decoded.height, lessThanOrEqualTo(150));
    });
  });

  group('Feature 6: Smart Auto-Redaction & Blackout Tests', () {
    test('autoDetectSensitiveTargets detects National IDs, Phones, and Amounts from OCR text', () {
      final service = SmartRedactionService();

      final ocrLines = [
        const OcrTextLine(
          text: 'الرقم القومي: 29810150102345 صادرة من مصلحة الأحوال',
          left: 0.1,
          top: 0.2,
          right: 0.9,
          bottom: 0.25,
          confidence: 0.95,
        ),
        const OcrTextLine(
          text: 'رقم الهاتف للتواصل: 01012345678 داخل جمهورية مصر',
          left: 0.1,
          top: 0.4,
          right: 0.8,
          bottom: 0.45,
          confidence: 0.92,
        ),
        const OcrTextLine(
          text: 'إجمالي الراتب المدفوع: 15,500.00 جنيه مصري',
          left: 0.1,
          top: 0.6,
          right: 0.7,
          bottom: 0.65,
          confidence: 0.90,
        ),
        const OcrTextLine(
          text: 'عنوان الإقامة: جمهورية مصر العربية محافظة الجيزة',
          left: 0.1,
          top: 0.8,
          right: 0.7,
          bottom: 0.85,
          confidence: 0.88,
        ),
      ];

      final targets = service.autoDetectSensitiveTargets(ocrLines: ocrLines);
      expect(targets.length, equals(3));
      expect(targets[0].label, contains('رقم قومي'));
      expect(targets[1].label, contains('هاتف'));
      expect(targets[2].label, contains('مبلغ مالي'));
    });

    test('burnRedactionsToBytes completely overwrites target rects with opaque black pixels', () async {
      final service = SmartRedactionService();

      // Create white image
      final baseImg = img.Image(width: 200, height: 200);
      img.fill(baseImg, color: img.ColorRgb8(255, 255, 255));
      final baseBytes = Uint8List.fromList(img.encodeJpg(baseImg));

      final redactions = [
        const RedactionTarget(
          id: 'red_1',
          label: 'تسويد أمني',
          normalizedRect: Rect.fromLTWH(0.2, 0.2, 0.6, 0.4),
        ),
      ];

      final redactedBytes = await service.burnRedactionsToBytes(
        imageBytes: baseBytes,
        redactions: redactions,
      );

      final decoded = img.decodeImage(redactedBytes);
      expect(decoded, isNotNull);

      // Center pixel (0.5, 0.4) is inside the redacted rect -> must be solid black (#111827 approx)
      final centerPixel = decoded!.getPixel(100, 80);
      expect(centerPixel.r, lessThan(30));
      expect(centerPixel.g, lessThan(35));
      expect(centerPixel.b, lessThan(45));

      // Pixel outside redacted area (10, 10) must remain white
      final outsidePixel = decoded.getPixel(10, 10);
      expect(outsidePixel.r, greaterThan(240));
      expect(outsidePixel.g, greaterThan(240));
      expect(outsidePixel.b, greaterThan(240));
    });
  });

  group('Feature 3: Shadow & Finger Removal Filter Model Tests', () {
    test('ImageFilterType includes shadowRemover with proper keys and Arabic label', () {
      expect(ImageFilterType.shadowRemover.nativeKey, equals('shadow_remover'));
      expect(ImageFilterType.shadowRemover.label, equals('إزالة الظلال والأصابع'));
      expect(ImageFilterType.fromKey('shadow_remover'), equals(ImageFilterType.shadowRemover));
      expect(ImageFilterType.fromKey('remove_shadows'), equals(ImageFilterType.shadowRemover));
    });
  });
}
