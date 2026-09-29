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
/// Preserves full metadata, PDF path, first-page thumbnail path, folder assignment, and
/// individual [ScanPage] items so any document can be reopened, edited, signed, or
/// exported to PDF/Word/Excel at any time.
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
    this.pages = const [],
    this.thumbnailPath,
    this.docxPath,
    this.xlsxPath,
    this.folderId,
    this.status = LocalDocumentStatus.saved,
  });

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
    return PendingUpload(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      pageCount: json['pageCount'] as int? ?? parsedPages.length,
      fileSize: json['fileSize'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pages: parsedPages,
      thumbnailPath: json['thumbnailPath'] as String?,
      docxPath: json['docxPath'] as String?,
      xlsxPath: json['xlsxPath'] as String?,
      folderId: json['folderId'] as String?,
      status: LocalDocumentStatus.fromName(json['status'] as String?),
    );
  }
}

typedef LocalDocument = PendingUpload;
typedef RemoteDocument = PendingUpload;
