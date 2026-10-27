import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_service.dart';
import 'office_exporter_service.dart';

/// Represents a reconstructed table extracted from a physical paper document.
@immutable
class ExtractedTableResult {
  const ExtractedTableResult({
    required this.title,
    required this.headers,
    required this.rows,
    required this.isRtl,
    this.sourceImagePath,
    this.confidence = 100,
  });

  /// The detected title of the table or document.
  final String title;

  /// The list of column headers.
  final List<String> headers;

  /// The 2D grid of cell values (rows x columns).
  final List<List<String>> rows;

  /// Whether the table layout is Right-to-Left (e.g. Arabic) or Left-to-Right.
  final bool isRtl;

  /// File path to the source physical paper photo, if available.
  final String? sourceImagePath;

  /// Confidence score [0..100].
  final int confidence;

  /// Creates a copy with optional modifications.
  ExtractedTableResult copyWith({
    String? title,
    List<String>? headers,
    List<List<String>>? rows,
    bool? isRtl,
    String? sourceImagePath,
    int? confidence,
  }) {
    return ExtractedTableResult(
      title: title ?? this.title,
      headers: headers ?? this.headers,
      rows: rows ?? this.rows,
      isRtl: isRtl ?? this.isRtl,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// Internal cell candidate with physical 2D coordinates on the paper document.
class _PhysicalCellCandidate {
  _PhysicalCellCandidate({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.isRtl,
  });

  String text;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final bool isRtl;

  double get width => math.max(1.0, right - left);
  double get height => math.max(1.0, bottom - top);
  double get centerX => left + width / 2.0;
  double get centerY => top + height / 2.0;
}

/// Represents a detected vertical column band on the physical paper.
class _PhysicalColumnBand {
  _PhysicalColumnBand({
    required this.left,
    required this.right,
    required this.centerX,
  });

  double left;
  double right;
  double centerX;
  int count = 1;
}

/// Robust Physical Paper Table Extraction Service.
///
/// Converts photos of paper tables into structured, editable grids
/// preserving physical row/column geometry, multi-line cells, and RTL/LTR directionality.
class TableExtractionService {
  const TableExtractionService({
    OcrService? ocrService,
  }) : _ocrService = ocrService;

  final OcrService? _ocrService;

  /// Extracts structured table data from an image file path.
  Future<ExtractedTableResult> extractTableFromImage({
    required String imagePath,
    OcrService? ocrOverride,
  }) async {
    final activeOcr = ocrOverride ?? _ocrService ?? OcrService();
    final blocks = <OcrBlockItem>[];

    try {
      // 1. Primary: Run comprehensive OCR (Tesseract Arabic+English on device)
      final engine = activeOcr.selectEngine(languageMode: OcrLanguageMode.araAndEng);
      final pageResult = await engine.recognizePage(
        imagePath: imagePath,
        pageIndex: 0,
        languageMode: OcrLanguageMode.araAndEng,
        preprocess: true,
      );

      final imgW = pageResult.imageWidth > 0 ? pageResult.imageWidth.toDouble() : 1200.0;
      final imgH = pageResult.imageHeight > 0 ? pageResult.imageHeight.toDouble() : 1600.0;

      for (final line in pageResult.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        final left = line.pixelLeft > 0 ? line.pixelLeft.toDouble() : (line.left * imgW);
        final top = line.pixelTop > 0 ? line.pixelTop.toDouble() : (line.top * imgH);
        final width = line.pixelWidth > 0 ? line.pixelWidth.toDouble() : (line.normWidth * imgW);
        final height = line.pixelHeight > 0 ? line.pixelHeight.toDouble() : (line.normHeight * imgH);

        blocks.add(
          OcrBlockItem(
            text: t,
            top: top,
            left: left,
            width: width,
            height: height,
            isRtl: line.isRtl,
          ),
        );
      }
    } catch (e) {
      debugPrint('[TableExtractionService] Tesseract/OcrService failed: $e, falling back to ML Kit');
    }

    // 2. Fallback: If no blocks were extracted, use direct ML Kit TextRecognizer
    if (blocks.isEmpty) {
      try {
        final inputImage = InputImage.fromFilePath(imagePath);
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final recognizedText = await recognizer.processImage(inputImage);
        await recognizer.close();

        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            final t = line.text.trim();
            if (t.isEmpty) continue;
            final rect = line.boundingBox;
            blocks.add(
              OcrBlockItem(
                text: t,
                top: rect.top,
                left: rect.left,
                width: rect.width,
                height: rect.height,
                isRtl: OfficeExporterService.isRtlText(t),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[TableExtractionService] ML Kit fallback error: $e');
      }
    }

    if (blocks.isEmpty) {
      return ExtractedTableResult(
        title: 'جدول مستخرج',
        headers: const ['البند / الوصف', 'الكمية', 'السعر', 'الإجمالي'],
        rows: const [],
        isRtl: true,
        sourceImagePath: imagePath,
        confidence: 0,
      );
    }

    return extractTableFromBlocks(
      blocks: blocks,
      sourceImagePath: imagePath,
    );
  }

  /// Reconstructs the physical table structure from detected 2D OCR blocks.
  ExtractedTableResult extractTableFromBlocks({
    required List<OcrBlockItem> blocks,
    String? sourceImagePath,
  }) {
    if (blocks.isEmpty) {
      return ExtractedTableResult(
        title: 'جدول مستخرج',
        headers: const ['العمود 1', 'العمود 2'],
        rows: const [],
        isRtl: true,
        sourceImagePath: sourceImagePath,
      );
    }

    // 1. Determine overall table direction (RTL vs LTR)
    final rtlCount = blocks.where((b) => b.isRtl || OfficeExporterService.isRtlText(b.text)).length;
    final isRtl = rtlCount >= (blocks.length * 0.30);

    // 2. Extract cell candidates with delimiter handling (tabs, pipes, double-spaces)
    final candidates = <_PhysicalCellCandidate>[];
    for (final b in blocks) {
      candidates.addAll(_splitBlockIntoCandidates(b));
    }

    if (candidates.isEmpty) {
      return ExtractedTableResult(
        title: 'جدول مستخرج',
        headers: const ['العمود 1'],
        rows: const [],
        isRtl: isRtl,
        sourceImagePath: sourceImagePath,
      );
    }

    // Sort by vertical position (top Y)
    candidates.sort((a, b) {
      final topCmp = a.top.compareTo(b.top);
      if (topCmp != 0) return topCmp;
      return a.left.compareTo(b.left);
    });

    // 3. Compute document bounds & median row height
    final heights = candidates.map((c) => c.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];

    final minLeft = candidates.map((c) => c.left).reduce(math.min);
    final maxRight = candidates.map((c) => c.right).reduce(math.max);
    final tableWidth = math.max(100.0, maxRight - minLeft);

    // 4. Extract standalone Document Title if present at the top
    String detectedTitle = 'جدول البيانات المستخرج';
    var candidateIndex = 0;

    if (candidates.isNotEmpty) {
      final first = candidates.first;
      // If the first item is centered or wide (>35% of table width) and well above others
      if (first.width >= tableWidth * 0.35 || candidates.length == 1) {
        final nextItemTop = candidates.length > 1 ? candidates[1].top : first.bottom + 100;
        if ((nextItemTop - first.bottom) >= medianHeight * 0.4) {
          detectedTitle = first.text;
          candidateIndex = 1;
        }
      }
    }

    final tableCandidates = candidates.sublist(candidateIndex);
    if (tableCandidates.isEmpty) {
      return ExtractedTableResult(
        title: detectedTitle,
        headers: const ['البند / الوصف', 'القيمة'],
        rows: const [],
        isRtl: isRtl,
        sourceImagePath: sourceImagePath,
      );
    }

    // 5. Cluster candidates into physical rows using adaptive vertical tolerance
    final clusteredRows = _clusterIntoPhysicalRows(tableCandidates, medianHeight);

    // 6. Detect physical column bands across rows
    final bands = _detectPhysicalColumnBands(clusteredRows, isRtl: isRtl);
    final colCount = math.max(1, bands.length);

    // 7. Align each row to the spatial column bands via Dynamic Programming
    final gridRows = <List<String>>[];
    for (final row in clusteredRows) {
      final alignedMap = _alignRowToBands(
        row: row,
        bands: bands,
        tableWidth: tableWidth,
      );

      final rowCells = List<String>.filled(colCount, '');
      alignedMap.forEach((bandIdx, cell) {
        if (bandIdx >= 0 && bandIdx < colCount) {
          final colIdx = isRtl ? (colCount - 1 - bandIdx) : bandIdx;
          final existing = rowCells[colIdx];
          rowCells[colIdx] = existing.isEmpty ? cell.text : '$existing ${cell.text}';
        }
      });

      // Keep rows that have at least one non-empty cell
      if (rowCells.any((c) => c.trim().isNotEmpty)) {
        gridRows.add(rowCells);
      }
    }

    if (gridRows.isEmpty) {
      return ExtractedTableResult(
        title: detectedTitle,
        headers: List.generate(colCount, (i) => 'عمود ${i + 1}'),
        rows: const [],
        isRtl: isRtl,
        sourceImagePath: sourceImagePath,
      );
    }

    // 8. Identify Header Row (first row with multiple text items that is not purely numbers)
    int headerRowIdx = 0;
    for (var r = 0; r < gridRows.length; r++) {
      final row = gridRows[r];
      final nonEmpty = row.where((c) => c.trim().isNotEmpty).toList();
      if (nonEmpty.length >= 2 || (colCount >= 2 && nonEmpty.isNotEmpty)) {
        final numericCount = nonEmpty.where((c) => OfficeExporterService.parseFlexibleNumber(c) != null).length;
        if (numericCount <= (nonEmpty.length * 0.45)) {
          headerRowIdx = r;
          break;
        }
      }
    }

    final rawHeaders = gridRows[headerRowIdx];
    final headers = <String>[];
    for (var c = 0; c < colCount; c++) {
      final val = rawHeaders[c].trim();
      headers.add(val.isNotEmpty ? val : 'عمود ${c + 1}');
    }

    // Data rows are all rows after headerRowIdx (plus any rows before it that were data)
    final dataRows = <List<String>>[];
    for (var r = 0; r < gridRows.length; r++) {
      if (r == headerRowIdx) continue;
      dataRows.add(gridRows[r]);
    }

    return ExtractedTableResult(
      title: detectedTitle,
      headers: headers,
      rows: dataRows,
      isRtl: isRtl,
      sourceImagePath: sourceImagePath,
      confidence: 95,
    );
  }

  /// Splits a single OCR block by common delimiters (tabs, pipes, multiple spaces).
  List<_PhysicalCellCandidate> _splitBlockIntoCandidates(OcrBlockItem block) {
    final text = block.text.trim();
    if (text.isEmpty) return const [];

    final delimiterRegex = RegExp(r'(\t|\||\s{3,})');
    final matches = delimiterRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      return [
        _PhysicalCellCandidate(
          text: text,
          left: block.left,
          right: block.right,
          top: block.top,
          bottom: block.bottom,
          isRtl: block.isRtl,
        ),
      ];
    }

    final candidates = <_PhysicalCellCandidate>[];
    var lastEnd = 0;
    final totalLen = math.max(1, text.length);

    void addSlice(int start, int end) {
      final slice = text.substring(start, end).trim();
      if (slice.isEmpty) return;

      final startRatio = start / totalLen;
      final endRatio = end / totalLen;

      final cellLeft = block.left + startRatio * block.width;
      final cellRight = block.left + endRatio * block.width;

      candidates.add(
        _PhysicalCellCandidate(
          text: slice,
          left: cellLeft,
          right: math.max(cellLeft + 10.0, cellRight),
          top: block.top,
          bottom: block.bottom,
          isRtl: OfficeExporterService.isRtlText(slice) || block.isRtl,
        ),
      );
    }

    for (final match in matches) {
      if (match.start > lastEnd) {
        addSlice(lastEnd, match.start);
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      addSlice(lastEnd, text.length);
    }

    return candidates.isEmpty
        ? [
            _PhysicalCellCandidate(
              text: text,
              left: block.left,
              right: block.right,
              top: block.top,
              bottom: block.bottom,
              isRtl: block.isRtl,
            ),
          ]
        : candidates;
  }

  /// Clusters physical candidates into horizontal rows based on vertical overlap.
  List<List<_PhysicalCellCandidate>> _clusterIntoPhysicalRows(
    List<_PhysicalCellCandidate> candidates,
    double medianHeight,
  ) {
    if (candidates.isEmpty) return const [];

    final sorted = List<_PhysicalCellCandidate>.from(candidates)
      ..sort((a, b) {
        final topCmp = a.top.compareTo(b.top);
        if (topCmp != 0) return topCmp;
        return a.left.compareTo(b.left);
      });

    final rows = <List<_PhysicalCellCandidate>>[];
    for (final item in sorted) {
      if (rows.isEmpty) {
        rows.add([item]);
        continue;
      }

      final currentRow = rows.last;
      final avgCenterY = currentRow.map((e) => e.centerY).reduce((a, b) => a + b) / currentRow.length;
      final avgHeight = currentRow.map((e) => e.height).reduce((a, b) => a + b) / currentRow.length;

      final tolerance = math.max(12.0, avgHeight * 0.65);
      if ((item.centerY - avgCenterY).abs() <= tolerance) {
        currentRow.add(item);
      } else {
        rows.add([item]);
      }
    }

    // Merge horizontally overlapping items in the same row (multi-line text within the same cell)
    final processedRows = <List<_PhysicalCellCandidate>>[];
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));

      final mergedRow = <_PhysicalCellCandidate>[];
      for (final item in row) {
        if (mergedRow.isEmpty) {
          mergedRow.add(item);
          continue;
        }

        final prev = mergedRow.last;
        final overlapX = math.max(0.0, math.min(prev.right, item.right) - math.max(prev.left, item.left));
        final minW = math.min(prev.width, item.width);

        if (overlapX >= minW * 0.35) {
          // Multi-line cell: concatenate text and expand envelope
          prev.text = '${prev.text} ${item.text}';
        } else {
          mergedRow.add(item);
        }
      }

      processedRows.add(mergedRow);
    }

    return processedRows;
  }

  /// Detects vertical column bands across rows, ordered spatially from left to right.
  List<_PhysicalColumnBand> _detectPhysicalColumnBands(
    List<List<_PhysicalCellCandidate>> rows, {
    required bool isRtl,
  }) {
    final multiItemRows = rows.where((r) => r.length >= 2).toList();
    if (multiItemRows.isEmpty) {
      return [
        _PhysicalColumnBand(left: 0, right: 1000, centerX: 500),
      ];
    }

    final maxCols = multiItemRows.map((r) => r.length).reduce(math.max);
    final templateRows = multiItemRows.where((r) => r.length == maxCols).toList();

    final bands = <_PhysicalColumnBand>[];
    for (var c = 0; c < maxCols; c++) {
      var sumLeft = 0.0;
      var sumRight = 0.0;
      var sumCenter = 0.0;
      for (final row in templateRows) {
        final cell = row[c];
        sumLeft += cell.left;
        sumRight += cell.right;
        sumCenter += cell.centerX;
      }
      final count = templateRows.length;
      bands.add(
        _PhysicalColumnBand(
          left: sumLeft / count,
          right: sumRight / count,
          centerX: sumCenter / count,
        )..count = count,
      );
    }

    // Incorporate additional distinct columns from other rows
    final avgColWidth = bands.isEmpty
        ? 120.0
        : (bands.last.centerX - bands.first.centerX) / math.max(1, bands.length);
    final gapThreshold = avgColWidth * 0.75;

    for (final row in multiItemRows) {
      for (final cell in row) {
        final minDistance = bands.map((b) => (b.centerX - cell.centerX).abs()).reduce(math.min);
        if (minDistance > gapThreshold) {
          bands.add(
            _PhysicalColumnBand(
              left: cell.left,
              right: cell.right,
              centerX: cell.centerX,
            ),
          );
        }
      }
    }

    // Always sort column bands spatially from left to right (ascending centerX)
    // to maintain monotonic alignment with row candidates.
    bands.sort((a, b) => a.centerX.compareTo(b.centerX));

    return bands;
  }

  /// Aligns cells in a row to the detected column bands using Dynamic Programming.
  Map<int, _PhysicalCellCandidate> _alignRowToBands({
    required List<_PhysicalCellCandidate> row,
    required List<_PhysicalColumnBand> bands,
    required double tableWidth,
  }) {
    final result = <int, _PhysicalCellCandidate>{};
    if (row.isEmpty || bands.isEmpty) return result;

    if (row.length == 1) {
      final item = row.first;
      var bestBand = 0;
      var bestDist = double.infinity;
      for (var b = 0; b < bands.length; b++) {
        final dist = (item.centerX - bands[b].centerX).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestBand = b;
        }
      }
      result[bestBand] = item;
      return result;
    }

    final m = row.length;
    final M = bands.length;

    if (m >= M) {
      for (var i = 0; i < m; i++) {
        result[math.min(i, M - 1)] = row[i];
      }
      return result;
    }

    // Dynamic Programming for monotonic matching
    final dp = List.generate(m, (_) => List<double>.filled(M, double.infinity));
    final parent = List.generate(m, (_) => List<int>.filled(M, -1));

    for (var j = 0; j <= M - m; j++) {
      dp[0][j] = (row[0].centerX - bands[j].centerX).abs();
    }

    for (var i = 1; i < m; i++) {
      for (var j = i; j <= M - (m - i); j++) {
        var minPrevCost = double.infinity;
        var bestPrevBand = -1;
        for (var k = i - 1; k < j; k++) {
          if (dp[i - 1][k] < minPrevCost) {
            minPrevCost = dp[i - 1][k];
            bestPrevBand = k;
          }
        }
        if (minPrevCost < double.infinity) {
          final dist = (row[i].centerX - bands[j].centerX).abs();
          dp[i][j] = minPrevCost + dist;
          parent[i][j] = bestPrevBand;
        }
      }
    }

    var bestLastBand = -1;
    var minTotalCost = double.infinity;
    for (var j = m - 1; j < M; j++) {
      if (dp[m - 1][j] < minTotalCost) {
        minTotalCost = dp[m - 1][j];
        bestLastBand = j;
      }
    }

    if (bestLastBand == -1) {
      for (var i = 0; i < m; i++) {
        result[i] = row[i];
      }
      return result;
    }

    var currBand = bestLastBand;
    for (var i = m - 1; i >= 0; i--) {
      result[currBand] = row[i];
      currBand = parent[i][currBand];
    }

    return result;
  }
}
