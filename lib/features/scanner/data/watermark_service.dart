import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum WatermarkStyle {
  /// Repeated diagonal pattern across the entire page (best for preventing forgery/cloning)
  tiledDiagonal,

  /// Single large diagonal banner across the center
  diagonalBanner,

  /// Official rectangular security stamp with border and optional date
  officialStamp,
}

enum WatermarkColorTheme {
  securityRed(Color(0xFFDC2626), 'أحمر أمني'),
  securityBlue(Color(0xFF1D4ED8), 'أزرق بنكي'),
  securityGray(Color(0xFF4B5563), 'رمادي أمني'),
  securityGreen(Color(0xFF047857), 'أخضر رسمي'),
  darkCharcoal(Color(0xFF1F2937), 'كحلي داكن');

  const WatermarkColorTheme(this.color, this.labelAr);
  final Color color;
  final String labelAr;
}

class WatermarkConfig {
  const WatermarkConfig({
    required this.text,
    this.style = WatermarkStyle.tiledDiagonal,
    this.colorTheme = WatermarkColorTheme.securityRed,
    this.opacity = 0.28,
    this.includeDate = true,
    this.customDateText,
  });

  final String text;
  final WatermarkStyle style;
  final WatermarkColorTheme colorTheme;
  final double opacity;
  final bool includeDate;
  final String? customDateText;

  static const List<String> egyptianPresets = [
    'صورة طبق الأصل',
    'مقدمة إلى بنك مصر فقط',
    'مقدمة إلى البنك الأهلي المصري',
    'مقدمة لشركة الاتصالات فقط',
    'لا يعتد بها بدون الأصل',
    'لأغراض التوظيف فقط',
    'نسخة غير صالحة للتعامل المالي',
    'سري للغاية - خاص بالمعاملة',
  ];
}

class WatermarkService {
  /// Applies the specified watermark configuration to an image file,
  /// and returns the path to the newly saved protected image file.
  Future<String> applyWatermarkToFile({
    required String sourceImagePath,
    required WatermarkConfig config,
    String? outputDirectory,
  }) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final watermarkedBytes = await applyWatermarkToBytes(
      imageBytes: bytes,
      config: config,
    );

    final dir = outputDirectory != null
        ? Directory(outputDirectory)
        : await getApplicationDocumentsDirectory();
    final nameWithoutExt = p.basenameWithoutExtension(sourceImagePath);
    final outPath = p.join(
      dir.path,
      '${nameWithoutExt}_watermarked_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    final outFile = File(outPath);
    await outFile.writeAsBytes(watermarkedBytes);
    return outPath;
  }

  /// Applies the watermark configuration to raw image bytes, returning the
  /// watermarked JPEG image bytes.
  Future<Uint8List> applyWatermarkToBytes({
    required Uint8List imageBytes,
    required WatermarkConfig config,
  }) async {
    // 1. Decode original image into ui.Image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final baseImage = frame.image;

    final imgW = baseImage.width.toDouble();
    final imgH = baseImage.height.toDouble();

    // 2. Setup PictureRecorder and Canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imgW, imgH));

    // 3. Draw base image
    final basePaint = Paint();
    canvas.drawImage(baseImage, Offset.zero, basePaint);

    // 4. Draw Watermark according to selected style
    final effectiveColor =
        config.colorTheme.color.withValues(alpha: config.opacity);

    switch (config.style) {
      case WatermarkStyle.tiledDiagonal:
        _drawTiledDiagonal(
          canvas: canvas,
          width: imgW,
          height: imgH,
          text: config.text,
          color: effectiveColor,
          includeDate: config.includeDate,
          dateText: config.customDateText,
        );
        break;

      case WatermarkStyle.diagonalBanner:
        _drawDiagonalBanner(
          canvas: canvas,
          width: imgW,
          height: imgH,
          text: config.text,
          color: effectiveColor,
          includeDate: config.includeDate,
          dateText: config.customDateText,
        );
        break;

      case WatermarkStyle.officialStamp:
        _drawOfficialStamp(
          canvas: canvas,
          width: imgW,
          height: imgH,
          text: config.text,
          color: effectiveColor,
          includeDate: config.includeDate,
          dateText: config.customDateText,
        );
        break;
    }

    // 5. Convert to image and encode to JPEG bytes
    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(
      baseImage.width,
      baseImage.height,
    );
    final byteData = await renderedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    baseImage.dispose();
    renderedImage.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode watermarked image to PNG bytes');
    }

