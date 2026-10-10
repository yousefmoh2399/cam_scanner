import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../shared/models/document_folder.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/services/local_media_storage_service.dart';
import 'document_search_service.dart';
import 'vault_security_service.dart';

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.restoredDocuments,
    required this.restoredFolders,
    required this.skippedDuplicates,
    this.restoredVaultDocuments = 0,
  });

  final int restoredDocuments;
  final int restoredFolders;
  final int skippedDuplicates;
  final int restoredVaultDocuments;
}

/// Phase 3.4: 100% Offline Full Library Backup & Restore (.zip)
///
/// Exports all documents, page images, folders, tags, notes, and OCR search index
/// into a portable `.zip` file (with optional PBKDF2 + AES-256-GCM password encryption)
/// and restores/merges them on any device without duplicating existing records.
class BackupRestoreService {
  BackupRestoreService({
    VaultSecurityService? securityService,
    DocumentSearchService? searchService,
  })  : _securityService = securityService ?? VaultSecurityService(),
        _searchService = searchService ?? DocumentSearchService();

  final VaultSecurityService _securityService;
  final DocumentSearchService _searchService;

  /// Creates a portable `.zip` backup file containing all documents, folders, media files,
  /// vault documents, and OCR search index. If [password] is provided, the payload is encrypted with AES-256-GCM (Zero-Knowledge).
  Future<String> createBackupZip({
    required List<PendingUpload> documents,
    required List<DocumentFolder> folders,
    List<PendingUpload>? vaultDocuments,
    String? password,
    ValueChanged<String>? onProgress,
  }) async {
    onProgress?.call('جارٍ جمع بيانات المستندات والمجلدات وفهرس البحث...');
    final ocrRecords = await _searchService.exportAllRecords();

    // Map local absolute paths to relative archive paths
    final mediaFilesToPack = <String, String>{}; // archiveRelPath -> localAbsPath
    final serializedDocs = <Map<String, dynamic>>[];
    final serializedVaultDocs = <Map<String, dynamic>>[];

    String? registerMediaFile(String? absPath, String docId, String role) {
      if (absPath == null || absPath.isEmpty) return null;
      final file = File(absPath);
      if (!file.existsSync()) return null;
      final relPath = 'media/${docId}_${role}_${p.basename(absPath)}';
      mediaFilesToPack[relPath] = absPath;
      return relPath;
    }

    for (final doc in documents) {
      final docJson = doc.toJson();
      docJson['file_path'] =
          registerMediaFile(doc.filePath, doc.id, 'pdf') ?? '';
      docJson['thumbnail_path'] =
          registerMediaFile(doc.thumbnailPath, doc.id, 'thumb');
      docJson['docx_path'] =
          registerMediaFile(doc.docxPath, doc.id, 'docx');
      docJson['xlsx_path'] =
          registerMediaFile(doc.xlsxPath, doc.id, 'xlsx');

      final pagesJson = <Map<String, dynamic>>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final pg = doc.pages[i];
        final pgJson = pg.toJson();
        pgJson['image_path'] =
            registerMediaFile(pg.imagePath, doc.id, 'p$i') ?? '';
        pgJson['original_image_path'] =
            registerMediaFile(pg.originalImagePath, doc.id, 'orig$i') ??
                pgJson['image_path'];
        pagesJson.add(pgJson);
      }
      docJson['pages'] = pagesJson;
      serializedDocs.add(docJson);
    }

