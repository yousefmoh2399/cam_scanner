import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/signature_model.dart';
import '../data/signature_extractor_service.dart';
import '../data/signature_storage_service.dart';

/// Result returned when the user confirms a signature from the bottom sheet.
class SignatureResult {
  const SignatureResult({required this.pngBytes, required this.isSaved});

  /// Raw PNG bytes of the drawn/selected signature (tightly cropped to ink bounds).
  final Uint8List pngBytes;

  /// Whether the user chose to save this signature for future use.
  final bool isSaved;
}

/// Shows a rock-solid, non-draggable modal sheet for drawing or selecting a signature.
///
/// `enableDrag: false` ensures the sheet never moves or steals touch gestures
/// while the user is signing.
Future<SignatureResult?> showSignatureBottomSheet({
  required BuildContext context,
  required SignatureStorageService storageService,
}) {
  return showModalBottomSheet<SignatureResult>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SignatureBottomSheet(storageService: storageService),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _SignatureBottomSheet extends StatefulWidget {
  const _SignatureBottomSheet({required this.storageService});
  final SignatureStorageService storageService;

  @override
  State<_SignatureBottomSheet> createState() => _SignatureBottomSheetState();
}

class _SignatureBottomSheetState extends State<_SignatureBottomSheet> {
  final _signatureController = _SignatureController();

  /// Key attached to the RepaintBoundary inside _SignaturePadWidget
  final GlobalKey _repaintKey = GlobalKey();

  List<SignatureModel> _savedSignatures = [];
  bool _loadingSignatures = true;
  bool _saving = false;
  bool _hasDrawingState = false;

  static const List<Color> _inkColors = [
    Color(0xFF111827), // Deep Black
    Color(0xFF1D4ED8), // Royal Blue Pen
    Color(0xFF0F172A), // Navy Ink
  ];
  Color _selectedColor = const Color(0xFF111827);

  @override
  void initState() {
    super.initState();
    _signatureController.addListener(_onSignatureChanged);
    _loadSignatures();
  }

  void _onSignatureChanged() {
    final nowHasDrawing = _signatureController.hasDrawing;
    if (nowHasDrawing != _hasDrawingState && mounted) {
      setState(() {
        _hasDrawingState = nowHasDrawing;
      });
    }
  }

  @override
  void dispose() {
    _signatureController.removeListener(_onSignatureChanged);
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadSignatures() async {
    final sigs = await widget.storageService.loadAllSignatures();
    if (mounted) {
      setState(() {
        _savedSignatures = sigs;
        _loadingSignatures = false;
      });
    }
  }

  void _clearCanvas() {
    _signatureController.clear();
  }

  void _undoStroke() {
    _signatureController.undo();
  }

  Future<void> _confirmNewSignature({required bool save}) async {
    if (!_signatureController.hasDrawing) return;
    setState(() => _saving = true);

    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final pngBytes = await _signatureController.captureFromRepaintBoundary(
        _repaintKey,
        dpr,
      );
      if (pngBytes == null) throw Exception('توقيع فارغ');

      if (save) {
        await widget.storageService.saveSignature(pngBytes);
      }

      if (mounted) {
        Navigator.of(
          context,
        ).pop(SignatureResult(pngBytes: pngBytes, isSaved: save));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء معالجة التوقيع: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _selectSavedSignature(SignatureModel sig) async {
    try {
      final bytes = await File(sig.filePath).readAsBytes();
      if (mounted) {
        Navigator.of(
          context,
        ).pop(SignatureResult(pngBytes: bytes, isSaved: true));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل التوقيع المحفوظ.')),
        );
      }
    }
  }

  Future<void> _deleteSavedSignature(SignatureModel sig) async {
    await widget.storageService.deleteSignature(sig.id);
    await _loadSignatures();
  }

  Future<void> _scanSignatureFromPaper() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }
    final imagePath = result.files.first.path!;

    setState(() => _saving = true);

    try {
      final extractor = SignatureExtractorService();
      final transparentBytes = await extractor.extractTransparentSignatureFromFile(
        filePath: imagePath,
        colorMode: SignatureInkColorMode.royalBlue,
      );

      await widget.storageService.saveSignature(transparentBytes);

      if (mounted) {
        Navigator.of(context).pop(SignatureResult(
          pngBytes: transparentBytes,
          isSaved: true,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استخراج التوقيع من الورقة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: mq.padding.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.draw_rounded,
                    color: palette.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'التوقيع الإلكتروني',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'وقّع بإصبعك مباشرة داخل المربع بالأسفل',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),

          // ── Scan Signature from Paper Option ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _scanSignatureFromPaper,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.document_scanner_rounded,
                      size: 20,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مسح توقيع من ورقة بيضاء (تفريغ شفاف)',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: palette.accent,
                            ),
                          ),
                          Text(
                            'صوّر توقيعك على ورقة وسيزيل التطبيق الخلفية تلقائياً',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  ],
                ),
              ),
            ),
          ),

          // ── Saved signatures horizontal list ──
          if (!_loadingSignatures && _savedSignatures.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'توقيعاتك المحفوظة (اضغط للاختيار فوراً)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _savedSignatures.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final sig = _savedSignatures[index];
                  return GestureDetector(
                    onTap: () => _selectSavedSignature(sig),
                    onLongPress: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('حذف التوقيع'),
                          content: const Text(
                            'هل تريد حذف هذا التوقيع المحفوظ؟',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('إلغاء'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.danger,
                              ),
                              child: const Text('حذف'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _deleteSavedSignature(sig);
                      }
                    },
                    child: Stack(
                      children: [
                        Container(
                          width: 125,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Image.file(
                            File(sig.filePath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: GestureDetector(
                            onTap: () => _deleteSavedSignature(sig),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Toolbar: Ink Color Picker + Undo + Clear ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Text(
                  'لون الحبر:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                for (final color in _inkColors)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedColor = color);
                        _signatureController.setInkColor(color);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == color
                                ? palette.accent
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: _selectedColor == color
                              ? [
                                  BoxShadow(
                                    color: palette.accent.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                        child: _selectedColor == color
                            ? const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                const Spacer(),
                if (_hasDrawingState) ...[
                  TextButton.icon(
                    onPressed: _undoStroke,
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('تراجع'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _clearCanvas,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                    label: const Text('مسح'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.danger,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Drawing canvas (raw pointer Listener -> 0ms latency, never drags sheet) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 210,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hasDrawingState
                      ? palette.accent
                      : palette.accent.withValues(alpha: 0.35),
                  width: _hasDrawingState ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // Baseline guide line for signing
                    Positioned(
                      left: 28,
                      right: 28,
                      bottom: 48,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: Colors.grey.withValues(alpha: 0.35),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: Colors.grey.withValues(alpha: 0.25),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _SignaturePadWidget(
                        controller: _signatureController,
                        showHint: !_hasDrawingState,
                        repaintKey: _repaintKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Action buttons (Always visible so sheet height never jumps) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!_hasDrawingState || _saving)
                        ? null
                        : () => _confirmNewSignature(save: false),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('استخدام الآن'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      foregroundColor: palette.accent,
                      side: BorderSide(
                        color: _hasDrawingState
                            ? palette.accent.withValues(alpha: 0.6)
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: (!_hasDrawingState || _saving)
                        ? null
                        : () => _confirmNewSignature(save: true),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text(
                      'اعتماد وحفظ التوقيع',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature Controller (0-lag ChangeNotifier + tight bounding-box crop)
// ─────────────────────────────────────────────────────────────────────────────

class _SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  List<Offset>? currentStroke;
  Color inkColor = const Color(0xFF111827);

  bool get hasDrawing =>
      strokes.isNotEmpty ||
      (currentStroke != null && currentStroke!.isNotEmpty);

  void setInkColor(Color color) {
    inkColor = color;
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    currentStroke = null;
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      notifyListeners();
    }
  }

  void startStroke(Offset point) {
    currentStroke = [point];
    notifyListeners();
  }

  void updateStroke(Offset point) {
    final active = currentStroke;
    if (active == null) {
      currentStroke = [point];
    } else if (active.isEmpty || (active.last - point).distance > 0.8) {
      active.add(point);
    }
    notifyListeners();
  }

  void endStroke() {
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      strokes.add(List.from(currentStroke!));
    }
    currentStroke = null;
    notifyListeners();
  }

  Rect? getStrokeBounds() {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    var hasPoints = false;

    for (final stroke in strokes) {
      for (final pt in stroke) {
        hasPoints = true;
        if (pt.dx < minX) minX = pt.dx;
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dx > maxX) maxX = pt.dx;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }
    if (!hasPoints) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Renders the signature directly onto an offscreen canvas tightly cropped
  /// around the actual ink strokes, so the placed signature box has no huge
  /// empty margins around it.
  Future<Uint8List?> captureFromRepaintBoundary(
    GlobalKey repaintKey,
    double devicePixelRatio,
  ) async {
    if (!hasDrawing) return null;

    if (currentStroke != null && currentStroke!.isNotEmpty) {
      strokes.add(List.from(currentStroke!));
      currentStroke = null;
      notifyListeners();
    }

    final bounds = getStrokeBounds();
    if (bounds == null) return null;

    const padding = 14.0;
    final cropLeft = bounds.left - padding;
    final cropTop = bounds.top - padding;
    final cropWidth = math.max(bounds.width + padding * 2, 48.0);
    final cropHeight = math.max(bounds.height + padding * 2, 32.0);

    final scale = devicePixelRatio.clamp(2.0, 3.5);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);
    canvas.translate(-cropLeft, -cropTop);

    _SignaturePainter.paintStrokes(
      canvas: canvas,
      strokes: strokes,
      currentStroke: null,
      inkColor: inkColor,
    );

    final picture = recorder.endRecording();
    final imgWidth = (cropWidth * scale).round().clamp(1, 4096);
    final imgHeight = (cropHeight * scale).round().clamp(1, 4096);
    final image = await picture.toImage(imgWidth, imgHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;

    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature Pad Widget (uses raw Listener for instant 0ms first-touch drawing)
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePadWidget extends StatefulWidget {
  const _SignaturePadWidget({
    required this.controller,
    required this.showHint,
    required this.repaintKey,
  });

  final _SignatureController controller;
  final bool showHint;
  final GlobalKey repaintKey;

  @override
  State<_SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<_SignaturePadWidget> {
  int? _activePointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        widget.controller.startStroke(event.localPosition);
      },
      onPointerMove: (event) {
        if (_activePointer != event.pointer) return;
        widget.controller.updateStroke(event.localPosition);
      },
      onPointerUp: (event) {
        if (_activePointer != event.pointer) return;
        _activePointer = null;
        widget.controller.endStroke();
      },
      onPointerCancel: (event) {
        if (_activePointer != event.pointer) return;
        _activePointer = null;
        widget.controller.endStroke();
      },
      child: RepaintBoundary(
        key: widget.repaintKey,
        child: CustomPaint(
          painter: _SignaturePainter(widget.controller),
          child: widget.showHint
              ? Center(
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.gesture_rounded,
                          size: 38,
                          color: Colors.grey.withValues(alpha: 0.38),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اكتب توقيعك هنا مباشرة',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature Painter (Smooth Quadratic Bézier curves)
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.controller) : super(repaint: controller);
  final _SignatureController controller;

  static void paintStrokes({
    required Canvas canvas,
    required List<List<Offset>> strokes,
    required List<Offset>? currentStroke,
    required Color inkColor,
  }) {
    final paint = Paint()
      ..color = inkColor
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    void drawStroke(List<Offset> stroke) {
      if (stroke.isEmpty) return;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          2.0,
          Paint()
            ..color = inkColor
            ..isAntiAlias = true
            ..style = PaintingStyle.fill,
        );
        return;
      }
      if (stroke.length == 2) {
        canvas.drawLine(stroke[0], stroke[1], paint);
        return;
      }

      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final p0 = stroke[i];
        final p1 = stroke[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;
        path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
    }

    for (final stroke in strokes) {
      drawStroke(stroke);
    }

    if (currentStroke != null && currentStroke.isNotEmpty) {
      drawStroke(currentStroke);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokes(
      canvas: canvas,
      strokes: controller.strokes,
      currentStroke: controller.currentStroke,
      inkColor: controller.inkColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => false;
}
