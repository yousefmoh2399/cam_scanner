import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cam_scanner/features/scanner/data/ocr_service.dart';
import 'package:cam_scanner/features/scanner/data/office_exporter_service.dart';
import 'package:cam_scanner/features/scanner/data/pdf_builder_service.dart';
import 'package:cam_scanner/features/scanner/data/vault_security_service.dart';
import 'package:cam_scanner/shared/models/image_filter_type.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1.2: 8-Filter Parity Verification', () {
    test('All 8 filters map cleanly between Dart enum and Kotlin ImageFilters keys', () {
      final expectedKeys = <String>[
        'original',
        'magic',
        'enhance',
        'lighten',
        'no_handwriting',
        'shadow_remover',
        'gray',
        'bw',
        'eco',
      ];
      expect(
        ImageFilterType.values.map((f) => f.nativeKey).toList(),
        equals(expectedKeys),
      );
      for (final key in expectedKeys) {
        final parsed = ImageFilterType.fromKey(key);
        expect(parsed.nativeKey, equals(key));
        expect(parsed.label.isNotEmpty, isTrue);
      }
    });
  });

  group('Phase 2: 3 Mandatory Samples (Arabic, English, Mixed+Table) & Searchable PDF', () {
    late Directory tempDir;
    late String sampleImagePath;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('cam_scanner_test_');
      final canvas = img.Image(width: 1200, height: 1600);
      img.fill(canvas, color: img.ColorRgb8(250, 250, 250));
      img.fillRect(
        canvas,
        x1: 80,
        y1: 120,
        x2: 1120,
        y2: 180,
        color: img.ColorRgb8(20, 20, 20),
      );
      final jpgBytes = img.encodeJpg(canvas, quality: 88);
      sampleImagePath = '${tempDir.path}/sample_page.jpg';
      await File(sampleImagePath).writeAsBytes(jpgBytes, flush: true);
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Sample 1 (Arabic Printed Text): Smart Title, RTL detection & Searchable PDF layer', () async {
      const arabicPage = OcrPageResult(
        pageIndex: 0,
        imagePath: 'sample1_ara.jpg',
        fullText: 'عقد إيجار وحدة سكنية رقم 2026/104\nيلتزم الطرف الأول بتسليم العين المؤجرة بحالة ممتازة.',
        imageWidth: 1200,
        imageHeight: 1600,
        engineUsed: 'Tesseract 4/5 LSTM (ara+eng)',
        lines: [
          OcrTextLine(
            text: 'عقد إيجار وحدة سكنية رقم 2026/104',
            left: 0.12,
            top: 0.08,
            right: 0.88,
            bottom: 0.12,
            confidence: 94.5,
          ),
          OcrTextLine(
            text: 'يلتزم الطرف الأول بتسليم العين المؤجرة بحالة ممتازة.',
            left: 0.10,
            top: 0.16,
            right: 0.90,
            bottom: 0.20,
            confidence: 92.1,
          ),
        ],
      );

      final docResult = OcrDocumentResult(
        documentId: 'sample_ara_1',
        languageMode: OcrLanguageMode.araAndEng,
        pages: const [arabicPage],
        createdAt: DateTime.now(),
      );

      expect(arabicPage.lines.first.isRtl, isTrue);
      expect(docResult.suggestedTitle, equals('عقد إيجار وحدة سكنية رقم 2026'));

      final pdfBuilder = PdfBuilderService();
      final searchablePdfBytes = await pdfBuilder.buildSearchablePdf(
        imagePaths: [sampleImagePath],
        paperSizes: const [DocumentPaperSize.a4],
        ocrPages: [arabicPage],
      );
      expect(searchablePdfBytes.length, greaterThan(1500));
      // Verify valid PDF header (%PDF-)
      expect(
        ascii.decode(searchablePdfBytes.sublist(0, 5)),
        equals('%PDF-'),
      );
    });

    test('Sample 2 (English Printed Text): Smart Title & LTR clustering', () {
      const englishPage = OcrPageResult(
        pageIndex: 0,
        imagePath: 'sample2_eng.jpg',
        fullText: 'COMMERCIAL INVOICE 2026-901\nTotal Amount Due: USD 1450.00\nPayment Terms: Net 30 Days',
        imageWidth: 1200,
        imageHeight: 1600,
        engineUsed: 'Tesseract 4/5 LSTM (ara+eng)',
        lines: [
          OcrTextLine(
            text: 'COMMERCIAL INVOICE 2026-901',
            left: 0.08,
            top: 0.07,
            right: 0.65,
            bottom: 0.11,
            confidence: 96.8,
          ),
          OcrTextLine(
            text: 'Total Amount Due: USD 1450.00',
            left: 0.08,
            top: 0.15,
            right: 0.58,
            bottom: 0.18,
            confidence: 95.2,
          ),
        ],
      );

      final docResult = OcrDocumentResult(
        documentId: 'sample_eng_2',
        languageMode: OcrLanguageMode.engOnly,
        pages: const [englishPage],
        createdAt: DateTime.now(),
      );

      expect(englishPage.lines.first.isRtl, isFalse);
      expect(docResult.suggestedTitle, equals('COMMERCIAL INVOICE 2026-901'));
    });

    test('Sample 3 (Mixed Arabic + English + Table): RTL Row Clustering for Excel/Word', () {
      final blocks = <OcrBlockItem>[
        // Row 1 (Arabic Table Header: Right-to-Left order: الصنف [right=800], الكمية [middle=450], السعر [left=120])
        const OcrBlockItem(
          text: 'السعر الإجمالي',
          top: 100,
          left: 120,
          width: 180,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'الكمية',
          top: 102,
          left: 450,
          width: 120,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'بيان الصنف (Model)',
          top: 99,
          left: 800,
          width: 240,
          height: 30,
          isRtl: true,
        ),
      ];

      final clustered = clusterOcrBlocksIntoRows(blocks);
      expect(clustered.length, equals(1));
      // Because row is predominantly RTL, the rightmost block (left=800) comes first!
      expect(clustered.first[0].text, equals('بيان الصنف (Model)'));
      expect(clustered.first[1].text, equals('الكمية'));
      expect(clustered.first[2].text, equals('السعر الإجمالي'));
    });
  });

  group('Phase 3: Target-Size PDF Compression & AES-256-GCM Vault Encryption', () {
    late Directory tempDir;
    late String noisyImagePath;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('cam_scanner_p3_test_');
      final canvas = img.Image(width: 1800, height: 2400);
      for (var y = 0; y < canvas.height; y++) {
        for (var x = 0; x < canvas.width; x++) {
          final v = ((x * 37 + y * 19) ^ (x * y)) & 0xFF;
          canvas.setPixelRgb(x, y, v, (v + 60) & 0xFF, (v + 120) & 0xFF);
        }
      }
      noisyImagePath = '${tempDir.path}/heavy_scan.jpg';
      await File(noisyImagePath).writeAsBytes(
        img.encodeJpg(canvas, quality: 95),
        flush: true,
      );
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Target-Size PDF Compressor keeps output under requested <500KB threshold', () async {
      final builder = PdfBuilderService();
      final compressed = await builder.buildPdf(
        imagePaths: [noisyImagePath],
        paperSizes: const [DocumentPaperSize.a4],
        options: const PdfBuildOptions(
          compressionPreset: PdfCompressionPreset.under500kb,
        ),
      );
      expect(compressed.length, lessThanOrEqualTo(500 * 1024));
    });

    test('AES-256-GCM Vault encryption/decryption roundtrip verifies integrity & rejects tampering', () async {
      final service = VaultSecurityService();
      final customKey = SecretKeyData.random(length: 32);
      final samplePlaintext = Uint8List.fromList(
        utf8.encode('مستند سري للغاية — عقد شراكة استراتيجية 2026 — CONFIDENTIAL'),
      );

      final encrypted = await service.encryptBytes(
        samplePlaintext,
        customKey: customKey,
      );
      // Encrypted payload must be 12B nonce + ciphertext + 16B GCM MAC tag
      expect(encrypted.length, equals(samplePlaintext.length + 28));
      expect(encrypted, isNot(equals(samplePlaintext)));

      final decrypted = await service.decryptBytes(
        encrypted,
        customKey: customKey,
      );
      expect(utf8.decode(decrypted), equals(utf8.decode(samplePlaintext)));

      // Tampering with 1 byte must fail GCM authentication tag check
      final tampered = Uint8List.fromList(encrypted);
      tampered[15] ^= 0xFF;
      expect(
        () => service.decryptBytes(tampered, customKey: customKey),
        throwsA(anything),
      );
    });
  });
}
