import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/scanner/data/backup_restore_service.dart';
import '../../features/scanner/data/document_search_service.dart';
import '../../features/scanner/data/exif_scrubber_service.dart';
import '../../features/scanner/data/government_preset_service.dart';
import '../../features/scanner/data/local_document_store.dart';
import '../../features/scanner/data/ocr_service.dart';
import '../../features/scanner/data/office_exporter_service.dart';
import '../../features/scanner/data/pdf_builder_service.dart';
import '../../features/scanner/data/signature_storage_service.dart';
import '../../features/scanner/data/smart_field_extractor_service.dart';
import '../../features/scanner/data/vault_security_service.dart';
import '../../features/scanner/presentation/scan_session_controller.dart';
import '../models/pending_upload.dart';
import '../models/scan_session.dart';
import '../services/document_folder_service.dart';

export '../services/document_folder_service.dart';

// ─── Core Services ───────────────────────────────────────────────────────────

final localDocumentStoreProvider = Provider<LocalDocumentStore>(
  (ref) => LocalDocumentStore(),
);

final exifScrubberServiceProvider = Provider<ExifScrubberService>(
  (ref) => const ExifScrubberService(),
);

final governmentPresetServiceProvider = Provider<GovernmentPresetService>(
  (ref) => const GovernmentPresetService(),
);

final smartFieldExtractorServiceProvider = Provider<SmartFieldExtractorService>(
  (ref) => const SmartFieldExtractorService(),
);

final pdfBuilderServiceProvider = Provider<PdfBuilderService>(
  (ref) => PdfBuilderService(),
);

final ocrServiceProvider = Provider<OcrService>(
  (ref) => OcrService(),
);

final documentSearchServiceProvider = Provider<DocumentSearchService>(
  (ref) => DocumentSearchService(),
);

final vaultSecurityServiceProvider = Provider<VaultSecurityService>(
  (ref) => VaultSecurityService(),
);

final backupRestoreServiceProvider = Provider<BackupRestoreService>(
  (ref) => BackupRestoreService(
    securityService: ref.read(vaultSecurityServiceProvider),
    searchService: ref.read(documentSearchServiceProvider),
  ),
);

final officeExporterServiceProvider = Provider<OfficeExporterService>(
  (ref) => OfficeExporterService(
    pdfBuilderService: ref.read(pdfBuilderServiceProvider),
    ocrService: ref.read(ocrServiceProvider),
    searchService: ref.read(documentSearchServiceProvider),
  ),
);

final signatureStorageServiceProvider = Provider<SignatureStorageService>(
  (ref) => SignatureStorageService(),
);

// ─── Scan Session & Progress ─────────────────────────────────────────────────

final scanSaveProgressProvider = StateProvider<String>((ref) => '');

final scanSessionControllerProvider =
    AsyncNotifierProvider<ScanSessionController, ScanSession?>(
  ScanSessionController.new,
);

// ─── Local Documents (PendingUpload / Saved Scans) ───────────────────────────

final pendingUploadsControllerProvider =
    AsyncNotifierProvider<PendingUploadsController, List<PendingUpload>>(
  PendingUploadsController.new,
);

class PendingUploadsController extends AsyncNotifier<List<PendingUpload>> {
  @override
  Future<List<PendingUpload>> build() async {
    final store = ref.read(localDocumentStoreProvider);
    await store.initialize();
    await store.purgeExpiredTrash();
    return store.loadPendingUploadsFiltered(includeTrash: false);
  }

  Future<void> refresh() async {
    final store = ref.read(localDocumentStoreProvider);
    state = AsyncData(await store.loadPendingUploadsFiltered(includeTrash: false));
  }

