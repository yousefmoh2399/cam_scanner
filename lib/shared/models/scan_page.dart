import 'document_paper_size.dart';
import 'image_filter_type.dart';

class ScanPage {
  const ScanPage({
    required this.id,
    required this.imagePath,
    required this.createdAt,
    this.paperSize = DocumentPaperSize.auto,
    this.originalPath,
    this.corners,
    this.filter = ImageFilterType.enhance,
    this.quarterTurns = 0,
  });

  final String id;
  final String imagePath;
  final DateTime createdAt;
  final DocumentPaperSize paperSize;

  /// Path to the untouched raw camera capture file.
  final String? originalPath;

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
    List<double>? corners,
    ImageFilterType? filter,
    int? quarterTurns,
  }) {
    return ScanPage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      paperSize: paperSize ?? this.paperSize,
      originalPath: originalPath ?? this.originalPath,
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
    return ScanPage(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      paperSize: DocumentPaperSizeLabels.fromName(json['paperSize'] as String?),
      originalPath: json['originalPath'] as String?,
      corners: (json['corners'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      filter: ImageFilterType.fromKey(json['filter'] as String?),
      quarterTurns: (json['quarterTurns'] as num?)?.toInt() ?? 0,
    );
  }
}
