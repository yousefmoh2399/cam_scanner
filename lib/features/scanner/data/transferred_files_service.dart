import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_web_drop_service.dart';

enum TransferDirection {
  received,
  sent,
}

class TransferredFile {
  const TransferredFile({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileSize,
    required this.transferTime,
    required this.direction,
    required this.mimeType,
    this.deviceSource,
  });

  final String id;
  final String name;
  final String filePath;
  final int fileSize;
  final DateTime transferTime;
  final TransferDirection direction;
  final String mimeType;
  final String? deviceSource;

  String get formattedSize => SharedDropFile.formatBytes(fileSize);

  bool get isReceived => direction == TransferDirection.received;
  bool get isSent => direction == TransferDirection.sent;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filePath': filePath,
        'fileSize': fileSize,
        'transferTime': transferTime.toIso8601String(),
        'direction': direction.name,
        'mimeType': mimeType,
        'deviceSource': deviceSource,
      };

  factory TransferredFile.fromJson(Map<String, dynamic> json) {
    return TransferredFile(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int? ?? 0,
      transferTime: DateTime.tryParse(json['transferTime'] as String? ?? '') ??
          DateTime.now(),
      direction: json['direction'] == 'sent'
          ? TransferDirection.sent
          : TransferDirection.received,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      deviceSource: json['deviceSource'] as String?,
    );
  }
}

class TransferredFilesService {
  TransferredFilesService._();
  static final TransferredFilesService instance = TransferredFilesService._();

  static const String _indexFileName = 'transferred_files_index.json';
  List<TransferredFile> _cachedFiles = [];
  List<TransferredFile> get cachedFiles => List.unmodifiable(_cachedFiles);

  Future<Directory> _getTransferDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'scans', 'web_drop_transfers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _getIndexFile() async {
    final dir = await _getTransferDirectory();
    return File(p.join(dir.path, _indexFileName));
  }

  Future<List<TransferredFile>> loadFiles() async {
    try {
      final indexFile = await _getIndexFile();
      if (!await indexFile.exists()) {
        _cachedFiles = [];
        return [];
      }

      final content = await indexFile.readAsString();
      if (content.trim().isEmpty) {
        _cachedFiles = [];
        return [];
      }

      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      final files = list
          .map((e) => TransferredFile.fromJson(e as Map<String, dynamic>))
          .where((f) => File(f.filePath).existsSync())
          .toList();

      files.sort((a, b) => b.transferTime.compareTo(a.transferTime));
      _cachedFiles = files;
      return List.unmodifiable(files);
    } catch (e) {
      debugPrint('[TransferredFilesService] Error loading files: $e');
      _cachedFiles = [];
      return [];
    }
  }

  Future<void> _saveIndex(List<TransferredFile> files) async {
    try {
      final indexFile = await _getIndexFile();
      final jsonStr = jsonEncode(files.map((e) => e.toJson()).toList());
      await indexFile.writeAsString(jsonStr, flush: true);
      _cachedFiles = List.from(files);
    } catch (e) {
      debugPrint('[TransferredFilesService] Error saving index: $e');
    }
  }

  /// Records a file received from the computer or another mobile device
  Future<TransferredFile> recordReceivedFile({
    required String fileName,
    required List<int> bytes,
    String? deviceSource,
  }) async {
    final dir = await _getTransferDirectory();
    final cleanName =
        fileName.replaceAll(RegExp(r'[^\w\.\-\u0600-\u06FF]'), '_');
    final filePath = p.join(
      dir.path,
      'recv_${DateTime.now().millisecondsSinceEpoch}_$cleanName',
    );

    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    final item = TransferredFile(
      id: 'recv_${DateTime.now().millisecondsSinceEpoch}_${cleanName.hashCode}',
      name: cleanName,
      filePath: filePath,
      fileSize: bytes.length,
      transferTime: DateTime.now(),
      direction: TransferDirection.received,
      mimeType: lookupDropMimeType(cleanName),
      deviceSource: deviceSource ?? 'متصفح الكمبيوتر / Wi-Fi',
    );

    final current = await loadFiles();
    final updated = [item, ...current];
    await _saveIndex(updated);
    return item;
  }

  /// Records a file sent from the phone to computer
  Future<TransferredFile> recordSentFile({
    required String fileName,
    required String sourcePath,
  }) async {
    final file = File(sourcePath);
    final size = await file.length();

    final item = TransferredFile(
      id: 'sent_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode}',
      name: fileName,
      filePath: sourcePath,
      fileSize: size,
      transferTime: DateTime.now(),
      direction: TransferDirection.sent,
      mimeType: lookupDropMimeType(fileName),
      deviceSource: 'هاتفك (Web Drop)',
    );

    final current = await loadFiles();
    final updated = [
      item,
      ...current.where((f) => f.filePath != sourcePath),
    ];
    await _saveIndex(updated);
    return item;
  }

  Future<void> deleteFile(String id) async {
    final current = await loadFiles();
    final target = current.where((f) => f.id == id).firstOrNull;
    if (target != null) {
      try {
        final f = File(target.filePath);
        if (await f.exists()) {
          // If it's stored inside transfers folder, delete physical file
          final dir = await _getTransferDirectory();
          if (p.isWithin(dir.path, target.filePath)) {
            await f.delete();
          }
        }
      } catch (_) {}
    }

    final updated = current.where((f) => f.id != id).toList();
    await _saveIndex(updated);
  }

  Future<void> clearAll() async {
    final current = await loadFiles();
    final dir = await _getTransferDirectory();
    for (final f in current) {
      try {
        if (p.isWithin(dir.path, f.filePath)) {
          final file = File(f.filePath);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}
    }
    await _saveIndex([]);
  }

  /// Copies the file to the user's public device storage or downloads directory
  Future<String?> saveToDownloads(TransferredFile file) async {
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        // Standard Android Download directory
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        }
      }

      targetDir ??= await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();

      final outPath = p.join(targetDir.path, file.name);
      await File(file.filePath).copy(outPath);
      return outPath;
    } catch (e) {
      debugPrint('[TransferredFilesService] Error saving to downloads: $e');
      return null;
    }
  }
}
