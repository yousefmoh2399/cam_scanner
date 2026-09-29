import 'package:uuid/uuid.dart';
import 'scan_page.dart';

class ScanSession {
  const ScanSession({
    required this.id,
    required this.createdAt,
    required this.pages,
  });

  final String id;
  final DateTime createdAt;
  final List<ScanPage> pages;

  factory ScanSession.create() {
    return ScanSession(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      pages: const [],
    );
  }

  ScanSession copyWith({
    String? id,
    DateTime? createdAt,
    List<ScanPage>? pages,
  }) {
    return ScanSession(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      pages: pages ?? this.pages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'pages': pages.map((page) => page.toJson()).toList(),
    };
  }

  factory ScanSession.fromJson(Map<String, dynamic> json) {
    return ScanSession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pages: (json['pages'] as List<dynamic>? ?? const [])
          .map((entry) => ScanPage.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}
