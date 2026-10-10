import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/models/pending_upload.dart';
import 'document_search_service.dart';
import 'native_scanner_bridge.dart';

/// Supported OCR language modes selectable by user or auto-selected.
enum OcrLanguageMode {
  araAndEng('ara+eng', 'عربي + إنجليزي (تلقائي)', true),
  araOnly('ara', 'عربي فقط (دقة قصوى للعربية)', true),
  engOnly('eng', 'إنجليزي فقط (Latin)', false);

  const OcrLanguageMode(this.tessCode, this.label, this.includesArabic);
  final String tessCode;
  final String label;
  final bool includesArabic;

  String get labelAr => label;

  static const OcrLanguageMode arabicEnglish = OcrLanguageMode.araAndEng;
  static const OcrLanguageMode arabicOnly = OcrLanguageMode.araOnly;
  static const OcrLanguageMode englishOnly = OcrLanguageMode.engOnly;
}

/// Engine selection mode.
enum OcrEnginePreference {
  auto('اختيار ذكي تلقائي (Tesseract للعربية / ML Kit للاتينية)'),
  tesseract('Tesseract LSTM (عربي + إنجليزي فائق الدقة)'),
  mlKitLatin('Google ML Kit (لاتيني/إنجليزي فقط)');

  const OcrEnginePreference(this.label);
  final String label;
}

/// Cancellation token for long-running multi-page OCR operations.
class OcrCancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

typedef OcrCancellationToken = OcrCancelToken;
typedef OcrPageData = OcrPageResult;

/// Represents a single recognized line/block with normalized [0..1] and pixel coordinates.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    this.pixelLeft = 0,
    this.pixelTop = 0,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;
  final int pixelLeft;
  final int pixelTop;
  final int pixelWidth;
  final int pixelHeight;

  bool get isRtl => OcrService.containsArabic(text);

  double get normLeft => left;
  double get normTop => top;
  double get normWidth => (right - left).clamp(0.01, 1.0);
  double get normHeight => (bottom - top).clamp(0.01, 1.0);

  double get width => pixelWidth > 0 ? pixelWidth.toDouble() : normWidth * 1200;
  double get height =>
      pixelHeight > 0 ? pixelHeight.toDouble() : normHeight * 1600;

  Map<String, dynamic> toJson() => {
        'text': text,
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'confidence': confidence,
        'pixelLeft': pixelLeft,
        'pixelTop': pixelTop,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
      };

  factory OcrTextLine.fromJson(Map<String, dynamic> json) => OcrTextLine(
        text: json['text'] as String? ?? '',
        left: (json['left'] as num?)?.toDouble() ?? 0.0,
        top: (json['top'] as num?)?.toDouble() ?? 0.0,
        right: (json['right'] as num?)?.toDouble() ?? 1.0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0.1,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 85.0,
        pixelLeft: (json['pixelLeft'] as num?)?.toInt() ?? 0,
        pixelTop: (json['pixelTop'] as num?)?.toInt() ?? 0,
        pixelWidth: (json['pixelWidth'] as num?)?.toInt() ?? 0,
        pixelHeight: (json['pixelHeight'] as num?)?.toInt() ?? 0,
      );
}

/// OCR result for a single document page.
class OcrPageResult {
  const OcrPageResult({
    required this.pageIndex,
    required this.imagePath,
    required this.fullText,
    required this.lines,
    required this.imageWidth,
    required this.imageHeight,
    required this.engineUsed,
  });

  final int pageIndex;
  final String imagePath;
  final String fullText;
  final List<OcrTextLine> lines;
  final int imageWidth;
  final int imageHeight;
  final String engineUsed;

  double get averageConfidence {
    if (lines.isEmpty) return 0;
    final sum = lines.fold<double>(0.0, (acc, l) => acc + l.confidence);
    return sum / lines.length;
  }

  Map<String, dynamic> toJson() => {
        'pageIndex': pageIndex,
        'imagePath': imagePath,
        'fullText': fullText,
        'lines': lines.map((l) => l.toJson()).toList(),
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'engineUsed': engineUsed,
      };

  factory OcrPageResult.fromJson(Map<String, dynamic> json) => OcrPageResult(
        pageIndex: json['pageIndex'] as int? ?? 0,
        imagePath: json['imagePath'] as String? ?? '',
        fullText: json['fullText'] as String? ?? '',
        lines: (json['lines'] as List<dynamic>?)
                ?.map((e) => OcrTextLine.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        imageWidth: json['imageWidth'] as int? ?? 1200,
        imageHeight: json['imageHeight'] as int? ?? 1600,
        engineUsed: json['engineUsed'] as String? ?? 'tesseract',
      );
}

/// Complete OCR result across all pages of a document.
class OcrDocumentResult {
  const OcrDocumentResult({
    required this.documentId,
    required this.languageMode,
    required this.pages,
    required this.createdAt,
  });

