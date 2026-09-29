/// Model representing a local document folder.
/// Folders are stored locally (SharedPreferences) and reference
/// document IDs from the local scanned documents list.
class DocumentFolder {
  const DocumentFolder({
    required this.id,
    required this.name,
    required this.documentIds,
    required this.createdAt,
    this.parentId,
    this.colorValue,
  });

  final String id;
  final String name;

  /// Ordered list of local document IDs inside this folder.
  final List<String> documentIds;
  final DateTime createdAt;

  final String? parentId;
  final int? colorValue;

  DocumentFolder copyWith({
    String? id,
    String? name,
    List<String>? documentIds,
    DateTime? createdAt,
    String? parentId,
    int? colorValue,
    bool clearParentId = false,
    bool clearColorValue = false,
  }) {
    return DocumentFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      documentIds: documentIds ?? this.documentIds,
      createdAt: createdAt ?? this.createdAt,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'documentIds': documentIds,
        'createdAt': createdAt.toIso8601String(),
        if (parentId != null) 'parentId': parentId,
        if (colorValue != null) 'colorValue': colorValue,
      };

  factory DocumentFolder.fromJson(Map<String, dynamic> json) {
    return DocumentFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      documentIds: (json['documentIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      parentId: json['parentId'] as String?,
      colorValue: json['colorValue'] as int?,
    );
  }
}
