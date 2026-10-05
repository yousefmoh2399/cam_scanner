import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/models/scan_session.dart';
import '../../../shared/services/local_media_storage_service.dart';

class LocalDocumentStore {
  static const _pendingUploadsKey = 'pending_uploads';
  static const _scanDraftKey = 'scan_draft';

  Future<void> initialize() async {
    await getPendingDirectory();
    await getDraftsDirectory();
    await getDownloadsDirectory();
    await getSavedSessionsDirectory();
  }

  Future<Directory> _appDirectory() =>
      path_provider.getApplicationDocumentsDirectory();

  Future<Directory> getPendingDirectory() async {
    final directory = Directory(
      path.join((await _appDirectory()).path, 'pending'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> getDraftsDirectory() async {
    final directory = Directory(
      path.join((await _appDirectory()).path, 'drafts'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> getSavedSessionsDirectory() async {
    final directory = Directory(
      path.join((await _appDirectory()).path, 'saved_sessions'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> getDownloadsDirectory() async {
    return const LocalMediaStorageService().scansDirectory();
  }

  Future<List<PendingUpload>> loadPendingUploads() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_pendingUploadsKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final uploads = decoded
        .cast<Map<String, dynamic>>()
        .map(PendingUpload.fromJson)
        .toList();

    var updated = false;
    final validUploads = <PendingUpload>[];
    for (final upload in uploads) {
      final repaired = await _repairPendingUploadPath(upload);
      if (repaired.filePath != upload.filePath ||
          repaired.fileSize != upload.fileSize) {
        updated = true;
      }
      if (File(repaired.filePath).existsSync() ||
          repaired.pages.any((p) => File(p.imagePath).existsSync())) {
        validUploads.add(repaired);
      } else {
        updated = true;
      }
    }

    if (updated) {
      await _savePendingUploads(validUploads);
    }

    return validUploads;
  }

  Future<void> _savePendingUploads(List<PendingUpload> uploads) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _pendingUploadsKey,
      jsonEncode(uploads.map((upload) => upload.toJson()).toList()),
    );
  }

  Future<void> savePendingUpload(PendingUpload doc) async {
    final current = await loadPendingUploads();
    final filtered = current.where((u) => u.id != doc.id).toList();
    await _savePendingUploads([doc, ...filtered]);
  }

  Future<PendingUpload> createPendingUpload({
    required String fileName,
    required Uint8List pdfBytes,
    required int pageCount,
    List<ScanPage> pages = const [],
    String? saveDirectoryPath,
  }) async {
    final id = const Uuid().v4();
    final sanitizedName = sanitizePdfName(fileName);
    final file = await _writePendingUploadFile(
      id: id,
      sanitizedName: sanitizedName,
      pdfBytes: pdfBytes,
      preferredDirectoryPath: saveDirectoryPath,
    );

    // Persist individual page images in saved_sessions/<id>/ so the document can
    // be reopened, edited, signed, or exported to Word/Excel anytime without re-scanning.
    final persistedPages = <ScanPage>[];
    String? thumbnailPath;
    if (pages.isNotEmpty) {
      final savedDir = await getSavedSessionsDirectory();
      final docSessionDir = Directory(path.join(savedDir.path, id));
      await docSessionDir.create(recursive: true);

      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final srcFile = File(page.imagePath);
        String targetImagePath = page.imagePath;
        if (await srcFile.exists()) {
          targetImagePath = path.join(docSessionDir.path, 'page_${i}_${page.id}.jpg');
          await srcFile.copy(targetImagePath);
        }

        String? targetOrigPath = page.originalPath;
        if (page.originalPath != null && File(page.originalPath!).existsSync()) {
          targetOrigPath = path.join(docSessionDir.path, 'raw_${i}_${page.id}.jpg');
          await File(page.originalPath!).copy(targetOrigPath);
        }

        final persistedPage = page.copyWith(
          imagePath: targetImagePath,
          originalPath: targetOrigPath,
        );
        persistedPages.add(persistedPage);
        if (i == 0) {
          thumbnailPath = targetImagePath;
        }
      }
    }

    final upload = PendingUpload(
      id: id,
      fileName: sanitizedName,
      filePath: file.path,
      pageCount: pageCount,
      fileSize: await file.length(),
      createdAt: DateTime.now(),
      pages: persistedPages,
      thumbnailPath: thumbnailPath,
      status: LocalDocumentStatus.saved,
    );

    final items = await loadPendingUploads();
    await _savePendingUploads([upload, ...items]);
    return upload;
  }

  Future<PendingUpload> updateDocument(PendingUpload updatedDoc) async {
    final items = await loadPendingUploads();
    final next = items.map((doc) => doc.id == updatedDoc.id ? updatedDoc : doc).toList();
    await _savePendingUploads(next);
    return updatedDoc;
  }

  Future<PendingUpload> renameDocument(String id, String newName) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((doc) => doc.id == id);
    if (idx == -1) throw StateError('المستند غير موجود');
    final sanitized = sanitizePdfName(newName);
    final updated = items[idx].copyWith(fileName: sanitized);
    items[idx] = updated;
    await _savePendingUploads(items);
    return updated;
  }

  Future<File> _writePendingUploadFile({
    required String id,
    required String sanitizedName,
    required Uint8List pdfBytes,
    required String? preferredDirectoryPath,
  }) async {
    final pendingDirectory = await getPendingDirectory();
    await pendingDirectory.create(recursive: true);
    final pendingFile = File(
      path.join(pendingDirectory.path, '${id}_$sanitizedName'),
    );
    await pendingFile.writeAsBytes(pdfBytes, flush: true);

    // التحقق الصريح من سلامة بايتات الـ PDF
    final headerBytes = await pendingFile.openRead(0, 5).first;
    final headerString = String.fromCharCodes(headerBytes);
    if (headerString != '%PDF-') {
      await pendingFile.delete();
      throw Exception('الملف الناتج تالف وليس بصيغة PDF صحيحة.');
    }

    final candidateDirectories = <Directory>[];
    if (preferredDirectoryPath != null &&
        preferredDirectoryPath.trim().isNotEmpty) {
      candidateDirectories.add(
        Directory(path.join(preferredDirectoryPath.trim(), 'Scans')),
      );
    }
    candidateDirectories.add(await getDownloadsDirectory());
    for (final directory in candidateDirectories) {
      try {
        await directory.create(recursive: true);
        final file = File(path.join(directory.path, '${id}_$sanitizedName'));
        await file.writeAsBytes(pdfBytes, flush: true);
        break;
      } catch (_) {}
    }

    return pendingFile;
  }

  Future<void> removePendingUpload(String id) async {
    final items = await loadPendingUploads();
    final target = items.where((upload) => upload.id == id).toList();
    for (final upload in target) {
      final file = File(upload.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      if (upload.docxPath != null) {
        final docxFile = File(upload.docxPath!);
        if (await docxFile.exists()) await docxFile.delete();
      }
      if (upload.xlsxPath != null) {
        final xlsxFile = File(upload.xlsxPath!);
        if (await xlsxFile.exists()) await xlsxFile.delete();
      }
      final savedDir = await getSavedSessionsDirectory();
      final docSessionDir = Directory(path.join(savedDir.path, upload.id));
      if (await docSessionDir.exists()) {
        await docSessionDir.delete(recursive: true);
      }
    }
    await _savePendingUploads(
      items.where((upload) => upload.id != id).toList(),
    );
  }

  Future<PendingUpload> _repairPendingUploadPath(PendingUpload upload) async {
    var resolvedPages = <ScanPage>[];
    for (final page in upload.pages) {
      final absImg = await _toAbsolutePath(page.imagePath);
      final absOrig = page.originalPath != null
          ? await _toAbsolutePath(page.originalPath!)
          : null;
      if (File(absImg).existsSync()) {
        resolvedPages.add(page.copyWith(imagePath: absImg, originalPath: absOrig));
      }
    }

    String? resolvedThumb = upload.thumbnailPath != null
        ? await _toAbsolutePath(upload.thumbnailPath!)
        : (resolvedPages.isNotEmpty ? resolvedPages.first.imagePath : null);
    if (resolvedThumb != null && !File(resolvedThumb).existsSync()) {
      resolvedThumb = resolvedPages.isNotEmpty ? resolvedPages.first.imagePath : null;
    }

    final currentFile = File(upload.filePath);
    if (await currentFile.exists()) {
      return upload.copyWith(
        pages: resolvedPages,
        thumbnailPath: resolvedThumb,
      );
    }

    final pendingDirectory = await getPendingDirectory();
    final repairedPath = path.join(
      pendingDirectory.path,
      path.basename(upload.filePath),
    );
    final repairedFile = File(repairedPath);
    if (!await repairedFile.exists()) {
      return upload.copyWith(
        pages: resolvedPages,
        thumbnailPath: resolvedThumb,
      );
    }

    return upload.copyWith(
      filePath: repairedPath,
      fileSize: await repairedFile.length(),
      pages: resolvedPages,
      thumbnailPath: resolvedThumb,
    );
  }

  Future<String> _toRelativePath(String fullPath) async {
    if (fullPath.isEmpty) return fullPath;
    final appDir = await _appDirectory();
    final appPath = appDir.path;
    if (fullPath.startsWith(appPath)) {
      var relative = fullPath.substring(appPath.length);
      if (relative.startsWith('/') || relative.startsWith('\\')) {
        relative = relative.substring(1);
      }
      return relative.replaceAll('\\', '/');
    }
    final draftsIndex = fullPath.indexOf('drafts');
    if (draftsIndex != -1) {
      return fullPath.substring(draftsIndex).replaceAll('\\', '/');
    }
    final savedIndex = fullPath.indexOf('saved_sessions');
    if (savedIndex != -1) {
      return fullPath.substring(savedIndex).replaceAll('\\', '/');
    }
    return fullPath;
  }

  Future<String> _toAbsolutePath(String storedPath) async {
    if (storedPath.isEmpty) return storedPath;
    final appDir = await _appDirectory();

    if (File(storedPath).existsSync()) {
      return storedPath;
    }

    final resolvedDirect = path.join(appDir.path, storedPath);
    if (File(resolvedDirect).existsSync()) {
      return resolvedDirect;
    }

    for (final folder in const ['drafts', 'saved_sessions', 'pending']) {
      final idx = storedPath.indexOf(folder);
      if (idx != -1) {
        final subPath = storedPath.substring(idx);
        final migratedPath = path.join(appDir.path, subPath);
        if (File(migratedPath).existsSync()) {
          return migratedPath;
        }
      }
    }

    return resolvedDirect;
  }

  Future<void> saveDraft(ScanSession session) async {
    final preferences = await SharedPreferences.getInstance();
    final relativePages = await Future.wait(
      session.pages.map((page) async {
        final relImage = await _toRelativePath(page.imagePath);
        final relOrig = page.originalPath != null
            ? await _toRelativePath(page.originalPath!)
            : null;
        return page.copyWith(
          imagePath: relImage,
          originalPath: relOrig,
        );
      }),
    );
    final relativeSession = session.copyWith(pages: relativePages);
    await preferences.setString(_scanDraftKey, jsonEncode(relativeSession.toJson()));
  }

  Future<ScanSession?> loadDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_scanDraftKey);
    if (raw == null || raw.isEmpty) return null;

    final session = ScanSession.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    var migrated = false;
    final resolvedPages = <ScanPage>[];

    for (final page in session.pages) {
      final absImagePath = await _toAbsolutePath(page.imagePath);
      final absOriginalPath = page.originalPath != null
          ? await _toAbsolutePath(page.originalPath!)
          : null;

      if (absImagePath != page.imagePath || absOriginalPath != page.originalPath) {
        migrated = true;
      }

      if (File(absImagePath).existsSync()) {
        resolvedPages.add(
          page.copyWith(
            imagePath: absImagePath,
            originalPath: absOriginalPath,
          ),
        );
      }
    }

    if (resolvedPages.isEmpty) {
      await clearDraft();
      return null;
    }

    final resolvedSession = session.copyWith(pages: resolvedPages);
    if (migrated || resolvedPages.length != session.pages.length) {
      await saveDraft(resolvedSession);
    }
    return resolvedSession;
  }

  Future<void> clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_scanDraftKey);
  }

  Future<String> savePageBytes({
    required String sessionId,
    required String pageId,
    required Uint8List bytes,
  }) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    await sessionDirectory.create(recursive: true);
    final filePath = path.join(sessionDirectory.path, '$pageId.jpg');
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  Future<String> savePageFile({
    required String sessionId,
    required String pageId,
    required String sourcePath,
  }) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    await sessionDirectory.create(recursive: true);
    final filePath = path.join(sessionDirectory.path, '$pageId.jpg');
    final sourceFile = File(sourcePath);
    if (sourcePath != filePath && await sourceFile.exists()) {
      await sourceFile.copy(filePath);
    }
    return filePath;
  }

