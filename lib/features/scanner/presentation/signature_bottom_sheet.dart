import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion_tokens.dart';
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
    sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
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
    Color(0xFF0A37A3), // Royal Blue
    Color(0xFF0F172A), // Navy Ink
    Color(0xFFB91C1C), // Official Red
    Color(0xFF047857), // Certified Green
  ];
  Color _selectedColor = const Color(0xFF111827);
  PenType _selectedPenType = PenType.fountain;
  double _selectedWidth = 3.8;

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
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                            cacheWidth: 250,
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

          // ── Toolbar: Ink Color Picker + Pen Type + Undo + Clear ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                        padding: const EdgeInsets.only(left: 6),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedColor = color);
                            _signatureController.setInkColor(color);
                          },
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : MotionTokens.chipSelection,
                            curve: MotionTokens.easeOutStrong,
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
                    if (_signatureController.isStylusActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded, size: 12, color: Color(0xFF10B981)),
                            SizedBox(width: 4),
                            Text(
                              'قلم ذكي متصل',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Pen Types
                    for (final pen in PenType.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedPenType = pen);
                            _signatureController.setPenType(pen);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : MotionTokens.chipSelection,
                            curve: MotionTokens.easeOutStrong,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _selectedPenType == pen
                                  ? palette.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedPenType == pen
                                    ? palette.accent
                                    : Colors.grey.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  pen.icon,
                                  size: 13,
                                  color: _selectedPenType == pen
                                      ? palette.accent
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  pen.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _selectedPenType == pen
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedPenType == pen
                                        ? palette.accent
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final widthOpt in [(2.4, 'دقيق'), (3.8, 'متوازن'), (5.6, 'عريض')])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedWidth = widthOpt.$1);
                            _signatureController.setBaseStrokeWidth(widthOpt.$1);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : MotionTokens.chipSelection,
                            curve: MotionTokens.easeOutStrong,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: _selectedWidth == widthOpt.$1
                                  ? palette.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedWidth == widthOpt.$1
                                    ? palette.accent
                                    : Colors.grey.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              widthOpt.$2,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: _selectedWidth == widthOpt.$1
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _selectedWidth == widthOpt.$1
                                    ? palette.accent
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (_hasDrawingState) ...[
                      TextButton.icon(
                        onPressed: _undoStroke,
                        icon: const Icon(Icons.undo_rounded, size: 15),
                        label: const Text('تراجع', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _clearCanvas,
                        icon: const Icon(Icons.delete_sweep_rounded, size: 15),
                        label: const Text('مسح', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: palette.danger,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                    ],
                  ],
                ),
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
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: (!_hasDrawingState || _saving)
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              _confirmNewSignature(save: false);
                            },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'استخدام الآن',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: (!_hasDrawingState || _saving)
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _confirmNewSignature(save: true);
                            },
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
                        'اعتماد وحفظ',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
// Dynamic Pressure-Sensitive & Velocity Adaptive Ink Engine
// ─────────────────────────────────────────────────────────────────────────────

enum PenType {
  fountain('حبر سائل', Icons.edit_note_rounded),
  ballpoint('حبر جاف', Icons.border_color_rounded),
  marker('توقيع عريض', Icons.brush_rounded);

  const PenType(this.label, this.icon);
  final String label;
  final IconData icon;
}

class InkPoint {
  const InkPoint({
    required this.point,
    required this.pressure,
    required this.timeMs,
    required this.width,
  });

  final Offset point;
  final double pressure;
  final int timeMs;
  final double width;
}

class InkStroke {
  InkStroke({
    required this.points,
    required this.color,
    required this.penType,
    required this.baseWidth,
  });

  final List<InkPoint> points;
  final Color color;
  final PenType penType;
  final double baseWidth;
}

class _SignatureController extends ChangeNotifier {
  final List<InkStroke> strokes = [];
  List<InkPoint>? currentPoints;
  Color inkColor = const Color(0xFF111827);
  PenType penType = PenType.fountain;
  double baseStrokeWidth = 3.8;
  bool isStylusActive = false;

  final Stopwatch _stopwatch = Stopwatch()..start();

  bool get hasDrawing =>
      strokes.isNotEmpty ||
      (currentPoints != null && currentPoints!.isNotEmpty);

  void setInkColor(Color color) {
    inkColor = color;
    notifyListeners();
  }

  void setPenType(PenType type) {
    penType = type;
    notifyListeners();
  }

