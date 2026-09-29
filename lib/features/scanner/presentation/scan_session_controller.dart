import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/models/scan_session.dart';
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import '../data/pdf_builder_service.dart';

class ScanSessionController extends AsyncNotifier<ScanSession?> {
  void resetState() {
    state = const AsyncLoading();
  }

  @override
  Future<ScanSession?> build() async {
    return ref.read(localDocumentStoreProvider).loadDraft();
  }

  Future<void> ensureSession() async {
    if (state.valueOrNull != null) return;
    final session = ScanSession.create();
    await ref.read(localDocumentStoreProvider).saveDraft(session);
    state = AsyncData(session);
  }

  Future<void> addPage(ScanPage page) async {
    final session = state.valueOrNull ?? ScanSession.create();
    final updated = session.copyWith(pages: [...session.pages, page]);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> replacePage(String pageId, ScanPage newPage) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final currentPage = session.pages.firstWhere(
      (page) => page.id == pageId,
      orElse: () => newPage,
    );
    if (currentPage.imagePath != newPage.imagePath) {
      await ref
          .read(localDocumentStoreProvider)
          .deletePageFile(
            currentPage.imagePath,
            originalPath: currentPage.originalPath != newPage.originalPath
                ? currentPage.originalPath
                : null,
          );
    }

    final updated = session.copyWith(
      pages: session.pages
          .map((page) => page.id == pageId ? newPage : page)
          .toList(),
    );
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> rotatePage(String pageId) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final targetPage = session.pages.firstWhere((page) => page.id == pageId);
    final tempRotated = '${targetPage.imagePath}.rot.jpg';
    await NativeScannerBridge.rotateLeft(
      path: targetPage.imagePath,
      outPath: tempRotated,
    );
    final f = File(tempRotated);
    if (await f.exists()) {
      await f.rename(targetPage.imagePath);
    }
    await FileImage(File(targetPage.imagePath)).evict();
    final updated = session.copyWith(
      pages: session.pages.map((p) {
        if (p.id == pageId) {
          return p.copyWith(quarterTurns: (p.quarterTurns + 1) % 4);
        }
        return p;
      }).toList(),
    );
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> deletePage(String pageId) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final targetPage = session.pages.firstWhere((page) => page.id == pageId);
    await ref
        .read(localDocumentStoreProvider)
        .deletePageFile(targetPage.imagePath);
    final updatedPages = session.pages
        .where((page) => page.id != pageId)
        .toList();

    if (updatedPages.isEmpty) {
      await clearSession();
      return;
    }

    final updated = session.copyWith(pages: updatedPages);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> reorderPages(int oldIndex, int newIndex) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final items = [...session.pages];
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final updated = session.copyWith(pages: items);
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<void> updatePagePaperSize(
    String pageId,
    DocumentPaperSize paperSize,
  ) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final updated = session.copyWith(
      pages: session.pages
          .map(
            (page) =>
                page.id == pageId ? page.copyWith(paperSize: paperSize) : page,
          )
          .toList(),
    );
    await ref.read(localDocumentStoreProvider).saveDraft(updated);
    state = AsyncData(updated);
  }

  Future<PendingUpload> saveCurrentSession(
    String fileName, {
    String? saveDirectoryPath,
    bool applyEnhancement = false,
  }) async {
    final session = state.valueOrNull;
    if (session == null || session.pages.isEmpty) {
      throw Exception('لا توجد صفحات لحفظها.');
    }

    final pageCount = session.pages.length;
    final progressNotifier = ref.read(scanSaveProgressProvider.notifier);

    // ── Step 1: Build PDF ──
    progressNotifier.state = pageCount == 1
        ? 'جارٍ تجهيز الصفحة وبناء الملف...'
        : 'جارٍ تجهيز $pageCount صفحات وبناء الملف...';

    // Ensure all pages are <= 2048px and orientation == 1 via C++ OpenCV (~15ms)
    // so PdfBuilderService always hits its 0ms zero-decode fast path.
    for (final page in session.pages) {
      try {
        final file = File(page.imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (applyEnhancement || PdfBuilderService.needsNormalization(bytes)) {
            await NativeScannerBridge.applyFilter(
              path: page.imagePath,
              filter: applyEnhancement ? 'enhance' : 'original',
              outPath: page.imagePath,
              maxSide: 2048,
            );
          }
        }
      } catch (_) {
        // Fallback inside PdfBuilderService will handle if native call fails
      }
    }

    final pdfBytes = await ref
        .read(pdfBuilderServiceProvider)
        .buildPdf(
          imagePaths: session.pages.map((page) => page.imagePath).toList(),
          paperSizes: session.pages.map((page) => page.paperSize).toList(),
          applyEnhancement: false,
        );

    // ── Step 2: Write to disk & preserve session pages ──
    progressNotifier.state = 'جارٍ حفظ المستند والصفحات على الجهاز...';

    final pending = await ref
        .read(localDocumentStoreProvider)
        .createPendingUpload(
          fileName: fileName,
          pdfBytes: pdfBytes,
          pageCount: pageCount,
          pages: session.pages,
          saveDirectoryPath: saveDirectoryPath,
        );

    // ── Cleanup draft session files (saved copies live in saved_sessions/<id>/) ──
    progressNotifier.state = '';
    await ref.read(localDocumentStoreProvider).clearDraft();
    await ref.read(localDocumentStoreProvider).clearSessionFiles(session.id);
    state = const AsyncData(null);
    return pending;
  }

  /// Overwrites the page image on disk with [newImageBytes] (the composited
  /// JPEG after the signature has been applied) and refreshes the UI.
  Future<void> applySignatureToPage(
    String pageId,
    Uint8List newImageBytes,
  ) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final targetPage = session.pages.firstWhere(
      (page) => page.id == pageId,
      orElse: () => throw StateError('Page $pageId not found in session.'),
    );

    await File(targetPage.imagePath).writeAsBytes(newImageBytes, flush: true);
    await FileImage(File(targetPage.imagePath)).evict();

    state = AsyncData(session.copyWith(pages: [...session.pages]));
  }

  Future<void> clearSession() async {
    final session = state.valueOrNull;
    if (session != null) {
      await ref.read(localDocumentStoreProvider).clearSessionFiles(session.id);
    }
    await ref.read(localDocumentStoreProvider).clearDraft();
    state = const AsyncData(null);
  }

  Future<void> startNewEmptySession() async {
    await clearSession();
    await ensureSession();
  }

  Future<void> loadSavedDocumentIntoSession(PendingUpload doc) async {
    await clearSession();
    final session = ScanSession(
      id: doc.id,
      pages: [...doc.pages],
      createdAt: doc.createdAt,
    );
    await ref.read(localDocumentStoreProvider).saveDraft(session);
    state = AsyncData(session);
  }
}