  Future<void> addDocument(PendingUpload doc) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.savePendingUpload(doc);
    await refresh();
  }

  Future<void> deleteDocument(String id) => moveToTrash(id);

  Future<void> removeById(String id) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.removePendingUpload(id);
    await ref.read(documentSearchServiceProvider).removeDocument(id);
    await refresh();
  }

  Future<void> removeMultiple(Iterable<String> ids) async {
    final store = ref.read(localDocumentStoreProvider);
    final search = ref.read(documentSearchServiceProvider);
    for (final id in ids) {
      await store.removePendingUpload(id);
      await search.removeDocument(id);
    }
    await refresh();
  }

  Future<void> replaceAllDocuments(List<PendingUpload> docs) async {
    final store = ref.read(localDocumentStoreProvider);
    for (final doc in docs) {
      await store.savePendingUpload(doc);
    }
    await refresh();
  }

  Future<PendingUpload> renameDocument(String id, String newName) async {
    final store = ref.read(localDocumentStoreProvider);
    final updated = await store.renameDocument(id, newName);
    await refresh();
    return updated;
  }

  Future<PendingUpload> updateDocument(PendingUpload doc) async {
    final store = ref.read(localDocumentStoreProvider);
    final updated = await store.updateDocument(doc);
    await refresh();
    return updated;
  }

  Future<void> assignToFolder(String id, String? folderId) async {
    final store = ref.read(localDocumentStoreProvider);
    final docs = await store.loadPendingUploads();
    final idx = docs.indexWhere((d) => d.id == id);
    if (idx != -1) {
      final updated = docs[idx].copyWith(
        folderId: folderId,
        clearFolderId: folderId == null,
      );
      await store.updateDocument(updated);
    }
    await ref
        .read(documentFolderServiceProvider)
        .assignDocumentToFolder(id, folderId);
    await ref.read(documentFoldersProvider.notifier).reload();
    await refresh();
  }

  Future<void> updateExportPaths(
    String id, {
    String? docxPath,
    String? xlsxPath,
  }) async {
    final store = ref.read(localDocumentStoreProvider);
    final docs = await store.loadPendingUploads();
    final idx = docs.indexWhere((d) => d.id == id);
    if (idx != -1) {
      final updated = docs[idx].copyWith(
        docxPath: docxPath,
        xlsxPath: xlsxPath,
      );
      await store.updateDocument(updated);
      await refresh();
    }
  }

  /// Soft-delete → move to Trash
  Future<void> moveToTrash(String id) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.moveToTrash(id);
    await refresh();
  }

  /// Restore from Trash
  Future<void> restoreFromTrash(String id) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.restoreFromTrash(id);
    await refresh();
  }

  /// Permanently delete (from trash)
  Future<void> permanentlyDelete(String id) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.permanentlyDelete(id);
    await ref.read(documentSearchServiceProvider).removeDocument(id);
    await refresh();
  }

  /// Empty all trash
  Future<void> emptyTrash() async {
    final store = ref.read(localDocumentStoreProvider);
    await store.emptyTrash();
    await refresh();
  }

  /// Toggle favorite
  Future<void> toggleFavorite(String id) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.toggleFavorite(id);
    await refresh();
  }

  /// Update tags
  Future<void> updateTags(String id, List<String> tags) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.updateTags(id, tags);
    await refresh();
  }

  /// Update category
  Future<void> updateCategory(String id, String? category) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.updateCategory(id, category);
    await refresh();
  }

  /// Set expiry date
  Future<void> setExpiryDate(String id, DateTime? date) async {
    final store = ref.read(localDocumentStoreProvider);
    await store.setExpiryDate(id, date);
    await refresh();
  }
}

// ─── Trash Provider ───────────────────────────────────────────────────────────

final trashUploadsProvider = FutureProvider<List<PendingUpload>>((ref) async {
  // Watch pendingUploads so we refresh automatically when anything changes
  ref.watch(pendingUploadsControllerProvider);
  final store = ref.read(localDocumentStoreProvider);
  return store.loadTrashUploads();
});

// ─── User Preferences (Theme, View Mode, Sort Order, Auto-Save) ──────────────

enum DocumentSortOrder {
  newest,
  name,
  size;

  String get label => switch (this) {
        DocumentSortOrder.newest => 'الأحدث أولاً',
        DocumentSortOrder.name => 'حسب الاسم (أ-ي)',
        DocumentSortOrder.size => 'الأكبر حجماً',
      };
}

