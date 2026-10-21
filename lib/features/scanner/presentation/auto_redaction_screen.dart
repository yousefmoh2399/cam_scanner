import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/motion_tokens.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import '../data/smart_redaction_service.dart';

/// Screen for permanently burning solid black redactions over sensitive data
/// (National ID, IBAN, bank records, signatures) with pixel-perfect coordinate mapping.
class AutoRedactionScreen extends ConsumerStatefulWidget {
  const AutoRedactionScreen({
    super.key,
    this.initialDocument,
    this.initialImagePath,
  });

  final PendingUpload? initialDocument;
  final String? initialImagePath;

  @override
  ConsumerState<AutoRedactionScreen> createState() => _AutoRedactionScreenState();
}

class _AutoRedactionScreenState extends ConsumerState<AutoRedactionScreen> {
  final SmartRedactionService _redactionService = SmartRedactionService();

  String? _selectedImagePath;
  PendingUpload? _selectedDoc;
  Size? _imageSize;

  final List<RedactionTarget> _redactions = [];
  final List<RedactionTarget> _undoStack = [];

  bool _isManualDrawing = true;
  Offset? _drawStart;
  Offset? _drawCurrent;

  bool _isDetecting = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDoc = widget.initialDocument;
    if (widget.initialImagePath != null) {
      _selectedImagePath = widget.initialImagePath;
    } else if (widget.initialDocument != null &&
        widget.initialDocument!.pages.isNotEmpty) {
      _selectedImagePath = widget.initialDocument!.pages.first.imagePath;
    }