    return byteData.buffer.asUint8List();
  }

  // ─── Drawing Helpers ────────────────────────────────────────────────────────

  void _drawTiledDiagonal({
    required Canvas canvas,
    required double width,
    required double height,
    required String text,
    required Color color,
    required bool includeDate,
    String? dateText,
  }) {
    final fullText = includeDate
        ? '$text\n${dateText ?? _formattedToday()}'
        : text;

    final fontSize = math.max(16.0, width * 0.026);
    final textPainter = TextPainter(
      text: TextSpan(
        text: fullText,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
          height: 1.3,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: width * 0.45);

    final stepX = math.max(220.0, width * 0.40);
    final stepY = math.max(160.0, height * 0.22);
    final rotationAngle = -32 * (math.pi / 180.0);

    for (double y = 60.0; y < height + 100.0; y += stepY) {
      // Offset alternating rows for a natural watermark tile pattern
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 40.0 : (stepX * 0.5);

      for (double x = startX; x < width + 100.0; x += stepX) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(rotationAngle);
        textPainter.paint(
          canvas,
          Offset(-textPainter.width / 2, -textPainter.height / 2),
        );
        canvas.restore();
      }
    }
  }

  void _drawDiagonalBanner({
    required Canvas canvas,
    required double width,
    required double height,
    required String text,
    required Color color,
    required bool includeDate,
    String? dateText,
  }) {
    final fullText = includeDate
        ? '$text • ${dateText ?? _formattedToday()}'
        : text;

    final fontSize = math.max(24.0, width * 0.046);
    final textPainter = TextPainter(
      text: TextSpan(
        text: fullText,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          fontFamily: 'Cairo',
          letterSpacing: 1.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: width * 1.2);

    final centerX = width / 2;
    final centerY = height / 2;
    final rotationAngle = -35 * (math.pi / 180.0);

    // Draw banner outline background box
    final bannerPaint = Paint()
      ..color = color.withValues(alpha: color.a * 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, width * 0.005);

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(rotationAngle);

    final boxW = textPainter.width + 48.0;
    final boxH = textPainter.height + 24.0;
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: boxW, height: boxH),
      const Radius.circular(12),
    );

    canvas.drawRRect(boxRect, bannerPaint);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  void _drawOfficialStamp({
    required Canvas canvas,
    required double width,
    required double height,
    required String text,
    required Color color,
    required bool includeDate,
    String? dateText,
  }) {
    final stampWidth = math.max(260.0, width * 0.48);
    final stampHeight = stampWidth * 0.52;
    final fontSize = math.max(16.0, stampWidth * 0.08);

    final dateStr = dateText ?? _formattedToday();

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$text\n',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
              height: 1.2,
            ),
          ),
          if (includeDate)
            TextSpan(
              text: 'تاريخ: $dateStr\n',
              style: TextStyle(
                color: color,
                fontSize: fontSize * 0.72,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          TextSpan(
            text: '★ معتمد محلياً بدون خوادم ★',
            style: TextStyle(
              color: color.withValues(alpha: color.a * 0.85),
              fontSize: fontSize * 0.58,
              fontWeight: FontWeight.w600,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: stampWidth - 24.0);

    // Place stamp in bottom-left or bottom-center of the document
    final stampCenterX = width * 0.35;
    final stampCenterY = height * 0.78;
    final stampAngle = -12 * (math.pi / 180.0); // authentic angled hand-stamp look

    canvas.save();
    canvas.translate(stampCenterX, stampCenterY);
    canvas.rotate(stampAngle);

    final stampRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: stampWidth,
        height: stampHeight,
      ),
      const Radius.circular(8),
    );

    // Outer thick border
    final outerBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawRRect(stampRect, outerBorderPaint);

    // Inner thin border (double security frame)
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: stampWidth - 10,
        height: stampHeight - 10,
      ),
      const Radius.circular(5),
    );
    final innerBorderPaint = Paint()
      ..color = color.withValues(alpha: color.a * 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(innerRect, innerBorderPaint);

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  String _formattedToday() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
}
