import 'document_paper_size.dart';
import 'image_filter_type.dart';

typedef ScannedPage = ScanPage;

class ScanPage {
  ScanPage({
    String? id,
    required this.imagePath,
    DateTime? createdAt,
    this.paperSize = DocumentPaperSize.auto,
    String? originalPath,
    String? originalImagePath,
    this.corners,
    ImageFilterType? filter,
    String? filterName,
    this.quarterTurns = 0,
  })  : id = id ?? 'pg_${DateTime.now().microsecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now(),
        originalPath = originalPath ?? originalImagePath ?? imagePath,
        filter = filter ??
            (filterName != null
                ? ImageFilterType.fromKey(filterName)
                : ImageFilterType.enhance);

  final String id;
  final String imagePath;
  final DateTime createdAt;
  final DocumentPaperSize paperSize;

  /// Path to the untouched raw camera capture file.
  final String? originalPath;

  String? get originalImagePath => originalPath;

  /// 8 normalized corner coordinates [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y].
  final List<double>? corners;

  /// Active filter applied to the page.
  final ImageFilterType filter;

  /// Number of 90-degree counter-clockwise turns applied.
  final int quarterTurns;

  ScanPage copyWith({
    String? id,
    String? imagePath,
    DateTime? createdAt,
    DocumentPaperSize? paperSize,
    String? originalPath,
    String? originalImagePath,
    List<double>? corners,
    ImageFilterType? filter,
    int? quarterTurns,
  }) {
    return ScanPage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      paperSize: paperSize ?? this.paperSize,
      originalPath: originalPath ?? originalImagePath ?? this.originalPath,
      corners: corners ?? this.corners,
      filter: filter ?? this.filter,
      quarterTurns: quarterTurns ?? this.quarterTurns,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
      'paperSize': paperSize.name,
      if (originalPath != null) 'originalPath': originalPath,
      if (corners != null) 'corners': corners,
      'filter': filter.nativeKey,
      'quarterTurns': quarterTurns,
    };
  }

  factory ScanPage.fromJson(Map<String, dynamic> json) {
    final imgPath =
        (json['imagePath'] ?? json['image_path'] ?? '') as String;
    final origPath =
        (json['originalPath'] ?? json['original_image_path']) as String?;
    return ScanPage(
      id: (json['id'] as String?) ??
          'pg_${DateTime.now().microsecondsSinceEpoch}',
      imagePath: imgPath,
      createdAt: DateTime.tryParse(
            (json['createdAt'] ?? json['created_at'] ?? '') as String,
          ) ??
          DateTime.now(),
      paperSize: DocumentPaperSizeLabels.fromName(
        (json['paperSize'] ?? json['paper_size']) as String?,
      ),
      originalPath: origPath ?? imgPath,
      corners: (json['corners'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      filter: ImageFilterType.fromKey(
        (json['filter'] ?? json['filterName']) as String?,
      ),
      quarterTurns: (json['quarterTurns'] as num?)?.toInt() ?? 0,
    );
  }
}