  void setBaseStrokeWidth(double width) {
    baseStrokeWidth = width;
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    currentPoints = null;
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      notifyListeners();
    }
  }

  void startStroke(Offset point, double rawPressure, {bool isStylus = false}) {
    if (isStylus) isStylusActive = true;
    final now = _stopwatch.elapsedMilliseconds;
    final pressure = (rawPressure > 0.0 && rawPressure <= 1.0) ? rawPressure : 0.0;

    final double initialWidth;
    if (pressure > 0.05 && pressure < 0.99) {
      isStylusActive = true;
      initialWidth = baseStrokeWidth * (0.45 + 0.85 * pressure);
    } else {
      initialWidth = baseStrokeWidth * 0.7;
    }

    currentPoints = [
      InkPoint(
        point: point,
        pressure: pressure,
        timeMs: now,
        width: initialWidth,
      ),
    ];
    notifyListeners();
  }

  void updateStroke(Offset point, double rawPressure, {bool isStylus = false}) {
    final active = currentPoints;
    if (active == null || active.isEmpty) {
      startStroke(point, rawPressure, isStylus: isStylus);
      return;
    }

    final prev = active.last;
    final dist = (point - prev.point).distance;
    if (dist < 0.6) return;

    final now = _stopwatch.elapsedMilliseconds;
    final dt = math.max(now - prev.timeMs, 1);
    final velocity = dist / dt;
    final pressure = (rawPressure > 0.0 && rawPressure <= 1.0) ? rawPressure : 0.0;

    double targetWidth;
    switch (penType) {
      case PenType.fountain:
        if (pressure > 0.05 && pressure < 0.99) {
          isStylusActive = true;
          targetWidth = baseStrokeWidth * (0.35 + 1.25 * pressure);
        } else {
          final velRatio = (velocity / 2.2).clamp(0.0, 1.0);
          targetWidth = baseStrokeWidth * (1.35 - 0.75 * velRatio);
        }
        break;
      case PenType.ballpoint:
        if (pressure > 0.05 && pressure < 0.99) {
          isStylusActive = true;
          targetWidth = baseStrokeWidth * (0.6 + 0.6 * pressure);
        } else {
          final velRatio = (velocity / 2.8).clamp(0.0, 1.0);
          targetWidth = baseStrokeWidth * (1.15 - 0.35 * velRatio);
        }
        break;
      case PenType.marker:
        targetWidth = baseStrokeWidth * 1.35;
        break;
    }

    final smoothedWidth = prev.width * 0.45 + targetWidth * 0.55;

    active.add(
      InkPoint(
        point: point,
        pressure: pressure,
        timeMs: now,
        width: smoothedWidth,
      ),
    );
    notifyListeners();
  }

  void endStroke() {
    final active = currentPoints;
    if (active != null && active.isNotEmpty) {
      strokes.add(
        InkStroke(
          points: List<InkPoint>.from(active),
          color: inkColor,
          penType: penType,
          baseWidth: baseStrokeWidth,
        ),
      );
    }
    currentPoints = null;
    notifyListeners();
  }

  Rect? getStrokeBounds() {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    var hasPoints = false;

    for (final stroke in strokes) {
      for (final pt in stroke.points) {
        hasPoints = true;
        final r = pt.width;
        if (pt.point.dx - r < minX) minX = pt.point.dx - r;
        if (pt.point.dy - r < minY) minY = pt.point.dy - r;
        if (pt.point.dx + r > maxX) maxX = pt.point.dx + r;
        if (pt.point.dy + r > maxY) maxY = pt.point.dy + r;
      }
    }
    if (!hasPoints) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Future<Uint8List?> captureFromRepaintBoundary(
    GlobalKey repaintKey,
    double devicePixelRatio,
  ) async {
    if (!hasDrawing) return null;

    if (currentPoints != null && currentPoints!.isNotEmpty) {
      strokes.add(
        InkStroke(
          points: List<InkPoint>.from(currentPoints!),
          color: inkColor,
          penType: penType,
          baseWidth: baseStrokeWidth,
        ),
      );
      currentPoints = null;
      notifyListeners();
    }

    final bounds = getStrokeBounds();
    if (bounds == null) return null;

    const padding = 16.0;
    final cropLeft = bounds.left - padding;
    final cropTop = bounds.top - padding;
    final cropWidth = math.max(bounds.width + padding * 2, 48.0);
    final cropHeight = math.max(bounds.height + padding * 2, 32.0);

    final scale = devicePixelRatio.clamp(2.0, 3.5);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);
    canvas.translate(-cropLeft, -cropTop);

    _SignaturePainter.paintAllStrokes(
      canvas: canvas,
      strokes: strokes,
      currentPoints: null,
      currentStrokeColor: inkColor,
      currentPenType: penType,
      currentBaseWidth: baseStrokeWidth,
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
// Signature Pad Widget (captures stylus events, pressure, and velocity)
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
        final isStylus = event.kind == ui.PointerDeviceKind.stylus ||
            event.kind == ui.PointerDeviceKind.invertedStylus;
        widget.controller.startStroke(
          event.localPosition,
          event.pressure,
          isStylus: isStylus,
        );
      },
      onPointerMove: (event) {
        if (_activePointer != event.pointer) return;
        final isStylus = event.kind == ui.PointerDeviceKind.stylus ||
            event.kind == ui.PointerDeviceKind.invertedStylus;
        widget.controller.updateStroke(
          event.localPosition,
          event.pressure,
          isStylus: isStylus,
        );
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
                          Icons.draw_rounded,
                          size: 38,
                          color: Colors.grey.withValues(alpha: 0.38),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اكتب توقيعك هنا بالقلم أو اللمس',
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
// Signature Painter (Fluid Variable-Width Bézier Curves & Round Joints)
// ─────────────────────────────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.controller) : super(repaint: controller);
  final _SignatureController controller;

  static void paintAllStrokes({
    required Canvas canvas,
    required List<InkStroke> strokes,
    required List<InkPoint>? currentPoints,
    required Color currentStrokeColor,
    required PenType currentPenType,
    required double currentBaseWidth,
  }) {
    for (final stroke in strokes) {
      _paintSingleStroke(canvas, stroke.points, stroke.color);
    }
    if (currentPoints != null && currentPoints.isNotEmpty) {
      _paintSingleStroke(canvas, currentPoints, currentStrokeColor);
    }
  }

  static void _paintSingleStroke(
    Canvas canvas,
    List<InkPoint> points,
    Color color,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (points.length == 1) {
      canvas.drawCircle(points.first.point, points.first.width / 2, paint);
      return;
    }

    if (points.length == 2) {
      _drawSegment(
        canvas,
        points[0].point,
        points[1].point,
        points[0].width,
        points[1].width,
        paint,
      );
      return;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = (i == 0) ? points[0] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];

      final startPt = Offset(
        (p0.point.dx + p1.point.dx) / 2,
        (p0.point.dy + p1.point.dy) / 2,
      );
      final controlPt = p1.point;
      final endPt = Offset(
        (p1.point.dx + p2.point.dx) / 2,
        (p1.point.dy + p2.point.dy) / 2,
      );

      final startW = (p0.width + p1.width) / 2;
      final endW = (p1.width + p2.width) / 2;

      const steps = 6;
      Offset prevSample = startPt;
      double prevW = startW;

      for (int s = 1; s <= steps; s++) {
        final t = s / steps;
        final oneMinusT = 1.0 - t;
        final samplePt = Offset(
          oneMinusT * oneMinusT * startPt.dx +
              2 * oneMinusT * t * controlPt.dx +
              t * t * endPt.dx,
          oneMinusT * oneMinusT * startPt.dy +
              2 * oneMinusT * t * controlPt.dy +
              t * t * endPt.dy,
        );
        final sampleW = startW + (endW - startW) * t;

        _drawSegment(canvas, prevSample, samplePt, prevW, sampleW, paint);
        prevSample = samplePt;
        prevW = sampleW;
      }
    }
  }

  static void _drawSegment(
    Canvas canvas,
    Offset a,
    Offset b,
    double wa,
    double wb,
    Paint paint,
  ) {
    final ra = math.max(wa / 2, 0.4);
    final rb = math.max(wb / 2, 0.4);

    canvas.drawCircle(a, ra, paint);
    canvas.drawCircle(b, rb, paint);

    final diff = b - a;
    final dist = diff.distance;
    if (dist < 0.1) return;

    final nx = -diff.dy / dist;
    final ny = diff.dx / dist;

    final p1 = Offset(a.dx + nx * ra, a.dy + ny * ra);
    final p2 = Offset(a.dx - nx * ra, a.dy - ny * ra);
    final p3 = Offset(b.dx - nx * rb, b.dy - ny * rb);
    final p4 = Offset(b.dx + nx * rb, b.dy + ny * rb);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p4.dx, p4.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintAllStrokes(
      canvas: canvas,
      strokes: controller.strokes,
      currentPoints: controller.currentPoints,
      currentStrokeColor: controller.inkColor,
      currentPenType: controller.penType,
      currentBaseWidth: controller.baseStrokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