    if (_selectedImagePath != null) {
      _loadImageSizeAndDetect(_selectedImagePath!);
    }
  }

  Future<void> _loadImageSizeAndDetect(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();

      if (mounted) {
        setState(() {
          _imageSize = size;
          _selectedImagePath = path;
          _redactions.clear();
          _undoStack.clear();
        });
      }
    } catch (e) {
      debugPrint('[AutoRedaction] Image size probe error: $e');
    }
  }

  Future<void> _triggerAutoDetection() async {
    if (_selectedImagePath == null || _isDetecting) return;
    setState(() => _isDetecting = true);
    HapticFeedback.lightImpact();

    try {
      final ocrService = ref.read(ocrServiceProvider);
      final ocrDoc = await ocrService.recognizeDocument(
        imagePaths: [_selectedImagePath!],
      );
      if (ocrDoc.pages.isNotEmpty && mounted) {
        final detected = _redactionService.autoDetectSensitiveTargets(
          ocrLines: ocrDoc.pages.first.lines,
        );

        setState(() {
          for (final t in detected) {
            if (!_redactions.any((r) => r.id == t.id)) {
              _redactions.add(t);
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detected.isNotEmpty
                  ? 'تم كشف ${detected.length} عنصراً حساساً تلقائياً'
                  : 'لم يتم العثور على أرقام أو بيانات حساسة بنص الوثيقة',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AutoRedaction] Detection error: $e');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _showSourcePickerSheet() async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final choice = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'اختيار مستند للحجب الأمني',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'التقط صورة بالكاميرا أو اختر مستنداً من المعرض أو المكتبة',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildPickerActionTile(
                      ctx: ctx,
                      icon: Icons.camera_alt_rounded,
                      title: 'كاميرا المستندات',
                      subtitle: 'التقاط فوري',
                      color: const Color(0xFF007AFF),
                      isDark: isDark,
                      value: 'camera',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPickerActionTile(
                      ctx: ctx,
                      icon: Icons.photo_library_rounded,
                      title: 'معرض الصور',
                      subtitle: 'من ألبومك',
                      color: const Color(0xFF34C759),
                      isDark: isDark,
                      value: 'gallery',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPickerActionTile(
                      ctx: ctx,
                      icon: Icons.folder_open_rounded,
                      title: 'مكتبة التطبيق',
                      subtitle: 'المستندات المحفوظة',
                      color: const Color(0xFFFF9500),
                      isDark: isDark,
                      value: 'library',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'camera') {
      try {
        final tmpDir = await getTemporaryDirectory();
        final res = await NativeScannerBridge.startSingleScan(destDir: tmpDir.path);
        if (res != null && mounted) {
          _loadImageSizeAndDetect(res.path);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
          );
        }
      }
    } else if (choice == 'gallery') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        _loadImageSizeAndDetect(res.files.single.path!);
      }
    } else if (choice == 'library') {
      await _selectDocumentFromLibrary();
    }
  }

  Widget _buildPickerActionTile({
    required BuildContext ctx,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required String value,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(ctx, value);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDocumentFromLibrary() async {
    final docs = await ref.read(pendingUploadsControllerProvider.future);
    if (!mounted) return;

    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selected = await showModalBottomSheet<PendingUpload>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'اختر مستنداً لحجب وتسويد البيانات',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      return ListTile(
                        leading: const Icon(Icons.shield_outlined, color: Colors.redAccent),
                        title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${d.pages.length} صفحات'),
                        onTap: () => Navigator.of(ctx).pop(d),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected.pages.isNotEmpty && mounted) {
      setState(() => _selectedDoc = selected);
      await _loadImageSizeAndDetect(selected.pages.first.imagePath);
    }
  }

  void _addManualRedactionBox(Rect normalized) {
    setState(() {
      _undoStack.clear();
      _redactions.add(RedactionTarget(
        id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
        label: 'حجب يدوي #${_redactions.length + 1}',
        normalizedRect: normalized,
        isAutoDetected: false,
      ));
    });
  }

  void _undoRedaction() {
    if (_redactions.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      final last = _redactions.removeLast();
      _undoStack.add(last);
    });
  }

  void _clearAllRedactions() {
    if (_redactions.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _undoStack.addAll(_redactions);
      _redactions.clear();
    });
  }

  void _removeRedaction(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final removed = _redactions.removeAt(index);
      _undoStack.add(removed);
    });
  }

  Future<void> _saveRedactedDocument({bool shareImmediately = false}) async {
    if (_selectedImagePath == null || _redactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد جزء لحجبه أولاً')),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final outPath = await _redactionService.burnRedactionsToFile(
        sourceImagePath: _selectedImagePath!,
        redactions: _redactions,
      );

      final docStore = ref.read(localDocumentStoreProvider);
      final newDoc = PendingUpload(
        id: 'redacted_${DateTime.now().millisecondsSinceEpoch}',
        fileName: '${_selectedDoc?.title ?? "مستند"}_محجوب_أمنياً',
        filePath: outPath,
        pageCount: 1,
        pages: [
          ScanPage(
            imagePath: outPath,
          ),
        ],
        createdAt: DateTime.now(),
        tags: const ['محجوب أمنياً', 'خصوصية', 'حجب'],
      );

      await docStore.savePendingUpload(newDoc);
      await ref.read(pendingUploadsControllerProvider.notifier).refresh();

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (shareImmediately) {
        Share.shareXFiles([XFile(outPath)], text: newDoc.title);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF34C759),
            content: const Text(
              'تم تسويد البيانات وحرقها داخل الصورة وحفظ النسخة بالمكتبة بنجاح!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.white,
              onPressed: () {
                Share.shareXFiles([XFile(outPath)], text: newDoc.title);
              },
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        appBar: AppBar(
          backgroundColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'الحجب الأمني وتسويد البيانات',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: 'تغيير الوثيقة',
              icon: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF007AFF)),
              onPressed: _showSourcePickerSheet,
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Top Toolbar (Detection, Undo, Clear) ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.6,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Auto Detect Button
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: _selectedImagePath != null && !_isDetecting
                          ? _triggerAutoDetection
                          : null,
                      icon: _isDetecting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF007AFF)),
                      label: const Text(
                        'كشف ذكي',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Mode Toggle Button (Draw vs View)
                  IconButton(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                    tooltip: _isManualDrawing ? 'وضع التحديد اليدوي نشط' : 'وضع المعاينة (التحديد معطل)',
                    icon: Icon(
                      _isManualDrawing ? Icons.draw_rounded : Icons.pan_tool_outlined,
                      size: 20,
                      color: _isManualDrawing ? const Color(0xFF007AFF) : const Color(0xFF8E8E93),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isManualDrawing = !_isManualDrawing);
                    },
                  ),

                  const Spacer(),

                  // Undo Button
                  IconButton(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                    tooltip: 'تراجع',
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    onPressed: _redactions.isNotEmpty ? _undoRedaction : null,
                  ),
                  const SizedBox(width: 4),

                  // Clear All Button
                  IconButton(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                    tooltip: 'مسح الكل',
                    icon: const Icon(Icons.delete_sweep_rounded, size: 20, color: Colors.redAccent),
                    onPressed: _redactions.isNotEmpty ? _clearAllRedactions : null,
                  ),
                ],
              ),
            ),

            // ── Interactive Document Preview Canvas Area ──
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF121214) : const Color(0xFFE5E5EA),
                child: Center(
                  child: _selectedImagePath == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                                ),
                                child: const Icon(
                                  Icons.security_rounded,
                                  size: 48,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'لا توجد وثيقة محددة حالياً',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'اختر وثيقة أو التقط صورة بالكاميرا للبدء بالتسويد',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 44,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                                  label: const Text(
                                    'اختيار وثيقة الآن',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  onPressed: _showSourcePickerSheet,
                                ),
                              ),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (_imageSize == null) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            // Precise letterboxing compensation using applyBoxFit:
                            final fittedSizes = applyBoxFit(
                              BoxFit.contain,
                              _imageSize!,
                              Size(constraints.maxWidth, constraints.maxHeight),
                            );

                            final renderW = fittedSizes.destination.width;
                            final renderH = fittedSizes.destination.height;
                            final offsetX = (constraints.maxWidth - renderW) / 2.0;
                            final offsetY = (constraints.maxHeight - renderH) / 2.0;

                            return Stack(
                              children: [
                                // Center Image
                                Positioned(
                                  left: offsetX,
                                  top: offsetY,
                                  width: renderW,
                                  height: renderH,
                                  child: Image.file(
                                    File(_selectedImagePath!),
                                    fit: BoxFit.fill,
                                    cacheWidth: 1600,
                                  ),
                                ),

                                // Interactive Overlay Canvas: Exactly on top of image
                                Positioned(
                                  left: offsetX,
                                  top: offsetY,
                                  width: renderW,
                                  height: renderH,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: (details) {
                                      if (!_isManualDrawing) return;
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _drawStart = details.localPosition;
                                        _drawCurrent = details.localPosition;
                                      });
                                    },
                                    onPanUpdate: (details) {
                                      if (!_isManualDrawing) return;
                                      setState(() {
                                        _drawCurrent = details.localPosition;
                                      });
                                    },
                                    onPanEnd: (details) {
                                      if (!_isManualDrawing ||
                                          _drawStart == null ||
                                          _drawCurrent == null) {
                                        return;
                                      }

                                      // Normalize touch coords strictly to [0.0, 1.0] relative to renderW & renderH
                                      final l = (_drawStart!.dx / renderW).clamp(0.0, 1.0);
                                      final t = (_drawStart!.dy / renderH).clamp(0.0, 1.0);
                                      final r = (_drawCurrent!.dx / renderW).clamp(0.0, 1.0);
                                      final b = (_drawCurrent!.dy / renderH).clamp(0.0, 1.0);

                                      final rect = Rect.fromLTRB(
                                        math.min(l, r),
                                        math.min(t, b),
                                        math.max(l, r),
                                        math.max(t, b),
                                      );

                                      if (rect.width > 0.015 && rect.height > 0.008) {
                                        HapticFeedback.lightImpact();
                                        _addManualRedactionBox(rect);
                                      }

                                      setState(() {
                                        _drawStart = null;
                                        _drawCurrent = null;
                                      });
                                    },
                                    child: CustomPaint(
                                      painter: _PixelPerfectRedactionPainter(
                                        redactions: _redactions,
                                        activeStart: _drawStart,
                                        activeCurrent: _drawCurrent,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ),

            // ── Redaction Targets List & Controls ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.6,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section Header & Counter
                  Row(
                    children: [
                      const Icon(Icons.security_update_warning_rounded,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'المربعات المحجوبة (${_redactions.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Horizontal Targets List
                  if (_redactions.isNotEmpty)
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _redactions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final target = _redactions[i];
                          return Chip(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              target.isAutoDetected
                                  ? Icons.smart_toy_rounded
                                  : Icons.edit_rounded,
                              size: 14,
                              color: const Color(0xFF007AFF),
                            ),
                            backgroundColor: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF2F2F7),
                            label: Text(
                              target.label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                            onDeleted: () => _removeRedaction(i),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 14),

                  // ── Apple Balanced Action Buttons (50% / 50%) ──
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _selectedImagePath != null &&
                                    _redactions.isNotEmpty &&
                                    !_isSaving
                                ? () => _saveRedactedDocument(shareImmediately: true)
                                : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                              foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.ios_share_rounded, size: 17),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'مشاركة مباشرة',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: _selectedImagePath != null &&
                                    _redactions.isNotEmpty &&
                                    !_isSaving
                                ? () => _saveRedactedDocument(shareImmediately: false)
                                : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              backgroundColor: const Color(0xFF1C1C1E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _isSaving
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.lock_rounded, size: 17),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _isSaving ? 'جارٍ الحرق...' : 'حفظ المستند',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter that renders existing redaction targets and live active drag rectangle
/// scaled strictly against the current rendered canvas size.
class _PixelPerfectRedactionPainter extends CustomPainter {
  _PixelPerfectRedactionPainter({
    required this.redactions,
    this.activeStart,
    this.activeCurrent,
  });

  final List<RedactionTarget> redactions;
  final Offset? activeStart;
  final Offset? activeCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    final solidBlackPaint = Paint()
      ..color = const Color(0xFF111827) // Solid deep blackout
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Paint saved redactions
    for (final target in redactions) {
      final rect = Rect.fromLTRB(
        target.normalizedRect.left * size.width,
        target.normalizedRect.top * size.height,
        target.normalizedRect.right * size.width,
        target.normalizedRect.bottom * size.height,
      );

      canvas.drawRect(rect, solidBlackPaint);
      canvas.drawRect(rect, borderPaint);
    }

    // Paint live active drag rectangle
    if (activeStart != null && activeCurrent != null) {
      final liveRect = Rect.fromPoints(activeStart!, activeCurrent!);
      final activeFill = Paint()
        ..color = const Color(0xFF111827).withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      final activeBorder = Paint()
        ..color = const Color(0xFF007AFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawRect(liveRect, activeFill);
      canvas.drawRect(liveRect, activeBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelPerfectRedactionPainter oldDelegate) {
    return oldDelegate.redactions != redactions ||
        oldDelegate.activeStart != activeStart ||
        oldDelegate.activeCurrent != activeCurrent;
  }
}
