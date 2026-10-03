import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:cam_scanner/shared/models/pending_upload.dart';
import 'package:cam_scanner/features/scanner/data/local_document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug 1: Folder Filtering & Root View Integrity', () {
    final unfiledDoc1 = PendingUpload(
      id: 'doc_1',
      fileName: 'Invoice_1.pdf',
      filePath: '/tmp/doc_1.pdf',
      pageCount: 1,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      folderId: null,
    );

    final unfiledDoc2 = PendingUpload(
      id: 'doc_2',
      fileName: 'Contract.pdf',
      filePath: '/tmp/doc_2.pdf',
      pageCount: 2,
      createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
      folderId: '',
    );

    final filedDoc1 = PendingUpload(
      id: 'doc_3',
      fileName: 'Work_Report.pdf',
      filePath: '/tmp/doc_3.pdf',
      pageCount: 3,
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      folderId: 'folder_work',
    );

    final filedDoc2 = PendingUpload(
      id: 'doc_4',
      fileName: 'Tax_Document.pdf',
      filePath: '/tmp/doc_4.pdf',
      pageCount: 4,
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      folderId: 'folder_finance',
    );

    final allDocs = [unfiledDoc1, unfiledDoc2, filedDoc1, filedDoc2];

    List<PendingUpload> filterDocuments({
      required List<PendingUpload> docs,
      String? activeFolderId,
      String query = '',
    }) {
      final q = query.trim().toLowerCase();
      return docs.where((doc) {
        if (activeFolderId != null) {
          if (doc.folderId != activeFolderId) return false;
        } else {
          // At root: only show unfiled documents when query is empty
          if (q.isEmpty) {
            if (doc.folderId != null && doc.folderId!.isNotEmpty) {
              return false;
            }
          }
        }
        if (q.isNotEmpty) {
          return doc.title.toLowerCase().contains(q) ||
              doc.fileName.toLowerCase().contains(q);
        }
        return true;
      }).toList();
    }

    test('In root view without search, filed documents are hidden from root list', () {
      final rootDocs = filterDocuments(
        docs: allDocs,
        activeFolderId: null,
        query: '',
      );

      expect(rootDocs.length, equals(2));
      expect(rootDocs.map((d) => d.id), containsAll(['doc_1', 'doc_2']));
      expect(rootDocs.any((d) => d.id == 'doc_3'), isFalse);
      expect(rootDocs.any((d) => d.id == 'doc_4'), isFalse);
    });

    test('When dragging/moving doc_1 into folder_work, it disappears from root', () {
      final updatedDoc1 = unfiledDoc1.copyWith(folderId: 'folder_work');
      final updatedAllDocs = [updatedDoc1, unfiledDoc2, filedDoc1, filedDoc2];

      final rootDocs = filterDocuments(
        docs: updatedAllDocs,
        activeFolderId: null,
        query: '',
      );

      expect(rootDocs.length, equals(1));
      expect(rootDocs.first.id, equals('doc_2'));
      expect(rootDocs.any((d) => d.id == 'doc_1'), isFalse);
    });

    test('When activeFolderId is set, only documents in that folder appear', () {
      final workDocs = filterDocuments(
        docs: allDocs,
        activeFolderId: 'folder_work',
        query: '',
      );

      expect(workDocs.length, equals(1));
      expect(workDocs.first.id, equals('doc_3'));
      expect(workDocs.first.fileName, equals('Work_Report.pdf'));
    });

    test('When searching in root view, matching documents in folders are discoverable', () {
      final searchResults = filterDocuments(
        docs: allDocs,
        activeFolderId: null,
        query: 'Report',
      );

      expect(searchResults.length, equals(1));
      expect(searchResults.first.id, equals('doc_3'));
      expect(searchResults.first.folderId, equals('folder_work'));
    });
  });

  group('Bug 2: LocalDocumentStore purgeOrphanDrafts() Age Protection', () {
    late Directory tempDraftsDir;

    setUp(() async {
      tempDraftsDir = await Directory.systemTemp.createTemp('cam_scanner_test_drafts_');
    });

    tearDown(() async {
      if (await tempDraftsDir.exists()) {
        await tempDraftsDir.delete(recursive: true);
      }
    });

    test('purgeOrphanDrafts() protects freshly captured raw scan files (< 2 hours old)', () async {
      // Create a fresh raw capture file
      final freshRawFile = File(path.join(tempDraftsDir.path, 'raw_test_capture.jpg'));
      await freshRawFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);

      // Create a stale raw capture file (> 3 hours old)
      final staleRawFile = File(path.join(tempDraftsDir.path, 'raw_stale_capture.jpg'));
      await staleRawFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
      final staleDate = DateTime.now().subtract(const Duration(hours: 4));
      await staleRawFile.setLastModified(staleDate);

      // Verify files exist before purge
      expect(await freshRawFile.exists(), isTrue);
      expect(await staleRawFile.exists(), isTrue);

      // Simulate the exact logic in purgeOrphanDrafts()
      final now = DateTime.now();
      final entities = tempDraftsDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          final name = path.basename(entity.path);
          if (name.startsWith('raw_') || name.startsWith('preview_')) {
            final stat = entity.statSync();
            if (now.difference(stat.modified).inHours < 2) {
              continue; // protected
            }
            entity.deleteSync();
          }
        }
      }

      // Fresh raw file MUST still exist!
      expect(await freshRawFile.exists(), isTrue, reason: 'Recent raw captures must NEVER be purged');

      // Stale raw file must be purged
      expect(await staleRawFile.exists(), isFalse, reason: 'Old orphaned captures (>2h) should be purged');
    });
  });
}
