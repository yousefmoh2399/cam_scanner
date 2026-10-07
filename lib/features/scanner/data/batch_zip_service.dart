import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/models/pending_upload.dart';

/// Service responsible for batch-exporting multiple documents and folders
/// into a single compressed .ZIP archive for cloudless offline backup & transfer.
class BatchZipService {
  BatchZipService._();
  static final BatchZipService instance = BatchZipService._();

  /// Compresses a collection of [PendingUpload] documents into a single .zip file.
  /// [onProgress] returns a value between 0.0 and 1.0 indicating completion.
  Future<File> createBatchZip({
    required List<PendingUpload> documents,
    String? customZipName,
    bool includePagesImages = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (documents.isEmpty) {
      throw ArgumentError('لا توجد مستندات محددة للتصدير');
    }

    onProgress?.call(0.05, 'تجهيز ملفات الأرشيف...');

    final archive = Archive();
    final usedFileNames = <String>{};

    final totalCount = documents.length;

    for (int i = 0; i < documents.length; i++) {
      final doc = documents[i];
      final currentProgress = 0.05 + ((i / totalCount) * 0.75);
      onProgress?.call(
        currentProgress,
        'جارٍ ضغط (${i + 1}/$totalCount): ${doc.title}...',
      );

      final pdfFile = File(doc.filePath);
      if (await pdfFile.exists()) {
        final pdfBytes = await pdfFile.readAsBytes();

        // Ensure unique filename inside zip
        String baseName = doc.fileName;
        if (!baseName.toLowerCase().endsWith('.pdf')) {
          baseName = '$baseName.pdf';
        }
        String entryName = baseName;
        int dup = 1;
        while (usedFileNames.contains(entryName)) {
          final rawWithoutExt = p.basenameWithoutExtension(baseName);
          entryName = '${rawWithoutExt}_$dup.pdf';
          dup++;
        }
        usedFileNames.add(entryName);

        final archiveFile = ArchiveFile(
          entryName,
          pdfBytes.length,
          pdfBytes,
        );
        archive.addFile(archiveFile);
      }

      // If requested, include raw page images in a subfolder for high-res archival
      if (includePagesImages && doc.pages.isNotEmpty) {
        final folderName = p.basenameWithoutExtension(doc.fileName);
        for (int pIdx = 0; pIdx < doc.pages.length; pIdx++) {
          final page = doc.pages[pIdx];
          final imgFile = File(page.imagePath);
          if (await imgFile.exists()) {
            final imgBytes = await imgFile.readAsBytes();
            final ext = p.extension(page.imagePath).isNotEmpty
                ? p.extension(page.imagePath)
                : '.jpg';
            final pageEntry = '$folderName/صفحة_${pIdx + 1}$ext';
            archive.addFile(ArchiveFile(pageEntry, imgBytes.length, imgBytes));
          }
        }
      }
    }

    onProgress?.call(0.85, 'إنشاء ملف المضغوط .zip النهائي...');

    // Run ZipEncoder in compute or directly
    final zipEncoder = ZipEncoder();
    final encodedBytes = await compute(
      (Archive arch) => zipEncoder.encode(arch),
      archive,
    );

    if (encodedBytes == null) {
      throw StateError('فشل تشفير أرشيف ZIP');
    }

    onProgress?.call(0.95, 'حفظ الأرشيف في الذاكرة المحلية...');

    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempDir.path, 'Exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final timestamp = DateTime.now();
    final formattedTime =
        '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}';
    final zipFileName = customZipName != null && customZipName.trim().isNotEmpty
        ? (customZipName.endsWith('.zip') ? customZipName : '$customZipName.zip')
        : 'أرشيف_لقطة_$formattedTime.zip';

    final outZipFile = File(p.join(exportDir.path, zipFileName));
    await outZipFile.writeAsBytes(encodedBytes, flush: true);

    onProgress?.call(1.0, 'اكتمل إنشاء الأرشيف بنجاح!');
    return outZipFile;
  }
}
