import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/magic_clean_service.dart';

/// Screen allowing the user to interactively erase blemishes, coffee stains,
/// fold marks, remove fingers holding the paper, and eliminate punch holes 100% offline.
class MagicCleanScreen extends StatefulWidget {
  const MagicCleanScreen({
    super.key,
    required this.imagePath,
    this.autoRemoveShadow = false,
  });

  final String imagePath;
  final bool autoRemoveShadow;

  @override
  State<MagicCleanScreen> createState() => _MagicCleanScreenState();
}

class _MagicCleanScreenState extends State<MagicCleanScreen> {
  final MagicCleanService _service = MagicCleanService();

  late Uint8List _originalBytes;
  late Uint8List _currentBytes;
  final List<Uint8List> _undoStack = [];
  final List<Uint8List> _redoStack = [];

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _showOriginal = false;

  // Manual brush state
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;
  double _brushRadius = 24.0;
  bool _isBrushMode = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      if (mounted) {
        setState(() {
          _originalBytes = bytes;
          _currentBytes = bytes;
          _isLoading = false;
        });
        if (widget.autoRemoveShadow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _autoRemoveShadowAndGlare();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل الصورة: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _pushUndo(Uint8List newBytes) {
    _undoStack.add(_currentBytes);
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _redoStack.clear();
    _currentBytes = newBytes;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _redoStack.add(_currentBytes);
      _currentBytes = _undoStack.removeLast();
      _strokes.clear();
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _undoStack.add(_currentBytes);
      _currentBytes = _redoStack.removeLast();
      _strokes.clear();
    });
  }

