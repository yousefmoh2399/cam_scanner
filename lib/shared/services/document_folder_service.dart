import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/document_folder.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final documentFolderServiceProvider = Provider<DocumentFolderService>(
  (ref) => DocumentFolderService(),
);

final documentFoldersProvider =
    AsyncNotifierProvider<DocumentFoldersNotifier, List<DocumentFolder>>(
  DocumentFoldersNotifier.new,
);

// ─── Notifier ────────────────────────────────────────────────────────────────

class DocumentFoldersNotifier extends AsyncNotifier<List<DocumentFolder>> {
  @override
  Future<List<DocumentFolder>> build() async {
    final service = ref.read(documentFolderServiceProvider);
    return service.loadFolders();
  }

  Future<void> reload() async {
    final service = ref.read(documentFolderServiceProvider);
    state = AsyncData(await service.loadFolders());
  }

  Future<DocumentFolder> createFolder(
    String name, {
    String? parentId,
    int? colorValue,
  }) async {
    final service = ref.read(documentFolderServiceProvider);
    final folder = await service.createFolder(
      name,
      parentId: parentId,
      colorValue: colorValue,
    );
    await reload();
    return folder;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final service = ref.read(documentFolderServiceProvider);
    await service.renameFolder(folderId, newName);
    await reload();
  }

  Future<void> deleteFolder(String folderId) async {
    final service = ref.read(documentFolderServiceProvider);
    await service.deleteFolder(folderId);
    await reload();
  }

  /// Move a document INTO a folder. Removes it from any other folder first.
  Future<void> moveDocumentToFolder(String documentId, String folderId) async {
    final service = ref.read(documentFolderServiceProvider);
    await service.moveDocumentToFolder(documentId, folderId);
    await reload();
  }

  /// Remove a document from its folder (move to root).
  Future<void> removeDocumentFromFolder(String documentId) async {
    final service = ref.read(documentFolderServiceProvider);
    await service.removeDocumentFromFolder(documentId);
    await reload();
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class DocumentFolderService {
  static const _key = 'document_folders_v1';
  static const _uuid = Uuid();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<DocumentFolder>> loadFolders() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(DocumentFolder.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveFolders(List<DocumentFolder> folders) async {
    final prefs = await _prefs();
    await prefs.setString(
      _key,
      jsonEncode(folders.map((f) => f.toJson()).toList()),
    );
  }

  Future<void> saveFoldersOrder(List<DocumentFolder> folders) async {
    await _saveFolders(folders);
  }

  Future<void> assignDocumentToFolder(
    String documentId,
    String? folderId,
  ) async {
    if (folderId == null || folderId.isEmpty) {
      await removeDocumentFromFolder(documentId);
    } else {
      await moveDocumentToFolder(documentId, folderId);
    }
  }

  Future<DocumentFolder> createFolder(
    String name, {
    String? parentId,
    int? colorValue,
  }) async {
    final folders = await loadFolders();
    final folder = DocumentFolder(
      id: _uuid.v4(),
      name: name.trim(),
      parentId: parentId,
      colorValue: colorValue,
      documentIds: [],
      createdAt: DateTime.now(),
    );
    folders.add(folder);
    await _saveFolders(folders);
    return folder;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final folders = await loadFolders();
    final idx = folders.indexWhere((f) => f.id == folderId);
    if (idx == -1) return;
    folders[idx] = folders[idx].copyWith(name: newName.trim());
    await _saveFolders(folders);
  }

  Future<void> deleteFolder(String folderId) async {
    final folders = await loadFolders();
    folders.removeWhere((f) => f.id == folderId);
    await _saveFolders(folders);
  }

  Future<void> moveDocumentToFolder(String documentId, String folderId) async {
    final folders = await loadFolders();
    for (var i = 0; i < folders.length; i++) {
      if (folders[i].documentIds.contains(documentId)) {
        final updated = List<String>.from(folders[i].documentIds)
          ..remove(documentId);
        folders[i] = folders[i].copyWith(documentIds: updated);
      }
    }
    final idx = folders.indexWhere((f) => f.id == folderId);
    if (idx != -1) {
      final updated = List<String>.from(folders[idx].documentIds)
        ..add(documentId);
      folders[idx] = folders[idx].copyWith(documentIds: updated);
    }
    await _saveFolders(folders);
  }

  Future<void> removeDocumentFromFolder(String documentId) async {
    final folders = await loadFolders();
    for (var i = 0; i < folders.length; i++) {
      if (folders[i].documentIds.contains(documentId)) {
        final updated = List<String>.from(folders[i].documentIds)
          ..remove(documentId);
        folders[i] = folders[i].copyWith(documentIds: updated);
      }
    }
    await _saveFolders(folders);
  }

  Future<String?> folderIdForDocument(String documentId) async {
    final folders = await loadFolders();
    for (final f in folders) {
      if (f.documentIds.contains(documentId)) return f.id;
    }
    return null;
  }
}
