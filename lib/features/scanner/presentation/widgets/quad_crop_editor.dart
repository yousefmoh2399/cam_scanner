import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Interactive 4-corner document boundary mesh editor.
///
/// Allows the user to fine-tune the 4 corners of the document quad
/// with touch dragging, visual guidelines, and an active magnifying loupe.
class QuadCropEditor extends StatefulWidget {
  const QuadCropEditor({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    required this.imageWidth,
    required this.imageHeight,
    required this.onCornersChanged,
  });

  final String imagePath;
  final List<double> initialCorners; // 8 normalized doubles [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
  final int imageWidth;
  final int imageHeight;
  final ValueChanged<List<double>> onCornersChanged;

  @override
  State<QuadCropEditor> createState() => _QuadCropEditorState();
}

class _QuadCropEditorState extends State<QuadCropEditor> {
  late List<double> _corners;
  int? _activeCornerIndex; // 0: TL, 1: TR, 2: BR, 3: BL
  Offset? _magnifierPos;

  @override
  void initState() {
    super.initState();
    _corners = List<double>.from(widget.initialCorners);
    if (_corners.length != 8) {
      _corners = [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95];
    }
  }

  @override
  void didUpdateWidget(covariant QuadCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCorners != widget.initialCorners &&
        widget.initialCorners.length == 8) {
      _corners = List<double>.from(widget.initialCorners);
    }
  }

  void resetToFull() {
    setState(() {
      _corners = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
    });
    widget.onCornersChanged(_corners);
  }

  void resetToDetected() {
    setState(() {
      _corners = List<double>.from(widget.initialCorners);
    });
    widget.onCornersChanged(_corners);
  }

  Rect _computeImageRect(BoxConstraints constraints) {
    final imgW = widget.imageWidth > 0 ? widget.imageWidth.toDouble() : 3.0;
    final imgH = widget.imageHeight > 0 ? widget.imageHeight.toDouble() : 4.0;
    final imageAspect = imgW / imgH;
    final containerAspect = constraints.maxWidth / constraints.maxHeight;

    if (containerAspect > imageAspect) {
      final h = constraints.maxHeight;
      final w = h * imageAspect;
      final left = (constraints.maxWidth - w) / 2;
      return Rect.fromLTWH(left, 0, w, h);
    } else {
      final w = constraints.maxWidth;
      final h = w / imageAspect;
      final top = (constraints.maxHeight - h) / 2;
      return Rect.fromLTWH(0, top, w, h);
    }
  }

  Offset _getCornerScreenPos(int index, Rect imageRect) {
    final nx = _corners[index * 2];
    final ny = _corners[index * 2 + 1];
    return Offset(
      imageRect.left + nx * imageRect.width,
      imageRect.top + ny * imageRect.height,
    );
  }

  void _handlePanStart(Offset globalPos, Rect imageRect) {
    const hitRadius = 42.0;
    int? nearestIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < 4; i++) {
      final screenPos = _getCornerScreenPos(i, imageRect);
      final dist = (globalPos - screenPos).distance;
      if (dist < hitRadius && dist < minDistance) {
        minDistance = dist;
        nearestIndex = i;
      }
    }

    if (nearestIndex != null) {
      setState(() {
        _activeCornerIndex = nearestIndex;
        _magnifierPos = globalPos;
      });
    }
  }

  void _handlePanUpdate(Offset globalPos, Rect imageRect) {
    final active = _activeCornerIndex;
    if (active == null) return;

    final normX = ((globalPos.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final normY = ((globalPos.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0);

    setState(() {
      _corners[active * 2] = normX;
      _corners[active * 2 + 1] = normY;
      _magnifierPos = globalPos;
    });
    widget.onCornersChanged(_corners);
  }

  void _handlePanEnd() {
    if (_activeCornerIndex != null) {
      setState(() {
        _activeCornerIndex = null;
        _magnifierPos = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageRect = _computeImageRect(constraints);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background preview image
            Positioned(
              left: imageRect.left,
              top: imageRect.top,
              width: imageRect.width,
              height: imageRect.height,
              child: Image.file(
                File(widget.imagePath),
                cacheWidth: 1080,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.white54),
                ),
              ),
            ),

            // Polygon boundary mesh overlay
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadMeshPainter(
                  corners: _corners,
                  imageRect: imageRect,
                  activeCornerIndex: _activeCornerIndex,
                  themeColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

            // Gesture detector for corner handles
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => _handlePanStart(details.localPosition, imageRect),
                onPanUpdate: (details) => _handlePanUpdate(details.localPosition, imageRect),
                onPanEnd: (_) => _handlePanEnd(),
                onPanCancel: () => _handlePanEnd(),
              ),
            ),

            // Magnifier Loupe when dragging a corner
            if (_activeCornerIndex != null && _magnifierPos != null)
              Positioned(
                left: math.max(16.0, math.min(constraints.maxWidth - 120.0, _magnifierPos!.dx - 55.0)),
                top: math.max(16.0, _magnifierPos!.dy - 130.0),
                child: _buildMagnifier(imageRect),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMagnifier(Rect imageRect) {
    final active = _activeCornerIndex;
    if (active == null) return const SizedBox.shrink();

    final cornerScreen = _getCornerScreenPos(active, imageRect);

    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 3.0),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 12, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 2x Zoom of the image around the active point
          Transform.scale(
            scale: 2.2,
            alignment: Alignment(
              ((cornerScreen.dx - imageRect.left) / imageRect.width) * 2 - 1,
              ((cornerScreen.dy - imageRect.top) / imageRect.height) * 2 - 1,
            ),
            child: Image.file(
              File(widget.imagePath),
              cacheWidth: 1080,
              fit: BoxFit.fill,
            ),
          ),
          // Crosshairs
          Center(
            child: CustomPaint(
              size: const Size(30, 30),
              painter: _CrosshairPainter(color: const Color(0xFF00E676)),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadMeshPainter extends CustomPainter {
  const _QuadMeshPainter({
    required this.corners,
    required this.imageRect,
    required this.activeCornerIndex,
    required this.themeColor,
  });

  final List<double> corners;
  final Rect imageRect;
  final int? activeCornerIndex;
  final Color themeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 8) return;

    final p0 = Offset(imageRect.left + corners[0] * imageRect.width, imageRect.top + corners[1] * imageRect.height);
    final p1 = Offset(imageRect.left + corners[2] * imageRect.width, imageRect.top + corners[3] * imageRect.height);
    final p2 = Offset(imageRect.left + corners[4] * imageRect.width, imageRect.top + corners[5] * imageRect.height);
    final p3 = Offset(imageRect.left + corners[6] * imageRect.width, imageRect.top + corners[7] * imageRect.height);

    final quadPath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    // 1. Shaded area outside document
    final outsidePath = Path()
      ..addRect(imageRect)
      ..addPath(quadPath, Offset.zero);
    outsidePath.fillType = PathFillType.evenOdd;

    final maskPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.42);
    canvas.drawPath(outsidePath, maskPaint);

    // 2. Light translucent fill inside quad
    final quadFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x2200E676);
    canvas.drawPath(quadPath, quadFillPaint);

    // 3. Document bounding border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF00E676);
    canvas.drawPath(quadPath, borderPaint);

    // 4. Subtle grid lines inside quad (Rule of thirds)
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x5500E676);

    for (int t = 1; t <= 2; t++) {
      final f = t / 3.0;
      // Horizontal grid line
      final hStart = Offset.lerp(p0, p3, f)!;
      final hEnd = Offset.lerp(p1, p2, f)!;
      canvas.drawLine(hStart, hEnd, gridPaint);

      // Vertical grid line
      final vStart = Offset.lerp(p0, p1, f)!;
      final vEnd = Offset.lerp(p3, p2, f)!;
      canvas.drawLine(vStart, vEnd, gridPaint);
    }

    // 5. Draw 4 corner handles
    final pts = [p0, p1, p2, p3];
    for (int i = 0; i < 4; i++) {
      final pt = pts[i];
      final isActive = (i == activeCornerIndex);
      final radius = isActive ? 16.0 : 12.0;

      // Outer glow / shadow
      final shadowPaint = Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(pt, radius + 2, shadowPaint);

      // White ring
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white;
      canvas.drawCircle(pt, radius, ringPaint);

      // Inner colored dot
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isActive ? Colors.white : const Color(0xFF00E676);
      canvas.drawCircle(pt, radius - 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadMeshPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.activeCornerIndex != activeCornerIndex;
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Center circle
    canvas.drawCircle(Offset(cx, cy), 3.0, paint);

    // Cross lines
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx - 4, cy), paint);
    canvas.drawLine(Offset(cx + 4, cy), Offset(cx + 10, cy), paint);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy - 4), paint);
    canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + 10), paint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}
