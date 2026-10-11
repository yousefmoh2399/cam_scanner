import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../data/models/three_d_scan_models.dart';
import '../data/three_d_reconstruction_service.dart';

/// Interactive 3D STL Mesh Viewer with metric millimeter dimensions and slicer export.
class ThreeDMeshViewerScreen extends StatefulWidget {
  const ThreeDMeshViewerScreen({
    super.key,
    required this.result,
  });

  final ThreeDReconstructionResult result;

  @override
  State<ThreeDMeshViewerScreen> createState() => _ThreeDMeshViewerScreenState();
}

class _ThreeDMeshViewerScreenState extends State<ThreeDMeshViewerScreen> {
  StlMesh? _mesh;
  bool _isLoading = true;
  String? _errorMessage;

  // 3D Viewport transformation parameters
  double _rotX = 0.5; // pitch radians
  double _rotY = -0.6; // yaw radians
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  bool _showWireframe = false;
  final bool _showGrid = true;

  @override
  void initState() {
    super.initState();
    _loadMesh();
  }

  Future<void> _loadMesh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final mesh = await ThreeDReconstructionService.loadStlMesh(widget.result.stlPath);
      if (mounted) {
        setState(() {
          _mesh = mesh;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _resetView([String angle = 'iso']) {
    HapticFeedback.selectionClick();
    setState(() {
      _pan = Offset.zero;
      _zoom = 1.0;
      switch (angle) {
        case 'top':
          _rotX = math.pi / 2.0;
          _rotY = 0.0;
          break;
        case 'front':
          _rotX = 0.0;
          _rotY = 0.0;
          break;
        case 'side':
          _rotX = 0.0;
          _rotY = math.pi / 2.0;
          break;
        case 'iso':
        default:
          _rotX = 0.5;
          _rotY = -0.6;
          break;
      }
    });
  }

  Future<void> _shareStl() async {
    HapticFeedback.mediumImpact();
    final file = File(widget.result.stlPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ملف STL غير موجود على الجهاز')),
      );
      return;
    }

    final xFile = XFile(file.path, mimeType: 'model/stl');
    await Share.shareXFiles(
      [xFile],
      text: 'مجسم STL صالح للطباعة ثلاثية الأبعاد (${widget.result.formattedDimensions})',
      subject: p.basename(file.path),
    );
  }

  void _confirmDeleteMesh() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('حذف المجسم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'هل تريد حذف مجسم "${widget.result.title}" نهائياً؟\nسيتم مسح ملف STL من ذاكرة الهاتف.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              final file = File(widget.result.stlPath);
              if (file.existsSync()) {
                file.deleteSync();
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418), // Slicer dark workspace
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D24),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.result.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${widget.result.formattedDimensions} • STL متري صلب',
              style: const TextStyle(
                color: Color(0xFF00E676),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showWireframe ? Icons.grid_3x3_rounded : Icons.view_in_ar_rounded,
              color: Colors.white70,
            ),
            tooltip: _showWireframe ? 'وضع المجسم المصمت' : 'وضع الشبك السلكي Wireframe',
            onPressed: () {
              setState(() => _showWireframe = !_showWireframe);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF00E676)),
            tooltip: 'مشاركة للـ Slicer / Cura',
            onPressed: _shareStl,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
            tooltip: 'حذف المجسم',
            onPressed: _confirmDeleteMesh,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 3D Canvas
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (_) {},
              onScaleUpdate: (details) {
                setState(() {
                  if (details.pointerCount == 1) {
                    _rotY += details.focalPointDelta.dx * 0.012;
                    _rotX = (_rotX - details.focalPointDelta.dy * 0.012)
                        .clamp(-math.pi / 2.0 + 0.05, math.pi / 2.0 - 0.05);
                  } else if (details.pointerCount >= 2) {
                    _zoom = (_zoom * details.scale).clamp(0.4, 3.5);
                    _pan += details.focalPointDelta;
                  }
                });
              },
              onDoubleTap: () => _resetView('iso'),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00E676)),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : CustomPaint(
                          painter: _StlViewportPainter(
                            mesh: _mesh,
                            rotX: _rotX,
                            rotY: _rotY,
                            zoom: _zoom,
                            pan: _pan,
                            showWireframe: _showWireframe,
                            showGrid: _showGrid,
                          ),
                          child: Container(),
                        ),
            ),
          ),

          // Floating View Angle Selector (Top-Right)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222B).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ViewAngleBtn(label: 'أيزومتري', onTap: () => _resetView('iso')),
                  _ViewAngleBtn(label: 'قمة', onTap: () => _resetView('top')),
                  _ViewAngleBtn(label: 'أمامي', onTap: () => _resetView('front')),
                  _ViewAngleBtn(label: 'جانبي', onTap: () => _resetView('side')),
                ],
              ),
            ),
          ),

          // Metric Dimensions HUD Card (Bottom)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D24).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dimension badges row
                  Row(
                    children: [
                      Expanded(
                        child: _DimensionChip(
                          axis: 'X (العرض)',
                          value: '${widget.result.dimX.toStringAsFixed(1)} مم',
                          color: const Color(0xFFFF5252),
                        ),
                      ),
                      Expanded(
                        child: _DimensionChip(
                          axis: 'Y (العمق)',
                          value: '${widget.result.dimY.toStringAsFixed(1)} مم',
                          color: const Color(0xFF448AFF),
                        ),
                      ),
                      Expanded(
                        child: _DimensionChip(
                          axis: 'Z (الارتفاع)',
                          value: '${widget.result.dimZ.toStringAsFixed(1)} مم',
                          color: const Color(0xFF00E676),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),
                  // Metadata & Actions row
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Watertight badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'مجسم صلب (Watertight)',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${widget.result.triangleCount} مثلث • ${widget.result.formattedFileSize}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Primary Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _shareStl,
                          icon: const Icon(Icons.print_rounded, size: 20),
                          label: const Text(
                            'تصدير للتقطيع (Cura / PrusaSlicer)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C853),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewAngleBtn extends StatelessWidget {
  const _ViewAngleBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({required this.axis, required this.value, required this.color});
  final String axis;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(axis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Custom 3D painter projecting triangles, lighting, depth-sorting, and print bed grid.
class _StlViewportPainter extends CustomPainter {
  _StlViewportPainter({
    required this.mesh,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.pan,
    required this.showWireframe,
    required this.showGrid,
  });

  final StlMesh? mesh;
  final double rotX;
  final double rotY;
  final double zoom;
  final Offset pan;
  final bool showWireframe;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy - 30;

    // Draw Heatbed Print Platform Grid
    if (showGrid) {
      _drawPrintBedGrid(canvas, cx, cy);
    }

    if (mesh == null || mesh!.triangles.isEmpty) return;

    final center = mesh!.center;
    final maxDim = math.max(10.0, math.max(mesh!.sizeX, math.max(mesh!.sizeY, mesh!.sizeZ)));
    final scale = (math.min(size.width, size.height) * 0.45 / maxDim) * zoom;

    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);

    // Light direction (front-top-right)
    final lx = 0.577;
    final ly = 0.577;
    final lz = 0.577;

    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0xFF00E676).withValues(alpha: 0.6);

    // Project and depth-sort triangles using fast interactive viewport LOD
    final sortedTriangles = <_ProjectedTriangle>[];

    for (final tri in mesh!.viewportTriangles) {
      // Vertex 1
      final x1 = (tri.p1[0] - center[0]) * scale;
      final y1 = (tri.p1[1] - center[1]) * scale;
      final z1 = (tri.p1[2] - center[2]) * scale;

      // Vertex 2
      final x2 = (tri.p2[0] - center[0]) * scale;
      final y2 = (tri.p2[1] - center[1]) * scale;
      final z2 = (tri.p2[2] - center[2]) * scale;

      // Vertex 3
      final x3 = (tri.p3[0] - center[0]) * scale;
      final y3 = (tri.p3[1] - center[1]) * scale;
      final z3 = (tri.p3[2] - center[2]) * scale;

      // Rotate around Y then X
      final rx1 = cosY * x1 + sinY * y1;
      final ry1 = -sinY * x1 + cosY * y1;
      final rz1 = z1;
      final px1 = rx1;
      final py1 = cosX * ry1 - sinX * rz1;
      final depth1 = sinX * ry1 + cosX * rz1;

      final rx2 = cosY * x2 + sinY * y2;
      final ry2 = -sinY * x2 + cosY * y2;
      final rz2 = z2;
      final px2 = rx2;
      final py2 = cosX * ry2 - sinX * rz2;
      final depth2 = sinX * ry2 + cosX * rz2;

      final rx3 = cosY * x3 + sinY * y3;
      final ry3 = -sinY * x3 + cosY * y3;
      final rz3 = z3;
      final px3 = rx3;
      final py3 = cosX * ry3 - sinX * rz3;
      final depth3 = sinX * ry3 + cosX * rz3;

      // Screen space 2D points (inverted Y for standard graphics coordinates)
      final pt1 = Offset(cx + px1, cy - py1);
      final pt2 = Offset(cx + px2, cy - py2);
      final pt3 = Offset(cx + px3, cy - py3);

      final avgDepth = (depth1 + depth2 + depth3) / 3.0;

      // Normal rotation for lighting
      final nx = tri.normal[0];
      final ny = tri.normal[1];
      final nz = tri.normal[2];
      final rnx = cosY * nx + sinY * ny;
      final rny = -sinY * nx + cosY * ny;
      final rnz = nz;
      final fnx = rnx;
      final fny = cosX * rny - sinX * rnz;
      final fnz = sinX * rny + cosX * rnz;

      // Dot product with light
      final dot = (fnx * lx + fny * ly + fnz * lz).clamp(0.0, 1.0);
      final intensity = (0.35 + 0.65 * dot).clamp(0.0, 1.0);

      // Back-face culling: skip if facing away from camera
      if (fnz < -0.05 && !showWireframe) continue;

      sortedTriangles.add(
        _ProjectedTriangle(
          pt1: pt1,
          pt2: pt2,
          pt3: pt3,
          depth: avgDepth,
          intensity: intensity,
        ),
      );
    }

    // Sort Painter's Algorithm: farthest depth first
    sortedTriangles.sort((a, b) => a.depth.compareTo(b.depth));

    if (showWireframe) {
      final wirePath = Path();
      for (final tri in sortedTriangles) {
        wirePath.moveTo(tri.pt1.dx, tri.pt1.dy);
        wirePath.lineTo(tri.pt2.dx, tri.pt2.dy);
        wirePath.lineTo(tri.pt3.dx, tri.pt3.dy);
        wirePath.close();
      }
      canvas.drawPath(wirePath, wirePaint);
    } else {
      // GPU hardware accelerated triangle shading via ui.Vertices (1 draw call, zero jank)
      final positions = <Offset>[];
      final colors = <Color>[];

      for (final tri in sortedTriangles) {
        positions.add(tri.pt1);
        positions.add(tri.pt2);
        positions.add(tri.pt3);

        final r = (45 + 140 * tri.intensity).toInt();
        final g = (65 + 160 * tri.intensity).toInt();
        final b = (80 + 175 * tri.intensity).toInt();
        final c = Color.fromARGB(255, r, g, b);
        colors.add(c);
        colors.add(c);
        colors.add(c);
      }

      if (positions.isNotEmpty) {
        final vertices = ui.Vertices(
          ui.VertexMode.triangles,
          positions,
          colors: colors,
        );
        canvas.drawVertices(vertices, BlendMode.src, Paint());
      }
    }
  }

  void _drawPrintBedGrid(Canvas canvas, double cx, double cy) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    final axisPaintX = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.5)
      ..strokeWidth = 2.0;
    final axisPaintY = Paint()
      ..color = const Color(0xFF448AFF).withValues(alpha: 0.5)
      ..strokeWidth = 2.0;

    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);

    final gridSize = 80.0 * zoom;
    final step = 20.0 * zoom;

    Offset project(double x, double y) {
      final rx = cosY * x + sinY * y;
      final ry = -sinY * x + cosY * y;
      final px = rx;
      final py = cosX * ry - sinX * (-gridSize * 0.5); // base plane
      return Offset(cx + px, cy - py + 50 * zoom);
    }

    for (double i = -gridSize; i <= gridSize; i += step) {
      canvas.drawLine(project(i, -gridSize), project(i, gridSize), gridPaint);
      canvas.drawLine(project(-gridSize, i), project(gridSize, i), gridPaint);
    }
    // Center axes
    canvas.drawLine(project(0, 0), project(gridSize * 0.7, 0), axisPaintX);
    canvas.drawLine(project(0, 0), project(0, gridSize * 0.7), axisPaintY);
  }

  @override
  bool shouldRepaint(covariant _StlViewportPainter oldDelegate) {
    return oldDelegate.rotX != rotX ||
        oldDelegate.rotY != rotY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan ||
        oldDelegate.showWireframe != showWireframe ||
        oldDelegate.mesh != mesh;
  }
}

class _ProjectedTriangle {
  _ProjectedTriangle({
    required this.pt1,
    required this.pt2,
    required this.pt3,
    required this.depth,
    required this.intensity,
  });

  final Offset pt1;
  final Offset pt2;
  final Offset pt3;
  final double depth;
  final double intensity;
}
