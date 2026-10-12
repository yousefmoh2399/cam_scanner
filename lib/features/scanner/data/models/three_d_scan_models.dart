import 'dart:io';

/// Represents a single captured photo during a 3D scan session.
class ThreeDScanPhoto {
  const ThreeDScanPhoto({
    required this.path,
    required this.elevationDeg,
    required this.azimuthDeg,
    this.isFlipped = false,
    required this.timestamp,
  });

  final String path;
  final double elevationDeg;
  final double azimuthDeg;
  final bool isFlipped;
  final DateTime timestamp;

  String get ringLabel {
    if (elevationDeg <= 20) return 'حلقة 15° (منخفضة)';
    if (elevationDeg <= 45) return 'حلقة 35° (متوسطة)';
    if (elevationDeg <= 70) return 'حلقة 60° (مرتفعة)';
    return 'حلقة 85° (قمة)';
  }
}

/// Configuration settings for the 3D Space Carving reconstruction engine.
class ThreeDReconstructionConfig {
  const ThreeDReconstructionConfig({
    this.voxelSizeMm = 1.4,
    this.consensusRatio = 0.40,
    this.isFlipScanEnabled = true,
    this.objectType = 'auto',
  });

  /// Voxel grid step size in real millimeters (e.g., 1.4 mm for balanced speed/detail).
  final double voxelSizeMm;

  /// Consensus voting ratio across camera views (35% - 45% for handheld scans).
  final double consensusRatio;

  /// Whether dual-session flip scan was performed to eliminate base occlusions.
  final bool isFlipScanEnabled;

  /// Target CAD synthesis preset: 'auto', 'smartphone', 'box', 'cylinder', 'freeform'
  final String objectType;
}

/// The metric 3D model result returned from the reconstruction engine.
class ThreeDReconstructionResult {
  const ThreeDReconstructionResult({
    required this.stlPath,
    required this.title,
    required this.vertexCount,
    required this.triangleCount,
    required this.dimX,
    required this.dimY,
    required this.dimZ,
    required this.isWatertight,
    required this.durationMs,
    required this.createdAt,
    required this.fileSizeBytes,
  });

  final String stlPath;
  final String title;
  final int vertexCount;
  final int triangleCount;
  final double dimX;
  final double dimY;
  final double dimZ;
  final bool isWatertight;
  final int durationMs;
  final DateTime createdAt;
  final int fileSizeBytes;

  String get formattedDimensions =>
      '${dimX.toStringAsFixed(1)} × ${dimY.toStringAsFixed(1)} × ${dimZ.toStringAsFixed(1)} مم';

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes بايت';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} ك.ب';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} م.ب';
  }

  factory ThreeDReconstructionResult.fromMap(Map<dynamic, dynamic> map, String title) {
    final stlPath = map['stlPath'] as String? ?? '';
    final file = File(stlPath);
    final size = file.existsSync() ? file.lengthSync() : 0;

    return ThreeDReconstructionResult(
      stlPath: stlPath,
      title: title,
      vertexCount: (map['vertexCount'] as num?)?.toInt() ?? 0,
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      dimX: (map['dimX'] as num?)?.toDouble() ?? 0.0,
      dimY: (map['dimY'] as num?)?.toDouble() ?? 0.0,
      dimZ: (map['dimZ'] as num?)?.toDouble() ?? 0.0,
      isWatertight: map['isWatertight'] as bool? ?? true,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.now(),
      fileSizeBytes: size,
    );
  }
}

/// In-memory parsed STL triangle mesh for 3D viewport rendering.
class StlMesh {
  StlMesh({
    required this.triangles,
    List<StlMeshTriangle>? viewportTriangles,
    required this.minBounds,
    required this.maxBounds,
  }) : viewportTriangles = viewportTriangles ?? triangles;

  final List<StlMeshTriangle> triangles;
  final List<StlMeshTriangle> viewportTriangles;
  final List<double> minBounds; // [x, y, z]
  final List<double> maxBounds; // [x, y, z]

  double get sizeX => maxBounds[0] - minBounds[0];
  double get sizeY => maxBounds[1] - minBounds[1];
  double get sizeZ => maxBounds[2] - minBounds[2];

  List<double> get center => [
        (minBounds[0] + maxBounds[0]) / 2.0,
        (minBounds[1] + maxBounds[1]) / 2.0,
        (minBounds[2] + maxBounds[2]) / 2.0,
      ];
}

class StlMeshTriangle {
  const StlMeshTriangle({
    required this.p1,
    required this.p2,
    required this.p3,
    required this.normal,
  });

  final List<double> p1;
  final List<double> p2;
  final List<double> p3;
  final List<double> normal;
}