  final String documentId;
  final OcrLanguageMode languageMode;
  final List<OcrPageResult> pages;
  final DateTime createdAt;

  String get combinedText =>
      pages.map((p) => p.fullText.trim()).where((s) => s.isNotEmpty).join('\n\n');

  String get fullText => combinedText;

  String? get suggestedTitle => OcrService.suggestSmartTitle(this);

  Map<String, dynamic> toJson() => {
        'documentId': documentId,
        'languageMode': languageMode.name,
        'pages': pages.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory OcrDocumentResult.fromJson(Map<String, dynamic> json) {
    final modeName = json['languageMode'] as String?;
    final mode = OcrLanguageMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => OcrLanguageMode.araAndEng,
    );
    return OcrDocumentResult(
      documentId: json['documentId'] as String? ?? '',
      languageMode: mode,
      pages: (json['pages'] as List<dynamic>?)
              ?.map((e) => OcrPageResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Abstract OCR engine contract (`OcrEngine`).
abstract class OcrEngine {
  String get name;
  bool get supportsArabic;

  Future<OcrPageResult> recognizePage({
    required String imagePath,
    required int pageIndex,
    required OcrLanguageMode languageMode,
    bool preprocess = true,
  });
}

/// Primary Offline OCR Engine: Tesseract 4/5 LSTM (`ara.traineddata` + `eng.traineddata` bundled in assets).
class TesseractOcrEngine implements OcrEngine {
  String? _cachedDataParentDir;

  @override
  String get name => 'Tesseract 4/5 LSTM (ara+eng Offline)';

  @override
  bool get supportsArabic => true;

  /// Copies `assets/tessdata/ara.traineddata` and `assets/tessdata/eng.traineddata`
  /// to `<appSupportDir>/tessdata/` on first run (100% offline).
  Future<String> ensureTessdataExtracted() async {
    if (_cachedDataParentDir != null) {
      return _cachedDataParentDir!;
    }
    final supportDir = await getApplicationSupportDirectory();
    final tessDir = Directory(p.join(supportDir.path, 'tessdata'));
    if (!await tessDir.exists()) {
      await tessDir.create(recursive: true);
    }

    for (final langFile in const ['ara.traineddata', 'eng.traineddata']) {
      final targetFile = File(p.join(tessDir.path, langFile));
      if (!await targetFile.exists() || await targetFile.length() < 100000) {
        final byteData = await rootBundle.load('assets/tessdata/$langFile');
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        await targetFile.writeAsBytes(bytes, flush: true);
        debugPrint(
          '[TesseractOcrEngine] Extracted offline model $langFile (${bytes.length} bytes) -> ${targetFile.path}',
        );
      }
    }

    _cachedDataParentDir = supportDir.path;
    return supportDir.path;
  }

  @override
  Future<OcrPageResult> recognizePage({
    required String imagePath,
    required int pageIndex,
    required OcrLanguageMode languageMode,
    bool preprocess = true,
  }) async {
    final dataParentPath = await ensureTessdataExtracted();
    final rawMap = await NativeScannerBridge.runTesseractOcr(
      imagePath: imagePath,
      dataPath: dataParentPath,
      language: languageMode.tessCode,
      preprocess: preprocess,
    );

    if (rawMap == null) {
      return OcrPageResult(
        pageIndex: pageIndex,
        imagePath: imagePath,
        fullText: '',
        lines: const [],
        imageWidth: 1200,
        imageHeight: 1600,
        engineUsed: name,
      );
    }

    final fullText = (rawMap['text'] as String? ?? '').trim();
    final imgW = (rawMap['width'] as num?)?.toInt() ?? 1200;
    final imgH = (rawMap['height'] as num?)?.toInt() ?? 1600;
    final rawBlocks = rawMap['blocks'] as List<dynamic>? ?? const [];

    final parsedLines = <OcrTextLine>[];
    for (final item in rawBlocks) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final text = (m['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        parsedLines.add(
          OcrTextLine(
            text: text,
            left: ((m['left'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
            top: ((m['top'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
            right: ((m['right'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
            bottom: ((m['bottom'] as num?)?.toDouble() ?? 0.1).clamp(0.0, 1.0),
            confidence: (m['confidence'] as num?)?.toDouble() ?? 85.0,
            pixelLeft: (m['pixelLeft'] as num?)?.toInt() ?? 0,
            pixelTop: (m['pixelTop'] as num?)?.toInt() ?? 0,
            pixelWidth: (m['pixelWidth'] as num?)?.toInt() ?? 0,
            pixelHeight: (m['pixelHeight'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    return OcrPageResult(
      pageIndex: pageIndex,
      imagePath: imagePath,
      fullText: fullText,
      lines: parsedLines,
      imageWidth: imgW,
      imageHeight: imgH,
      engineUsed: name,
    );
  }
}

/// Backup Latin-only OCR Engine using Google ML Kit (`google_mlkit_text_recognition`).
class MlKitLatinOcrEngine implements OcrEngine {
  @override
  String get name => 'Google ML Kit (Latin Backup)';

  @override
  bool get supportsArabic => false;

  @override
  Future<OcrPageResult> recognizePage({
    required String imagePath,
    required int pageIndex,
    required OcrLanguageMode languageMode,
    bool preprocess = true,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);

      const defaultW = 1600.0;
      const defaultH = 2200.0;
      final lines = <OcrTextLine>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;
          final rect = line.boundingBox;
          lines.add(
            OcrTextLine(
              text: text,
              left: (rect.left / defaultW).clamp(0.0, 1.0),
              top: (rect.top / defaultH).clamp(0.0, 1.0),
              right: (rect.right / defaultW).clamp(0.0, 1.0),
              bottom: (rect.bottom / defaultH).clamp(0.0, 1.0),
              confidence: ((line.confidence ?? 0.85) * 100.0).clamp(0.0, 100.0),
              pixelLeft: rect.left.round(),
              pixelTop: rect.top.round(),
              pixelWidth: rect.width.round(),
              pixelHeight: rect.height.round(),
            ),
          );
        }
      }

      return OcrPageResult(
        pageIndex: pageIndex,
        imagePath: imagePath,
        fullText: recognized.text.trim(),
        lines: lines,
        imageWidth: defaultW.round(),
        imageHeight: defaultH.round(),
        engineUsed: name,
      );
    } finally {
      await recognizer.close();
    }
  }
}

/// High-level OCR Service coordinating Tesseract (Arabic + English) & ML Kit (Latin backup),
/// OpenCV preprocessing, per-document JSON caching, and smart title suggestion.
class OcrService {
  OcrService({
    TesseractOcrEngine? tesseractEngine,
    MlKitLatinOcrEngine? mlKitLatinEngine,
  })  : _tesseract = tesseractEngine ?? TesseractOcrEngine(),
        _mlKitLatin = mlKitLatinEngine ?? MlKitLatinOcrEngine();

  final TesseractOcrEngine _tesseract;
  final MlKitLatinOcrEngine _mlKitLatin;

  static final RegExp _arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');

  static bool containsArabic(String text) => _arabicRegex.hasMatch(text);

  /// Selects the appropriate [OcrEngine] based on language and user preference.
  OcrEngine selectEngine({
    required OcrLanguageMode languageMode,
    OcrEnginePreference preference = OcrEnginePreference.auto,
  }) {
    if (preference == OcrEnginePreference.tesseract) {
      return _tesseract;
    }
    if (preference == OcrEnginePreference.mlKitLatin &&
        !languageMode.includesArabic) {
      return _mlKitLatin;
    }
    // Whenever Arabic is involved (ara or ara+eng), ALWAYS use Tesseract LSTM
    // because google_mlkit_text_recognition does not support Arabic script.
    if (languageMode.includesArabic) {
      return _tesseract;
    }
    return _tesseract;
  }

  Future<File> _cacheFileForDocument(
    String documentId,
    OcrLanguageMode languageMode,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(docsDir.path, 'ocr_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File(
      p.join(cacheDir.path, '${documentId}_${languageMode.name}.json'),
    );
  }

  /// Loads cached OCR result for [documentId] if available on disk.
  Future<OcrDocumentResult?> loadCachedResult(
    String documentId, {
    OcrLanguageMode languageMode = OcrLanguageMode.araAndEng,
  }) async {
    try {
      final file = await _cacheFileForDocument(documentId, languageMode);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return OcrDocumentResult.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs OCR across all pages of [document] (or [documentId] + [imagePaths]) with caching, progress callbacks, and cancellation.
  Future<OcrDocumentResult> recognizeDocument({
    PendingUpload? document,
    String? documentId,
    List<String>? imagePaths,
    OcrLanguageMode languageMode = OcrLanguageMode.araAndEng,
    OcrEnginePreference enginePreference = OcrEnginePreference.auto,
    bool preprocess = true,
    bool forceRefresh = false,
    OcrCancelToken? cancelToken,
    OcrCancelToken? cancellationToken,
    ValueChanged<String>? onProgress,
    void Function(String status, int currentPage, int totalPages)?
        onDetailedProgress,
  }) async {
    final effectiveDocId =
        document?.id ?? documentId ?? 'doc_${DateTime.now().millisecondsSinceEpoch}';
    final effectiveToken = cancelToken ?? cancellationToken;

    if (!forceRefresh && effectiveDocId != 'smart_title_preview') {
      final cached = await loadCachedResult(
        effectiveDocId,
        languageMode: languageMode,
      );
      if (cached != null && cached.pages.isNotEmpty) {
        final msg =
            'تم استرجاع النص المفهرس من الذاكرة المحلية (${cached.pages.length} صفحات)';
        onProgress?.call(msg);
        onDetailedProgress?.call(msg, cached.pages.length, cached.pages.length);
        return cached;
      }
    }

    final pagePaths = <String>[];
    if (imagePaths != null && imagePaths.isNotEmpty) {
      for (final path in imagePaths) {
        if (File(path).existsSync()) {
          pagePaths.add(path);
        }
      }
    } else if (document != null) {
      if (document.pages.isNotEmpty) {
        for (final p in document.pages) {
          if (File(p.imagePath).existsSync()) {
            pagePaths.add(p.imagePath);
          }
        }
      } else if (document.effectiveThumbnailPath != null &&
          File(document.effectiveThumbnailPath!).existsSync()) {
        pagePaths.add(document.effectiveThumbnailPath!);
      }
    }

    final engine = selectEngine(
      languageMode: languageMode,
      preference: enginePreference,
    );

    final pageResults = <OcrPageResult>[];
    final total = pagePaths.length.clamp(1, 9999);

    for (var i = 0; i < pagePaths.length; i++) {
      if (effectiveToken?.isCancelled == true) {
        throw StateError('تم إلغاء عملية التعرف الضوئي (OCR) من قِبل المستخدم.');
      }
      final msg =
          'جارٍ تحسين الصورة واستخراج النص (${languageMode.label}) — صفحة ${i + 1} من $total...';
      onProgress?.call(msg);
      onDetailedProgress?.call(msg, i + 1, total);

      var pageResult = await engine.recognizePage(
        imagePath: pagePaths[i],
        pageIndex: i,
        languageMode: languageMode,
        preprocess: preprocess,
      );

      // If English-only was selected and Tesseract returned empty, try ML Kit Latin fallback
      if (pageResult.fullText.isEmpty &&
          !languageMode.includesArabic &&
          engine is! MlKitLatinOcrEngine) {
        pageResult = await _mlKitLatin.recognizePage(
          imagePath: pagePaths[i],
          pageIndex: i,
          languageMode: languageMode,
          preprocess: preprocess,
        );
      }

      pageResults.add(pageResult);
    }

    final docResult = OcrDocumentResult(
      documentId: effectiveDocId,
      languageMode: languageMode,
      pages: pageResults,
      createdAt: DateTime.now(),
    );

    if (effectiveDocId != 'smart_title_preview') {
      try {
        final cacheFile =
            await _cacheFileForDocument(effectiveDocId, languageMode);
        await cacheFile.writeAsString(
          jsonEncode(docResult.toJson()),
          flush: true,
        );
        // Automatically populate local offline full-text search index
        await DocumentSearchService().indexDocumentOcr(
          documentId: effectiveDocId,
          title: document?.title ?? effectiveDocId,
          fullText: docResult.fullText,
          smartTitle: docResult.suggestedTitle,
        );
      } catch (e) {
        debugPrint('[OcrService] Warning: could not write OCR cache: $e');
      }
    }

    return docResult;
  }

  /// Suggests a smart document title from the first meaningful line of OCR text.
  static String? suggestSmartTitle(Object? resultOrText) {
    final candidateLines = <String>[];
    if (resultOrText is OcrDocumentResult) {
      for (final page in resultOrText.pages) {
        if (page.lines.isNotEmpty) {
          candidateLines.addAll(page.lines.map((l) => l.text));
        } else {
          candidateLines.addAll(page.fullText.split('\n'));
        }
      }
    } else if (resultOrText is String) {
      candidateLines.addAll(resultOrText.split('\n'));
    }

    for (final rawLine in candidateLines) {
      final cleaned = rawLine
          .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s\-_]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length >= 4 &&
          RegExp(r'[\u0600-\u06FFa-zA-Z]{2,}').hasMatch(cleaned)) {
        final words = cleaned.split(' ');
        final snippet = words.take(6).join(' ');
        return snippet.length > 42 ? snippet.substring(0, 42).trim() : snippet;
      }
    }
    return null;
  }

  /// Extracts plain text from an image file directly.
  Future<String> extractTextFromFile(
    String imagePath, {
    OcrLanguageMode languageMode = OcrLanguageMode.araAndEng,
  }) async {
    final engine = selectEngine(languageMode: languageMode);
    final result = await engine.recognizePage(
      imagePath: imagePath,
      pageIndex: 0,
      languageMode: languageMode,
    );
    return result.fullText;
  }
}
