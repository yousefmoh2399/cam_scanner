import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StampColorFilter {
  original,
  officialRed,
  royalBlue,
  emeraldGreen,
  executiveBlack,
}

class DigitalStamp {
  const DigitalStamp({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.createdAt,
    this.colorFilter = StampColorFilter.original,
    this.opacity = 0.85,
    this.isBuiltIn = false,
  });

  final String id;
  final String title;
  final String imagePath;
  final DateTime createdAt;
  final StampColorFilter colorFilter;
  final double opacity;
  final bool isBuiltIn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'colorFilter': colorFilter.index,
        'opacity': opacity,
        'isBuiltIn': isBuiltIn,
      };

  factory DigitalStamp.fromJson(Map<String, dynamic> json) => DigitalStamp(
        id: json['id'] as String,
        title: json['title'] as String,
        imagePath: json['imagePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        colorFilter: StampColorFilter.values[(json['colorFilter'] as int?) ?? 0],
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.85,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      );
}

class StampStorageService {
  static const _metaFileName = 'digital_stamps_v1.json';

  Future<Directory> _getStampsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'digital_stamps'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<DigitalStamp>> loadAllStamps() async {
    try {
      final dir = await _getStampsDir();
      final metaFile = File(p.join(dir.path, _metaFileName));
      if (!await metaFile.exists()) {
        // Generate built-in template stamps
        final builtIns = await _generateBuiltInStamps(dir);
        await saveStamps(builtIns);
        return builtIns;
      }

      final jsonStr = await metaFile.readAsString();
      final list = (jsonDecode(jsonStr) as List<dynamic>)
          .map((e) => DigitalStamp.fromJson(e as Map<String, dynamic>))
          .where((s) => File(s.imagePath).existsSync())
          .toList();

      return list;
    } catch (e) {
      debugPrint('[StampStorage] Error loading stamps: $e');
      return [];
    }
  }

  Future<void> saveStamps(List<DigitalStamp> stamps) async {
    final dir = await _getStampsDir();
    final metaFile = File(p.join(dir.path, _metaFileName));
    final jsonStr = jsonEncode(stamps.map((s) => s.toJson()).toList());
    await metaFile.writeAsString(jsonStr, flush: true);
  }

  Future<DigitalStamp> createCustomStampFromBytes({
    required Uint8List rawImageBytes,
    required String title,
    double sensitivity = 0.82,
    StampColorFilter colorFilter = StampColorFilter.officialRed,
    double opacity = 0.85,
  }) async {
    final dir = await _getStampsDir();
    final id = 'stamp_${DateTime.now().millisecondsSinceEpoch}';
    final targetPath = p.join(dir.path, '$id.png');

    final transparentPngBytes = await compute(_extractStampIsolate, {
      'bytes': rawImageBytes,
      'sensitivity': sensitivity,
      'colorFilter': colorFilter.index,
      'opacity': opacity,
    });

    final f = File(targetPath);
    await f.writeAsBytes(transparentPngBytes, flush: true);

    final stamp = DigitalStamp(
      id: id,
      title: title,
      imagePath: targetPath,
      createdAt: DateTime.now(),
      colorFilter: colorFilter,
      opacity: opacity,
      isBuiltIn: false,
    );

    final existing = await loadAllStamps();
    existing.insert(0, stamp);
    await saveStamps(existing);

    return stamp;
  }