    if (vaultDocuments != null && vaultDocuments.isNotEmpty) {
      for (final doc in vaultDocuments) {
        final docJson = doc.toJson();
        docJson['file_path'] =
            registerMediaFile(doc.filePath, 'vault_${doc.id}', 'pdf') ?? '';
        docJson['thumbnail_path'] =
            registerMediaFile(doc.thumbnailPath, 'vault_${doc.id}', 'thumb');
        docJson['docx_path'] =
            registerMediaFile(doc.docxPath, 'vault_${doc.id}', 'docx');
        docJson['xlsx_path'] =
            registerMediaFile(doc.xlsxPath, 'vault_${doc.id}', 'xlsx');

        final pagesJson = <Map<String, dynamic>>[];
        for (var i = 0; i < doc.pages.length; i++) {
          final pg = doc.pages[i];
          final pgJson = pg.toJson();
          pgJson['image_path'] =
              registerMediaFile(pg.imagePath, 'vault_${doc.id}', 'p$i') ?? '';
          pgJson['original_image_path'] =
              registerMediaFile(pg.originalImagePath, 'vault_${doc.id}', 'orig$i') ??
                  pgJson['image_path'];
          pagesJson.add(pgJson);
        }
        docJson['pages'] = pagesJson;
        serializedVaultDocs.add(docJson);
      }
    }

    final manifest = <String, dynamic>{
      'version': 3,
      'created_at': DateTime.now().toIso8601String(),
      'documents_count': serializedDocs.length,
      'folders_count': folders.length,
      'vault_documents_count': serializedVaultDocs.length,
      'documents': serializedDocs,
      'folders': folders.map((f) => f.toJson()).toList(),
      'vault_documents': serializedVaultDocs,
      'ocr_records': ocrRecords,
    };

    onProgress?.call(
      'جارٍ ضغط ${mediaFilesToPack.length} ملف داخل أرشيف النسخة الاحتياطية...',
    );

    var zipBytes = await Isolate.run(
      () => _buildInnerArchiveInIsolate(manifest, mediaFilesToPack),
    );

    // Optional password-based AES-256-GCM encryption
    if (password != null && password.trim().isNotEmpty) {
      onProgress?.call('جارٍ تشفير النسخة الاحتياطية بمعيار AES-256-GCM...');
      final salt = SecretKeyData.random(length: 16).bytes;
      final key =
          await _securityService.deriveKeyFromPassword(password.trim(), salt);
      final encryptedPayload = await _securityService.encryptBytes(
        zipBytes,
        customKey: key,
      );

      final outerArchive = Archive();
      final metaJson = utf8.encode(
        jsonEncode({
          'encrypted': true,
          'cipher': 'AES-256-GCM-PBKDF2-SHA256',
          'salt_b64': base64Encode(salt),
        }),
      );
      outerArchive.addFile(
        ArchiveFile('encryption_meta.json', metaJson.length, metaJson),
      );
      outerArchive.addFile(
        ArchiveFile(
          'payload.enc',
          encryptedPayload.length,
          encryptedPayload,
        ),
      );
      final encodedOuter = ZipEncoder().encode(outerArchive);
      if (encodedOuter != null) {
        zipBytes = Uint8List.fromList(encodedOuter);
      }
    }

    final exportsDir = await const LocalMediaStorageService().exportsDirectory();
    final dateTag =
        DateTime.now().toIso8601String().split('T').first.replaceAll('-', '');
    final outPath =
        p.join(exportsDir.path, 'cam_scanner_backup_$dateTag.zip');
    await File(outPath).writeAsBytes(zipBytes, flush: true);

