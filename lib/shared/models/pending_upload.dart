import 'dart:io';

import '../../core/utils/formatters.dart';
import 'scan_page.dart';

/// Local document lifecycle status (replaces server upload status).
enum LocalDocumentStatus {
  draft,
  saved,
  exporting;

  String get label => switch (this) {
        LocalDocumentStatus.draft => 'مسودة',
        LocalDocumentStatus.saved => 'محفوظ محلياً',
        LocalDocumentStatus.exporting => 'قيد التصدير',
      };

  static LocalDocumentStatus fromName(String? name) {
    return LocalDocumentStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => LocalDocumentStatus.saved,
    );
  }
}

/// Represents a locally stored scanned document (replaces PendingUpload & RemoteDocument).
class PendingUpload {
  PendingUpload({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    int? fileSize,
    required this.createdAt,
    this.pages = const [],
    this.thumbnailPath,
    this.docxPath,
    this.xlsxPath,
    this.folderId,
    String? fileType,
    Object? status = LocalDocumentStatus.saved,
  })  : fileSize = fileSize ??
            (filePath.isNotEmpty && File(filePath).existsSync()
                ? File(filePath).lengthSync()
                : 0),
        status = status is LocalDocumentStatus
            ? status
            : LocalDocumentStatus.fromName(status?.toString());

  final String id;
  final String fileName;
  final String filePath;
  final int pageCount;
  final int fileSize;
  final DateTime createdAt;
  final List<ScanPage> pages;
  final String? thumbnailPath;
  final String? docxPath;
  final String? xlsxPath;
  final String? folderId;
  final LocalDocumentStatus status;

  String get title => stripFileExtension(fileName);

  int get fileSizeBytes => fileSize;

  int get effectivePageCount =>
      pageCount > 0 ? pageCount : (pages.isNotEmpty ? pages.length : 1);

  String? get effectiveThumbnailPath {
    if (thumbnailPath != null && thumbnailPath!.isNotEmpty) {
      return thumbnailPath;
    }
    if (pages.isNotEmpty) {
      return pages.first.imagePath;
    }
    return null;
  }

  String? get previewImagePath => effectiveThumbnailPath;

  PendingUpload copyWith({
    String? id,
    String? fileName,
    String? filePath,
    int? pageCount,
    int? fileSize,
    DateTime? createdAt,
    List<ScanPage>? pages,
    String? thumbnailPath,
    String? docxPath,
    String? xlsxPath,
    String? folderId,
    bool clearFolderId = false,
    LocalDocumentStatus? status,
  }) {
    return PendingUpload(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      pageCount: pageCount ?? this.pageCount,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      pages: pages ?? this.pages,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      docxPath: docxPath ?? this.docxPath,
      xlsxPath: xlsxPath ?? this.xlsxPath,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'pageCount': pageCount,
      'fileSize': fileSize,
      'createdAt': createdAt.toIso8601String(),
      'pages': pages.map((p) => p.toJson()).toList(),
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      if (docxPath != null) 'docxPath': docxPath,
      if (xlsxPath != null) 'xlsxPath': xlsxPath,
      if (folderId != null) 'folderId': folderId,
      'status': status.name,
    };
  }

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    final parsedPages = (json['pages'] as List<dynamic>?)
            ?.map((e) => ScanPage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <ScanPage>[];
    final fPath =
        (json['filePath'] ?? json['file_path'] ?? '') as String;
    return PendingUpload(
      id: json['id'] as String,
      fileName: (json['fileName'] ?? json['file_name'] ?? 'document.pdf') as String,
      filePath: fPath,
      pageCount: (json['pageCount'] ?? json['page_count']) as int? ??
          parsedPages.length,
      fileSize: (json['fileSize'] ?? json['file_size']) as int? ?? 0,
      createdAt: DateTime.tryParse(
            (json['createdAt'] ?? json['created_at'] ?? '') as String,
          ) ??
          DateTime.now(),
      pages: parsedPages,
      thumbnailPath:
          (json['thumbnailPath'] ?? json['thumbnail_path']) as String?,
      docxPath: (json['docxPath'] ?? json['docx_path']) as String?,
      xlsxPath: (json['xlsxPath'] ?? json['xlsx_path']) as String?,
      folderId: (json['folderId'] ?? json['folder_id']) as String?,
      status: LocalDocumentStatus.fromName(json['status'] as String?),
    );
  }
}

typedef LocalDocument = PendingUpload;
typedef RemoteDocument = PendingUpload;