  Future<void> deleteStamp(String id) async {
    final existing = await loadAllStamps();
    final target = existing.where((s) => s.id == id).firstOrNull;
    if (target != null && !target.isBuiltIn) {
      try {
        final f = File(target.imagePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    existing.removeWhere((s) => s.id == id);
    await saveStamps(existing);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Built-in Official Stamp Generators
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<DigitalStamp>> _generateBuiltInStamps(Directory dir) async {
    final results = <DigitalStamp>[];

    // 1. معتمد / APPROVED
    final approvedPath = p.join(dir.path, 'builtin_approved.png');
    final approvedBytes = _renderTemplateStampPng(
      textAr: 'معـتـمـد',
      textEn: 'OFFICIAL APPROVAL',
      r: 218,
      g: 41,
      b: 28,
    );
    await File(approvedPath).writeAsBytes(approvedBytes, flush: true);
    results.add(
      DigitalStamp(
        id: 'builtin_approved',
        title: 'ختم معتمد رسمي',
        imagePath: approvedPath,
        createdAt: DateTime.now(),
        colorFilter: StampColorFilter.officialRed,
        opacity: 0.88,
        isBuiltIn: true,
      ),
    );

    // 2. سري للغاية / TOP SECRET
    final secretPath = p.join(dir.path, 'builtin_secret.png');
    final secretBytes = _renderTemplateStampPng(
      textAr: 'سري للغـايـة',
      textEn: 'STRICTLY CONFIDENTIAL',
      r: 180,
      g: 20,
      b: 20,
    );
    await File(secretPath).writeAsBytes(secretBytes, flush: true);
    results.add(
      DigitalStamp(
        id: 'builtin_secret',
        title: 'سري للغاية وخاص',
        imagePath: secretPath,
        createdAt: DateTime.now(),
        colorFilter: StampColorFilter.officialRed,
        opacity: 0.88,
        isBuiltIn: true,
      ),
    );

    // 3. طبق الأصل / CERTIFIED
    final copyPath = p.join(dir.path, 'builtin_certified.png');
    final copyBytes = _renderTemplateStampPng(
      textAr: 'طـبـق الأصـل',
      textEn: 'CERTIFIED TRUE COPY',
      r: 0,
      g: 85,
      b: 184,
    );
    await File(copyPath).writeAsBytes(copyBytes, flush: true);
    results.add(
      DigitalStamp(
        id: 'builtin_certified',
        title: 'صورة طبق الأصل',
        imagePath: copyPath,
        createdAt: DateTime.now(),
        colorFilter: StampColorFilter.royalBlue,
        opacity: 0.88,
        isBuiltIn: true,
      ),
    );

    // 4. مدفوع / PAID
    final paidPath = p.join(dir.path, 'builtin_paid.png');
    final paidBytes = _renderTemplateStampPng(
      textAr: 'مـدفـوع بـالـكـامـل',
      textEn: 'PAYMENT RECEIVED',
      r: 16,
      g: 140,
      b: 60,
    );
    await File(paidPath).writeAsBytes(paidBytes, flush: true);
    results.add(
      DigitalStamp(
        id: 'builtin_paid',
        title: 'مدفوع ومسدد',
        imagePath: paidPath,
        createdAt: DateTime.now(),
        colorFilter: StampColorFilter.emeraldGreen,
        opacity: 0.88,
        isBuiltIn: true,
      ),
    );

    return results;
  }

  Uint8List _renderTemplateStampPng({
    required String textAr,
    required String textEn,
    required int r,
    required int g,
    required int b,
  }) {
    const width = 480;
    const height = 240;
    final image = img.Image(width: width, height: height, numChannels: 4);

    // Draw double rounded border rectangle
    const borderWidth = 6;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final isOuterBorder = (x < borderWidth ||
            x >= width - borderWidth ||
            y < borderWidth ||
            y >= height - borderWidth);
        final isInnerBorder = ((x >= 14 && x < 18) ||
                (x >= width - 18 && x < width - 14) ||
                (y >= 14 && y < 18) ||
                (y >= height - 18 && y < height - 14)) &&
            (x >= 14 && x < width - 14 && y >= 14 && y < height - 14);

        if (isOuterBorder || isInnerBorder) {
          // Slight ink bleeding jitter for realism
          final jitter = ((x * 7 + y * 13) % 5);
          if (jitter != 0) {
            image.setPixelRgba(x, y, r, g, b, 230);
          }
        }
      }
    }

    // Render center text using crisp embedded bitmap font
    img.drawString(
      image,
      textEn,
      font: img.arial24,
      x: 60,
      y: 110,
      color: img.ColorRgba8(r, g, b, 240),
    );

    return Uint8List.fromList(img.encodePng(image));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inking & Transparency Extraction Isolate
  // ─────────────────────────────────────────────────────────────────────────

  static Uint8List _extractStampIsolate(Map<String, dynamic> params) {
    final rawBytes = params['bytes'] as Uint8List;
    final sensitivity = (params['sensitivity'] as num).toDouble();
    final filterIdx = params['colorFilter'] as int;
    final colorFilter = StampColorFilter.values[filterIdx];
    final opacity = (params['opacity'] as num).toDouble().clamp(0.1, 1.0);

    final source = img.decodeImage(rawBytes);
    if (source == null) return rawBytes;

    final w = source.width;
    final h = source.height;
    final output = img.Image(width: w, height: h, numChannels: 4);

    // Compute paper background luminance
    int sumLum = 0, count = 0;
    for (int y = 0; y < h; y += 4) {
      for (int x = 0; x < w; x += 4) {
        final p = source.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        if (lum > 175) {
          sumLum += lum;
          count++;
        }
      }
    }
    final bgLum = count > 0 ? (sumLum / count) : 235.0;
    final threshold = bgLum * sensitivity;

    int minX = w, maxX = 0, minY = h, maxY = 0;
    bool foundInk = false;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = source.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

        if (lum < threshold) {
          foundInk = true;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;

          // Alpha curve based on stroke density
          final strokeDensity = ((threshold - lum) / threshold).clamp(0.0, 1.0);
          final alpha = (strokeDensity * opacity * 255).round().clamp(0, 255);

          int outR = p.r.toInt();
          int outG = p.g.toInt();
          int outB = p.b.toInt();

          switch (colorFilter) {
            case StampColorFilter.officialRed:
              outR = 210;
              outG = 30;
              outB = 30;
              break;
            case StampColorFilter.royalBlue:
              outR = 10;
              outG = 75;
              outB = 180;
              break;
            case StampColorFilter.emeraldGreen:
              outR = 20;
              outG = 135;
              outB = 60;
              break;
            case StampColorFilter.executiveBlack:
              outR = 25;
              outG = 25;
              outB = 30;
              break;
            case StampColorFilter.original:
              break;
          }

          output.setPixelRgba(x, y, outR, outG, outB, alpha);
        } else {
          output.setPixelRgba(x, y, 0, 0, 0, 0); // 100% transparent
        }
      }
    }

    // Auto crop tightly to ink bounding box
    img.Image finalImage = output;
    if (foundInk && maxX > minX && maxY > minY) {
      const padding = 16;
      final cropX = math.max(0, minX - padding);
      final cropY = math.max(0, minY - padding);
      final cropW = math.min(w - cropX, (maxX - minX) + (padding * 2));
      final cropH = math.min(h - cropY, (maxY - minY) + (padding * 2));
      finalImage = img.copyCrop(output, x: cropX, y: cropY, width: cropW, height: cropH);
    }

    return Uint8List.fromList(img.encodePng(finalImage));
  }
}