    onProgress?.call('تم إنشاء ملف النسخة الاحتياطية بنجاح!');
    return outPath;
  }

  /// Checks whether a backup `.zip` file is encrypted with a password.
  Future<bool> isBackupEncrypted(String zipFilePath) async {
    final bytes = await File(zipFilePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.findFile('encryption_meta.json') != null &&
        archive.findFile('payload.enc') != null;
  }

  /// Restores and merges a `.zip` backup into existing [currentDocuments] and [currentFolders].
  /// Returns the merged lists and statistics without duplicating existing documents.
  Future<({
    List<PendingUpload> mergedDocuments,
    List<DocumentFolder> mergedFolders,
    List<PendingUpload> restoredVaultDocuments,
    BackupRestoreResult stats,
  })> restoreFromBackupFile({
    required String zipFilePath,
    required List<PendingUpload> currentDocuments,
    required List<DocumentFolder> currentFolders,
    String? password,
    ValueChanged<String>? onProgress,
  }) async {
    onProgress?.call('جارٍ قراءة ملف النسخة الاحتياطية...');
    var rawBytes = await File(zipFilePath).readAsBytes();
    var archive = ZipDecoder().decodeBytes(rawBytes);

    // Handle password-encrypted backup
    final encMetaFile = archive.findFile('encryption_meta.json');
    final encPayloadFile = archive.findFile('payload.enc');
    if (encMetaFile != null && encPayloadFile != null) {
      if (password == null || password.trim().isEmpty) {
        throw Exception(
          'هذه النسخة الاحتياطية محمية بكلمة مرور. يرجى إدخال كلمة المرور أولاً.',
        );
      }
      onProgress?.call('جارٍ فك تشفير النسخة الاحتياطية (AES-256-GCM)...');
      final metaMap = jsonDecode(
        utf8.decode(encMetaFile.content as List<int>),
      ) as Map<String, dynamic>;
      final salt = base64Decode(metaMap['salt_b64'] as String);
      final key =
          await _securityService.deriveKeyFromPassword(password.trim(), salt);
      try {
        final decryptedZip = await _securityService.decryptBytes(
          Uint8List.fromList(encPayloadFile.content as List<int>),
          customKey: key,
        );
        archive = ZipDecoder().decodeBytes(decryptedZip);
      } catch (_) {
        throw Exception('كلمة المرور غير صحيحة أو الملف تالف.');
      }
    }

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw Exception('ملف النسخة الاحتياطية غير صالح (manifest.json مفقود).');
    }

    final manifest = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;

    const mediaStorage = LocalMediaStorageService();
    final docsDir = await mediaStorage.documentsDirectory();
    final pagesDir = await mediaStorage.pagesDirectory();
    final exportsDir = await mediaStorage.exportsDirectory();

    Future<String?> unpackMediaFile(String? relPath, Directory targetDir) async {
      if (relPath == null || relPath.isEmpty) return null;
      final entry = archive.findFile(relPath);
      if (entry == null) return null;
      final fileName = p.basename(relPath);
      final destPath = p.join(targetDir.path, fileName);
      await File(destPath).writeAsBytes(
        entry.content as List<int>,
        flush: true,
      );
      return destPath;
    }

    // 1. Merge Folders (deduplicate by ID or name)
    final mergedFolders = List<DocumentFolder>.from(currentFolders);
    final existingFolderIds = mergedFolders.map((f) => f.id).toSet();
    int restoredFoldersCount = 0;

    final rawFolders = manifest['folders'] as List<dynamic>? ?? const [];
    for (final item in rawFolders.whereType<Map<String, dynamic>>()) {
      final folder = DocumentFolder.fromJson(item);
      if (!existingFolderIds.contains(folder.id)) {
        mergedFolders.add(folder);
        existingFolderIds.add(folder.id);
        restoredFoldersCount++;
      }
    }

    // 2. Merge Documents (deduplicate by ID)
    final mergedDocuments = List<PendingUpload>.from(currentDocuments);
    final existingDocIds = mergedDocuments.map((d) => d.id).toSet();
    int restoredDocsCount = 0;
    int skippedDuplicatesCount = 0;

    final rawDocs = manifest['documents'] as List<dynamic>? ?? const [];
    for (var i = 0; i < rawDocs.length; i++) {
      final raw = rawDocs[i];
      if (raw is! Map<String, dynamic>) continue;
      final docId = raw['id'] as String? ?? '';
      if (docId.isEmpty || existingDocIds.contains(docId)) {
        skippedDuplicatesCount++;
        continue;
      }

      onProgress?.call(
        'جارٍ استعادة المستند ${i + 1} من ${rawDocs.length}...',
      );

      final docCopy = Map<String, dynamic>.from(raw);
      docCopy['file_path'] =
          await unpackMediaFile(raw['file_path'] as String?, docsDir) ?? '';
      docCopy['thumbnail_path'] =
          await unpackMediaFile(raw['thumbnail_path'] as String?, pagesDir);
      docCopy['docx_path'] =
          await unpackMediaFile(raw['docx_path'] as String?, exportsDir);
      docCopy['xlsx_path'] =
          await unpackMediaFile(raw['xlsx_path'] as String?, exportsDir);

      final rawPages = raw['pages'] as List<dynamic>? ?? const [];
      final unpackedPages = <Map<String, dynamic>>[];
      for (final pgRaw in rawPages.whereType<Map<String, dynamic>>()) {
        final pgCopy = Map<String, dynamic>.from(pgRaw);
        final imgPath =
            await unpackMediaFile(pgRaw['image_path'] as String?, pagesDir) ??
                '';
        final origPath = await unpackMediaFile(
              pgRaw['original_image_path'] as String?,
              pagesDir,
            ) ??
            imgPath;
        pgCopy['image_path'] = imgPath;
        pgCopy['original_image_path'] = origPath;
        unpackedPages.add(pgCopy);
      }
      docCopy['pages'] = unpackedPages;

      final restoredDoc = PendingUpload.fromJson(docCopy);
      mergedDocuments.insert(0, restoredDoc);
      existingDocIds.add(restoredDoc.id);
      restoredDocsCount++;
    }

    // 3. Restore Vault Documents
    final restoredVaultDocs = <PendingUpload>[];
    final rawVaultDocs = manifest['vault_documents'] as List<dynamic>? ?? const [];
    for (var i = 0; i < rawVaultDocs.length; i++) {
      final raw = rawVaultDocs[i];
      if (raw is! Map<String, dynamic>) continue;
      final docCopy = Map<String, dynamic>.from(raw);
      docCopy['file_path'] =
          await unpackMediaFile(raw['file_path'] as String?, docsDir) ?? '';
      docCopy['thumbnail_path'] =
          await unpackMediaFile(raw['thumbnail_path'] as String?, pagesDir);
      docCopy['docx_path'] =
          await unpackMediaFile(raw['docx_path'] as String?, exportsDir);
      docCopy['xlsx_path'] =
          await unpackMediaFile(raw['xlsx_path'] as String?, exportsDir);

      final rawPages = raw['pages'] as List<dynamic>? ?? const [];
      final unpackedPages = <Map<String, dynamic>>[];
      for (final pgRaw in rawPages.whereType<Map<String, dynamic>>()) {
        final pgCopy = Map<String, dynamic>.from(pgRaw);
        final imgPath =
            await unpackMediaFile(pgRaw['image_path'] as String?, pagesDir) ??
                '';
        final origPath = await unpackMediaFile(
              pgRaw['original_image_path'] as String?,
              pagesDir,
            ) ??
            imgPath;
        pgCopy['image_path'] = imgPath;
        pgCopy['original_image_path'] = origPath;
        unpackedPages.add(pgCopy);
      }
      docCopy['pages'] = unpackedPages;
      restoredVaultDocs.add(PendingUpload.fromJson(docCopy));
    }

    // 4. Restore SQLite FTS4 OCR records
    final rawOcrRecords = manifest['ocr_records'] as List<dynamic>? ?? const [];
    if (rawOcrRecords.isNotEmpty) {
      await _searchService.importRecords(
        rawOcrRecords.whereType<Map<String, dynamic>>().toList(),
      );
    }

    return (
      mergedDocuments: mergedDocuments,
      mergedFolders: mergedFolders,
      restoredVaultDocuments: restoredVaultDocs,
      stats: BackupRestoreResult(
        restoredDocuments: restoredDocsCount,
        restoredFolders: restoredFoldersCount,
        skippedDuplicates: skippedDuplicatesCount,
        restoredVaultDocuments: restoredVaultDocs.length,
      ),
    );
  }
}

Uint8List _buildInnerArchiveInIsolate(
  Map<String, dynamic> manifest,
  Map<String, String> mediaFilesToPack,
) {
  final archive = Archive();
  final manifestBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );

  for (final entry in mediaFilesToPack.entries) {
    final file = File(entry.value);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw Exception('فشل ضغط أرشيف النسخة الاحتياطية.');
  }
  return Uint8List.fromList(encoded);
}
