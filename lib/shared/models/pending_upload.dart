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
    this.deletedAt,
    this.isFavorite = false,
    this.tags = const [],
    this.category,
    this.expiryDate,
    this.isExifClean = true,
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
  final DateTime? deletedAt;
  final bool isFavorite;
  final List<String> tags;
  final String? category;
  final DateTime? expiryDate;
  final bool isExifClean;

  String get title => stripFileExtension(fileName);

  int get fileSizeBytes => fileSize;

  bool get isDeleted => deletedAt != null;

  int get daysRemainingInTrash {
    if (deletedAt == null) return 30;
    final diff = DateTime.now().difference(deletedAt!).inDays;
    return (30 - diff).clamp(0, 30);
  }

  int get effectivePageCount =>
      pageCount > 0 ? pageCount : (pages.isNotEmpty ? pages.length : 1);

  static bool isImageFilePath(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    final lower = path.trim().toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  String? get effectiveThumbnailPath {
    if (thumbnailPath != null &&
        thumbnailPath!.isNotEmpty &&
        isImageFilePath(thumbnailPath)) {
      return thumbnailPath;
    }
    for (final page in pages) {
      if (page.imagePath.isNotEmpty && isImageFilePath(page.imagePath)) {
        return page.imagePath;
      }
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
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool? isFavorite,
    List<String>? tags,
    String? category,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    bool? isExifClean,
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
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      isFavorite: isFavorite ?? this.isFavorite,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      isExifClean: isExifClean ?? this.isExifClean,
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
      if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      'isFavorite': isFavorite,
      'tags': tags,
      if (category != null) 'category': category,
      if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
      'isExifClean': isExifClean,
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
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'] as String)
          : null,
      isFavorite: json['isFavorite'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      category: json['category'] as String?,
      expiryDate: json['expiryDate'] != null
          ? DateTime.tryParse(json['expiryDate'] as String)
          : null,
      isExifClean: json['isExifClean'] as bool? ?? true,
    );
  }
}

typedef LocalDocument = PendingUpload;
typedef RemoteDocument = PendingUpload;