  Future<String> importRawScanFile({
    required String sessionId,
    required String sourcePath,
  }) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    await sessionDirectory.create(recursive: true);

    final extension = path.extension(sourcePath).trim().isEmpty
        ? '.jpg'
        : path.extension(sourcePath);
    final filePath = path.join(
      sessionDirectory.path,
      'raw_${const Uuid().v4()}$extension',
    );
    final copiedFile = await File(sourcePath).copy(filePath);
    return copiedFile.path;
  }

  Future<void> clearSessionFiles(String sessionId) async {
    final draftsDirectory = await getDraftsDirectory();
    final sessionDirectory = Directory(
      path.join(draftsDirectory.path, sessionId),
    );
    if (await sessionDirectory.exists()) {
      await sessionDirectory.delete(recursive: true);
    }
    await purgeOrphanDrafts();
  }

  Future<void> deletePageFile(String imagePath, {String? originalPath}) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
    if (originalPath != null && originalPath != imagePath) {
      final orig = File(originalPath);
      if (await orig.exists()) {
        await orig.delete();
      }
    }
  }

  Future<void> purgeOrphanDrafts() async {
    try {
      final draftsDir = await getDraftsDirectory();
      if (!await draftsDir.exists()) return;
      final now = DateTime.now();
      final entities = draftsDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          final name = path.basename(entity.path);
          if (name.startsWith('preview_') ||
              name.startsWith('full_warp_') ||
              name.startsWith('full_filtered_') ||
              name.startsWith('full_rot_') ||
              name.startsWith('rot_') ||
              name.startsWith('raw_')) {
            try {
              // Safety: Never delete files created or modified in the last 2 hours.
              // This protects in-progress scans, batch items, and active review sessions.
              final stat = entity.statSync();
              if (now.difference(stat.modified).inHours < 2) {
                continue;
              }
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalDocumentStore] purgeOrphanDrafts error: $e');
    }
  }

  // ─── Trash / Soft-Delete ────────────────────────────────────────────────────

  /// Loads only active (non-deleted) documents. Existing behavior is preserved.
  /// Pass includeTrash=true to get ALL docs including deleted.
  Future<List<PendingUpload>> loadPendingUploadsFiltered({bool includeTrash = false}) async {
    final all = await loadPendingUploads();
    if (includeTrash) return all;
    return all.where((d) => !d.isDeleted).toList();
  }

  /// Loads ONLY trash items (deletedAt != null).
  Future<List<PendingUpload>> loadTrashUploads() async {
    final all = await loadPendingUploads();
    return all.where((d) => d.isDeleted).toList();
  }

  /// Soft-delete: sets deletedAt = now. Document stays in storage.
  Future<void> moveToTrash(String id) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(deletedAt: DateTime.now());
    await _savePendingUploads(items);
  }

  /// Restores a trashed document back to active.
  Future<void> restoreFromTrash(String id) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(clearDeletedAt: true);
    await _savePendingUploads(items);
  }

  /// Permanently deletes files from disk and removes from storage.
  Future<void> permanentlyDelete(String id) async {
    await removePendingUpload(id); // existing method handles file deletion
  }

  /// Clears all items in trash permanently.
  Future<void> emptyTrash() async {
    final items = await loadPendingUploads();
    final trashItems = items.where((d) => d.isDeleted).toList();
    for (final item in trashItems) {
      await removePendingUpload(item.id);
    }
  }

  /// Auto-purges trash items older than 30 days.
  Future<void> purgeExpiredTrash() async {
    final items = await loadPendingUploads();
    final now = DateTime.now();
    final expired = items.where((d) {
      if (d.deletedAt == null) return false;
      return now.difference(d.deletedAt!).inDays >= 30;
    }).toList();
    for (final item in expired) {
      await removePendingUpload(item.id);
    }
  }

  // ─── Favorite / Tags / Category / Expiry / EXIF ────────────────────────────

  /// Toggles favorite state.
  Future<void> toggleFavorite(String id) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(isFavorite: !items[idx].isFavorite);
    await _savePendingUploads(items);
  }

  /// Sets document tags.
  Future<void> updateTags(String id, List<String> tags) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(tags: tags);
    await _savePendingUploads(items);
  }

  /// Sets document category.
  Future<void> updateCategory(String id, String? category) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(category: category);
    await _savePendingUploads(items);
  }

  /// Sets document expiry reminder date.
  Future<void> setExpiryDate(String id, DateTime? date) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(
      expiryDate: date,
      clearExpiryDate: date == null,
    );
    await _savePendingUploads(items);
  }

  /// Marks document as EXIF-clean.
  Future<void> markAsExifClean(String id) async {
    final items = await loadPendingUploads();
    final idx = items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(isExifClean: true);
    await _savePendingUploads(items);
  }
}