  Future<void> _applyBrushStrokes(Size viewportSize) async {
    if (_strokes.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final normalizedStrokes = _strokes.map((stroke) {
        final normPts = stroke.map((pt) {
          return (
            x: (pt.dx / viewportSize.width).clamp(0.0, 1.0),
            y: (pt.dy / viewportSize.height).clamp(0.0, 1.0),
          );
        }).toList();

        final radiusFraction = (_brushRadius / viewportSize.width).clamp(0.01, 0.15);
        return CleanStroke(points: normPts, radiusFraction: radiusFraction);
      }).toList();

      final cleanedBytes = await _service.applyInpaintingStrokes(
        imageBytes: _currentBytes,
        strokes: normalizedStrokes,
      );

      if (mounted) {
        setState(() {
          _pushUndo(cleanedBytes);
          _strokes.clear();
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تطبيق الممحاة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoRemoveFingers() async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final cleanedBytes = await _service.autoCleanMargins(
        imageBytes: _currentBytes,
        cleanFingers: true,
        cleanPunchHoles: false,
      );

      if (mounted) {
        setState(() {
          _pushUndo(cleanedBytes);
          _strokes.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت إزالة أصابع اليد من الأطراف بنجاح'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء المعالجة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoRemovePunchHoles() async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final cleanedBytes = await _service.autoCleanMargins(
        imageBytes: _currentBytes,
        cleanFingers: false,
        cleanPunchHoles: true,
      );

      if (mounted) {
        setState(() {
          _pushUndo(cleanedBytes);
          _strokes.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت إزالة ثقوب الدباسة والملفات بنجاح'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء المعالجة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoWhitenBackground() async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final cleanedBytes = await _service.autoLevelAndWhiten(
        imageBytes: _currentBytes,
      );

      if (mounted) {
        setState(() {
          _pushUndo(cleanedBytes);
          _strokes.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تبييض وتنقية خلفية الورقة بنجاح'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء المعالجة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoRemoveShadowAndGlare() async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final cleanedBytes = await _service.removeShadowAndGlare(
        imageBytes: _currentBytes,
      );

      if (mounted) {
        setState(() {
          _pushUndo(cleanedBytes);
          _strokes.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت إزالة ظل الهاتف وضبط الإضاءة بنجاح'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء إزالة الظل: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveAndReturn() async {
    setState(() => _isProcessing = true);
    try {
      final f = File(widget.imagePath);
      await f.writeAsBytes(_currentBytes, flush: true);
      await FileImage(f).evict();

      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(_currentBytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ التعديلات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'إلغاء',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'الممحاة الذكية وتنظيف الورق',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
        ),
        actions: [
          // Hold to see original
          GestureDetector(
            onTapDown: (_) => setState(() => _showOriginal = true),
            onTapUp: (_) => setState(() => _showOriginal = false),
            onTapCancel: () => setState(() => _showOriginal = false),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _showOriginal
                    ? palette.accent
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'الأصل',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _showOriginal ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'تراجع',
            icon: const Icon(Icons.undo_rounded),
            color: _undoStack.isNotEmpty ? Colors.white : Colors.white30,
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            tooltip: 'إعادة',
            icon: const Icon(Icons.redo_rounded),
            color: _redoStack.isNotEmpty ? Colors.white : Colors.white30,
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
          TextButton(
            onPressed: _isProcessing ? null : _saveAndReturn,
            child: const Text(
              'حفظ',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final displayBytes = _showOriginal ? _originalBytes : _currentBytes;

          return Stack(
            children: [
              Column(
                children: [
                  // ── Document Image & Interactive Canvas ──
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: LayoutBuilder(
                            builder: (ctx, boxConstraints) {
                              return GestureDetector(
                                onPanStart: _isBrushMode
                                    ? (details) {
                                        setState(() {
                                          _currentStroke = [details.localPosition];
                                          _strokes.add(_currentStroke!);
                                        });
                                      }
                                    : null,
                                onPanUpdate: _isBrushMode
                                    ? (details) {
                                        setState(() {
                                          _currentStroke?.add(details.localPosition);
                                        });
                                      }
                                    : null,
                                onPanEnd: _isBrushMode
                                    ? (_) {
                                        _applyBrushStrokes(
                                          Size(
                                            boxConstraints.maxWidth,
                                            boxConstraints.maxHeight,
                                          ),
                                        );
                                      }
                                    : null,
                                child: Stack(
                                  fit: StackFit.passthrough,
                                  children: [
                                    Image.memory(
                                      displayBytes,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                      ),
                                    ),
                                    if (_isBrushMode && _strokes.isNotEmpty)
                                      CustomPaint(
                                        painter: _BrushStrokePainter(
                                          strokes: _strokes,
                                          brushRadius: _brushRadius,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom Control Panel ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? Colors.white12
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brush Size Slider (When in Brush Mode)
                          if (_isBrushMode) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.brush_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'حجم الممحاة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Slider(
                                    value: _brushRadius,
                                    min: 10.0,
                                    max: 60.0,
                                    activeColor: palette.accent,
                                    onChanged: (val) {
                                      setState(() => _brushRadius = val);
                                    },
                                  ),
                                ),
                                Container(
                                  width: _brushRadius * 0.7,
                                  height: _brushRadius * 0.7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: palette.accent.withValues(alpha: 0.6),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],

                          // Tool Action Bar
                          SizedBox(
                            height: 74,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _buildToolButton(
                                  icon: Icons.brush_rounded,
                                  label: 'الممحاة اليدوية',
                                  isSelected: _isBrushMode,
                                  onTap: () => setState(() => _isBrushMode = !_isBrushMode),
                                  accentColor: palette.accent,
                                ),
                                const SizedBox(width: 8),
                                _buildToolButton(
                                  icon: Icons.wb_sunny_rounded,
                                  label: 'إزالة ظل الهاتف',
                                  isSelected: false,
                                  onTap: _autoRemoveShadowAndGlare,
                                  accentColor: const Color(0xFFFF9500),
                                ),
                                const SizedBox(width: 8),
                                _buildToolButton(
                                  icon: Icons.back_hand_rounded,
                                  label: 'إزالة الأصابع',
                                  isSelected: false,
                                  onTap: _autoRemoveFingers,
                                  accentColor: const Color(0xFF34C759),
                                ),
                                const SizedBox(width: 8),
                                _buildToolButton(
                                  icon: Icons.radio_button_checked_rounded,
                                  label: 'ثقوب الملفات',
                                  isSelected: false,
                                  onTap: _autoRemovePunchHoles,
                                  accentColor: const Color(0xFFFF2D55),
                                ),
                                const SizedBox(width: 8),
                                _buildToolButton(
                                  icon: Icons.cleaning_services_rounded,
                                  label: 'تبييض الورقة',
                                  isSelected: false,
                                  onTap: _autoWhitenBackground,
                                  accentColor: const Color(0xFF5856D6),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Processing Overlay Indicator
              if (_isProcessing)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E24),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator.adaptive(),
                          SizedBox(width: 16),
                          Text(
                            'جاري التنظيف الذكي بدون إنترنت...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? accentColor : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: isSelected ? accentColor : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? accentColor : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the user's brush strokes with a soft translucent glow
class _BrushStrokePainter extends CustomPainter {
  const _BrushStrokePainter({
    required this.strokes,
    required this.brushRadius,
  });

  final List<List<Offset>> strokes;
  final double brushRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF2D55).withValues(alpha: 0.45)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = brushRadius * 2
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          brushRadius,
          Paint()
            ..color = const Color(0xFFFF2D55).withValues(alpha: 0.45)
            ..style = PaintingStyle.fill,
        );
        continue;
      }

      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BrushStrokePainter oldDelegate) => true;
}
