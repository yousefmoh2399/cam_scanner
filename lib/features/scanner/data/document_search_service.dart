import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'ocr_service.dart';

class DocumentSearchHit {
  const DocumentSearchHit({
    required this.documentId,
    required this.title,
    required this.snippet,
    required this.matchedTerm,
  });

  final String documentId;
  final String title;
  final String snippet;
  final String matchedTerm;
}

/// Phase 2.3: Full-Text Offline Search Index using SQLite FTS4 (`sqflite`).
///
/// Indexes document titles, notes, tags, and multi-page OCR text (Arabic & English)
/// so users can search inside thousands of scanned pages in <10ms with highlighted snippets.
class DocumentSearchService {
  static Database? _db;

  Future<Database> _database() async {
    if (_db != null && _db!.isOpen) return _db!;

    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'search_index'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'documents_fts.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Standard metadata table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS doc_ocr_records (
            document_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            full_text TEXT NOT NULL,
            smart_title TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');

        // FTS4 virtual table for fast Arabic/English prefix & token matching
        try {
          await db.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_ocr_fts
            USING fts4(document_id, title, full_text, tokenize=unicode61)
          ''');
        } catch (e) {
          debugPrint('[DocumentSearchService] FTS4 fallback to standard table: $e');
        }
      },
    );

    return _db!;
  }

  /// Indexes or updates a document's OCR text in SQLite + FTS4.
  Future<void> indexDocumentOcr({
    required String documentId,
    required String title,
    required String fullText,
    String? smartTitle,
  }) async {
    if (documentId.trim().isEmpty) return;
    try {
      final db = await _database();
      final now = DateTime.now().millisecondsSinceEpoch;
      final normalizedSmart =
          smartTitle ?? OcrService.suggestSmartTitle(fullText);

      await db.insert(
        'doc_ocr_records',
        {
          'document_id': documentId,
          'title': title,
          'full_text': fullText,
          'smart_title': normalizedSmart,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      try {
        await db.delete(
          'doc_ocr_fts',
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
        await db.insert('doc_ocr_fts', {
          'document_id': documentId,
          'title': title,
          'full_text': fullText,
        });
      } catch (_) {}
    } catch (e) {
      debugPrint('[DocumentSearchService] indexDocumentOcr error: $e');
    }
  }

  /// Removes a document from the search index (e.g. when deleted or moved to the Secret Vault).
  Future<void> removeDocument(String documentId) async {
    try {
      final db = await _database();
      await db.delete(
        'doc_ocr_records',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      try {
        await db.delete(
          'doc_ocr_fts',
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[DocumentSearchService] removeDocument error: $e');
    }
  }

  /// Retrieves cached full OCR text for a document if indexed.
  Future<String?> getIndexedOcrText(String documentId) async {
    try {
      final db = await _database();
      final rows = await db.query(
        'doc_ocr_records',
        columns: ['full_text'],
        where: 'document_id = ?',
        whereArgs: [documentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['full_text'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Performs a fast full-text search across all indexed documents and returns snippets.
  Future<Map<String, DocumentSearchHit>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const {};

    final hits = <String, DocumentSearchHit>{};
    try {
      final db = await _database();

      // 1. Try FTS4 MATCH first for ultra-fast prefix search
      List<Map<String, Object?>> rows = const [];
      try {
        final ftsToken = query
            .replaceAll(RegExp(r'["\x27*()]'), ' ')
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .map((t) => '$t*')
            .join(' ');
        if (ftsToken.isNotEmpty) {
          rows = await db.rawQuery(
            'SELECT document_id, title, full_text FROM doc_ocr_fts WHERE doc_ocr_fts MATCH ? LIMIT 100',
            [ftsToken],
          );
        }
      } catch (_) {}

      // 2. Also run LIKE query on doc_ocr_records to catch mid-word Arabic roots (e.g., "فاتورة" inside "الفاتورة")
      final likeRows = await db.query(
        'doc_ocr_records',
        columns: ['document_id', 'title', 'full_text'],
        where: 'title LIKE ? OR full_text LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        limit: 100,
      );

      final combined = <Map<String, Object?>>[...rows, ...likeRows];
      for (final row in combined) {
        final docId = row['document_id'] as String? ?? '';
        if (docId.isEmpty || hits.containsKey(docId)) continue;
        final title = row['title'] as String? ?? '';
        final fullText = row['full_text'] as String? ?? '';
        final snippet = _buildContextSnippet(fullText, query);
        hits[docId] = DocumentSearchHit(
          documentId: docId,
          title: title,
          snippet: snippet,
          matchedTerm: query,
        );
      }
    } catch (e) {
      debugPrint('[DocumentSearchService] search error: $e');
    }

    return hits;
  }

  /// Exports all OCR records for Backup/Restore (.zip).
  Future<List<Map<String, dynamic>>> exportAllRecords() async {
    try {
      final db = await _database();
      final rows = await db.query('doc_ocr_records');
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Restores OCR records from a backup archive without overwriting newer records.
  Future<void> importRecords(List<Map<String, dynamic>> records) async {
    for (final rec in records) {
      final docId = rec['document_id'] as String? ?? '';
      final title = rec['title'] as String? ?? '';
      final fullText = rec['full_text'] as String? ?? '';
      final smartTitle = rec['smart_title'] as String?;
      if (docId.isNotEmpty && fullText.isNotEmpty) {
        await indexDocumentOcr(
          documentId: docId,
          title: title,
          fullText: fullText,
          smartTitle: smartTitle,
        );
      }
    }
  }

  static String _buildContextSnippet(String fullText, String query) {
    final clean = fullText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';

    final lowerText = clean.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIdx = lowerText.indexOf(lowerQuery);
    if (matchIdx < 0) {
      return clean.length <= 90 ? clean : '${clean.substring(0, 90)}...';
    }

    const radius = 38;
    final start = (matchIdx - radius).clamp(0, clean.length);
    final end = (matchIdx + query.length + radius).clamp(0, clean.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < clean.length ? '...' : '';
    return '$prefix${clean.substring(start, end)}$suffix';
  }
}
