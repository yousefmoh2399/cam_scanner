import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

enum DiffType {
  equal,
  insert,
  delete,
}

class DiffSegment {
  const DiffSegment({
    required this.text,
    required this.type,
  });

  final String text;
  final DiffType type;
}

class DocumentDiffResult {
  const DocumentDiffResult({
    required this.segments,
    required this.totalWordsA,
    required this.totalWordsB,
    required this.addedCount,
    required this.deletedCount,
    required this.unchangedCount,
    required this.similarityScore,
  });

  final List<DiffSegment> segments;
  final int totalWordsA;
  final int totalWordsB;
  final int addedCount;
  final int deletedCount;
  final int unchangedCount;

  /// Percentage 0.0 to 100.0%
  final double similarityScore;
}

class DocumentDiffService {
  /// Extracts text offline using Google ML Kit on-device model
  Future<String> extractTextOffline(String imagePath) async {
    final inputImage = InputImage.fromFile(File(imagePath));
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(inputImage);
      return recognizedText.text;
    } finally {
      await recognizer.close();
    }
  }

  /// Computes offline word-level LCS diff between textA and textB
  DocumentDiffResult compareTexts(String textA, String textB) {
    final wordsA = _tokenize(textA);
    final wordsB = _tokenize(textB);

    final lcs = _computeLcs(wordsA, wordsB);
    final segments = <DiffSegment>[];

    int i = 0, j = 0;
    int added = 0, deleted = 0, equal = 0;

    for (final match in lcs) {
      // Elements in A before match are deletions
      while (i < match.indexA) {
        segments.add(DiffSegment(text: wordsA[i], type: DiffType.delete));
        deleted++;
        i++;
      }
      // Elements in B before match are additions
      while (j < match.indexB) {
        segments.add(DiffSegment(text: wordsB[j], type: DiffType.insert));
        added++;
        j++;
      }
      // Matched element is equal
      segments.add(DiffSegment(text: wordsA[i], type: DiffType.equal));
      equal++;
      i++;
      j++;
    }

    // Remaining in A are deletions
    while (i < wordsA.length) {
      segments.add(DiffSegment(text: wordsA[i], type: DiffType.delete));
      deleted++;
      i++;
    }

    // Remaining in B are additions
    while (j < wordsB.length) {
      segments.add(DiffSegment(text: wordsB[j], type: DiffType.insert));
      added++;
      j++;
    }

    final total = wordsA.length + wordsB.length;
    final similarity = total > 0 ? ((equal * 2) / total * 100).clamp(0.0, 100.0) : 100.0;

    return DocumentDiffResult(
      segments: segments,
      totalWordsA: wordsA.length,
      totalWordsB: wordsB.length,
      addedCount: added,
      deletedCount: deleted,
      unchangedCount: equal,
      similarityScore: similarity,
    );
  }

  List<String> _tokenize(String text) {
    if (text.trim().isEmpty) return [];
    return text
        .replaceAll(RegExp(r'\r\n|\r|\n'), ' \n ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<({int indexA, int indexB})> _computeLcs(
    List<String> a,
    List<String> b,
  ) {
    final m = a.length;
    final n = b.length;

    // Fast bounds limit for huge documents to prevent memory overflow
    if (m * n > 4000000) {
      return _computeGreedyDiff(a, b);
    }

    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack to build matches
    final matches = <({int indexA, int indexB})>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        matches.add((indexA: i - 1, indexB: j - 1));
        i--;
        j--;
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return matches.reversed.toList();
  }

  List<({int indexA, int indexB})> _computeGreedyDiff(
    List<String> a,
    List<String> b,
  ) {
    final matches = <({int indexA, int indexB})>[];
    int j = 0;
    for (int i = 0; i < a.length && j < b.length; i++) {
      for (int k = j; k < b.length && k < j + 40; k++) {
        if (a[i] == b[k]) {
          matches.add((indexA: i, indexB: k));
          j = k + 1;
          break;
        }
      }
    }
    return matches;
  }
}
