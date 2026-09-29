import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:uuid/uuid.dart';

import '../../../shared/models/signature_model.dart';

/// Handles saving, loading, and deleting signature PNG files locally on-device.
/// Signatures are NEVER uploaded to the backend — they exist only in the
/// application's documents directory under the "signatures/" subfolder.
class SignatureStorageService {
  static const _metadataFileName = 'signatures_index_v2.json';

  Future<Directory> _signaturesDirectory() async {
    final appDir = await path_provider.getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, 'signatures'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _metadataFile() async {
    final dir = await _signaturesDirectory();
    return File(path.join(dir.path, _metadataFileName));
  }

  Future<List<SignatureModel>> loadAllSignatures() async {
    final file = await _metadataFile();
    if (!await file.exists()) return const [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      final signatures = list
          .cast<Map<String, dynamic>>()
          .map(SignatureModel.fromJson)
          .toList();

      // Filter out entries whose PNG file is missing (e.g. app reinstall)
      final valid = <SignatureModel>[];
      var needsUpdate = false;
      for (final sig in signatures) {
        if (File(sig.filePath).existsSync()) {
          valid.add(sig);
        } else {
          needsUpdate = true;
        }
      }
      if (needsUpdate) {
        await _saveIndex(valid);
      }
      // Newest first
      valid.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return valid;
    } catch (_) {
      return const [];
    }
  }

  Future<SignatureModel> saveSignature(Uint8List pngBytes) async {
    final id = const Uuid().v4();
    final dir = await _signaturesDirectory();
    final filePath = path.join(dir.path, '$id.png');
    await File(filePath).writeAsBytes(pngBytes, flush: true);

    final model = SignatureModel(
      id: id,
      filePath: filePath,
      createdAt: DateTime.now(),
    );

    final existing = await loadAllSignatures();
    await _saveIndex([model, ...existing]);
    return model;
  }

  Future<void> deleteSignature(String id) async {
    final all = await loadAllSignatures();
    final target = all.where((s) => s.id == id).toList();
    for (final sig in target) {
      final f = File(sig.filePath);
      if (await f.exists()) await f.delete();
    }
    await _saveIndex(all.where((s) => s.id != id).toList());
  }

  Future<void> _saveIndex(List<SignatureModel> signatures) async {
    final file = await _metadataFile();
    await file.writeAsString(
      jsonEncode(signatures.map((s) => s.toJson()).toList()),
    );
  }
}