class LocalUserPreferences {
  const LocalUserPreferences({
    this.themeMode = ThemeMode.system,
    this.isGridView = true,
    this.sortOrder = DocumentSortOrder.newest,
    this.autoSaveAfterScan = false,
    this.scanSaveDirectoryPath,
    this.accentThemeId = 'default',
  });

  final ThemeMode themeMode;
  final bool isGridView;
  final DocumentSortOrder sortOrder;
  final bool autoSaveAfterScan;
  final String? scanSaveDirectoryPath;
  final String accentThemeId;

  bool get darkMode => themeMode == ThemeMode.dark;

  LocalUserPreferences copyWith({
    ThemeMode? themeMode,
    bool? isGridView,
    DocumentSortOrder? sortOrder,
    bool? autoSaveAfterScan,
    String? scanSaveDirectoryPath,
    String? accentThemeId,
  }) {
    return LocalUserPreferences(
      themeMode: themeMode ?? this.themeMode,
      isGridView: isGridView ?? this.isGridView,
      sortOrder: sortOrder ?? this.sortOrder,
      autoSaveAfterScan: autoSaveAfterScan ?? this.autoSaveAfterScan,
      scanSaveDirectoryPath:
          scanSaveDirectoryPath ?? this.scanSaveDirectoryPath,
      accentThemeId: accentThemeId ?? this.accentThemeId,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'isGridView': isGridView,
        'sortOrder': sortOrder.name,
        'autoSaveAfterScan': autoSaveAfterScan,
        if (scanSaveDirectoryPath != null)
          'scanSaveDirectoryPath': scanSaveDirectoryPath,
        'accentThemeId': accentThemeId,
      };

  factory LocalUserPreferences.fromJson(Map<String, dynamic> json) {
    final modeStr = json['themeMode'] as String?;
    final sortStr = json['sortOrder'] as String?;
    return LocalUserPreferences(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => ThemeMode.system,
      ),
      isGridView: json['isGridView'] as bool? ?? true,
      sortOrder: DocumentSortOrder.values.firstWhere(
        (s) => s.name == sortStr,
        orElse: () => DocumentSortOrder.newest,
      ),
      autoSaveAfterScan: json['autoSaveAfterScan'] as bool? ?? false,
      scanSaveDirectoryPath: json['scanSaveDirectoryPath'] as String?,
      accentThemeId: json['accentThemeId'] as String? ?? 'default',
    );
  }
}

final userPreferencesControllerProvider =
    AsyncNotifierProvider<UserPreferencesController, LocalUserPreferences>(
  UserPreferencesController.new,
);

class UserPreferencesController extends AsyncNotifier<LocalUserPreferences> {
  static const _prefsKey = 'local_scanner_preferences_v1';

  @override
  Future<LocalUserPreferences> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const LocalUserPreferences();
    }
    try {
      return LocalUserPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const LocalUserPreferences();
    }
  }

  Future<void> _save(LocalUserPreferences next) async {
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }

  Future<void> toggleThemeMode() async {
    final current = state.valueOrNull ?? const LocalUserPreferences();
    final nextMode = switch (current.themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.dark,
    };
    await _save(current.copyWith(themeMode: nextMode));
  }

  Future<void> toggleDarkMode() => toggleThemeMode();

  Future<void> setViewMode({required bool isGrid}) async {
    final current = state.valueOrNull ?? const LocalUserPreferences();
    await _save(current.copyWith(isGridView: isGrid));
  }

  Future<void> setSortOrder(DocumentSortOrder sortOrder) async {
    final current = state.valueOrNull ?? const LocalUserPreferences();
    await _save(current.copyWith(sortOrder: sortOrder));
  }

  Future<void> setAccentTheme(String themeId) async {
    final current = state.valueOrNull ?? const LocalUserPreferences();
    await _save(current.copyWith(accentThemeId: themeId));
  }
}
