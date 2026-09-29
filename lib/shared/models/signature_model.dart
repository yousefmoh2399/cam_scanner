class SignatureModel {
  const SignatureModel({
    required this.id,
    required this.filePath,
    required this.createdAt,
  });

  final String id;
  final String filePath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SignatureModel.fromJson(Map<String, dynamic> json) {
    return SignatureModel(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
