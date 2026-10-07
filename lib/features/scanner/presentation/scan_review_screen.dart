import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';

import '../../../shared/models/image_filter_type.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import 'widgets/quad_crop_editor.dart';

class ScanReviewResult {
  const ScanReviewResult({
    required this.page,
    this.saveAllRemaining = false,
  });

  final ScanPage page;
  final bool saveAllRemaining;
}

/// Helper to launch ScanReviewScreen for a standalone image capture/crop/enhancement.
/// Returns the final processed & enhanced image path, or null if cancelled.
Future<String?> openScanReviewScreen(
  BuildContext context, {
  required String rawImagePath,
  List<double> initialCorners = const [],
  int imageWidth = 0,
  int imageHeight = 0,
  String initialFilter = 'enhance',
}) async {
  List<double> corners = initialCorners;
  if (corners.length != 8) {
    try {
      final detected = await NativeScannerBridge.detectCorners(rawImagePath);
      if (detected.length == 8) {
        corners = detected;
      }
    } catch (_) {}
  }

  if (!context.mounted) return null;

  final dynamic result = await Navigator.of(context).push<dynamic>(
    MaterialPageRoute(
      builder: (_) => ScanReviewScreen(
        rawImagePath: rawImagePath,
        initialCorners: corners,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        initialFilter: initialFilter,
      ),
    ),
  );

  if (result is String) return result;
  if (result is ScanPage) return result.imagePath;
  if (result is ScanReviewResult) return result.page.imagePath;
  return null;
}

/// Screen for interactive review, manual quadrilateral cropping, filter selection with live thumbnails, and rotation.
class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.rawImagePath,
    this.sessionId,
    this.pageId,
    this.initialCorners = const [],
    this.initialFilter = 'enhance',
    this.initialQuarterRotations = 0,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.pageIndex,
    this.totalPages,
  });

  final String rawImagePath;
  final String? sessionId;
  final String? pageId;
  final List<double> initialCorners; // 8 normalized coordinates
  final String initialFilter;
  final int initialQuarterRotations;
  final int imageWidth;
  final int imageHeight;
  final int? pageIndex;
  final int? totalPages;

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late List<double> _corners;
  bool _isEditingCrop = false;
  late String _selectedFilter;
  late int _quarterRotations;

  bool _isBusy = false;
  String? _statusText;
  bool _isBlurry = false;
  bool _checkedBlur = false;

  String? _warpedPreviewPath;
  String? _currentPreviewPath;
  final Map<String, String> _filterCache = {};
  final Map<String, String> _filterThumbnails = {};

  final Set<String> _tempFiles = {};
  int _previewToken = 0;

  final GlobalKey<State<QuadCropEditor>> _cropEditorKey = GlobalKey();

  static const List<({String key, String label, IconData icon})> _filters = [
    (key: 'enhance', label: 'توضيح', icon: Icons.auto_fix_high_rounded),
    (key: 'magic', label: 'لون سحري', icon: Icons.auto_awesome_rounded),
    (key: 'original', label: 'أصلي', icon: Icons.image_rounded),
    (key: 'lighten', label: 'تفتيح', icon: Icons.wb_sunny_rounded),
    (
      key: 'no_handwriting',
      label: 'إزالة خط اليد',
      icon: Icons.cleaning_services_rounded
    ),
    (
      key: 'shadow_remover',
      label: 'إزالة الظلال',
      icon: Icons.exposure_rounded
    ),
    (key: 'gray', label: 'رمادي', icon: Icons.filter_b_and_w_rounded),
    (key: 'bw', label: 'أبيض وأسود', icon: Icons.contrast_rounded),
    (key: 'eco', label: 'توفير الحبر', icon: Icons.format_color_reset_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _quarterRotations = widget.initialQuarterRotations % 4;

    if (widget.initialCorners.length == 8) {
      _corners = List<double>.from(widget.initialCorners);
      _isEditingCrop = false;
    } else {
      _corners = [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95];
      _isEditingCrop = true;
    }

    _preparePreview();
  }

  @override
  void dispose() {
    _cleanupTempFiles();
    super.dispose();
  }

  void _cleanupTempFiles() {
    for (final path in _tempFiles) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (e) {
        debugPrint('[ScanReviewScreen] Error deleting temp file $path: $e');
      }
    }
    _tempFiles.clear();
  }

  Future<void> _preparePreview() async {
    final token = ++_previewToken;
    setState(() {
      _isBusy = true;
      _statusText = 'جار تصحيح المنظور...';
    });

    try {
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      final tag = DateTime.now().millisecondsSinceEpoch;
      final warpedPath = '${draftsDir.path}/preview_warp_$tag.jpg';
      _tempFiles.add(warpedPath);

      // Fast native warp at max 1600px for instant preview with rotation in-memory
      await NativeScannerBridge.warp(
        path: widget.rawImagePath,
        corners: _corners,
        outPath: warpedPath,
        maxSide: 1600,
        quarterTurns: _quarterRotations,
      ).timeout(const Duration(seconds: 20));

      if (token != _previewToken || !mounted) return;

      _warpedPreviewPath = warpedPath;
      _filterCache.clear();
      _filterThumbnails.clear();

      await _applyFilter(_selectedFilter, parentToken: token);
      _generateFilterThumbnails(warpedPath, token);

      if (!_checkedBlur) {
        _checkedBlur = true;
        NativeScannerBridge.checkBlur(widget.rawImagePath).then((res) {
          if (mounted && res.isBlurry) {
            setState(() => _isBlurry = true);
          }
        });
      }
    } catch (e) {
      if (token != _previewToken || !mounted) return;
      setState(() {
        _isBusy = false;
        _statusText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تجهيز المعاينة: $e')),
      );
    }
  }

  Future<void> _generateFilterThumbnails(String warpedPath, int token) async {
    try {
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      for (final f in _filters) {
        if (token != _previewToken || !mounted) return;
        final tag = DateTime.now().microsecondsSinceEpoch;
        final thumbPath = '${draftsDir.path}/preview_thumb_${f.key}_$tag.jpg';
        _tempFiles.add(thumbPath);
        await NativeScannerBridge.applyFilter(
          path: warpedPath,
          filter: f.key,
          outPath: thumbPath,
          maxSide: 220,
        );
        if (token != _previewToken || !mounted) return;
        if (File(thumbPath).existsSync()) {
          setState(() {
            _filterThumbnails[f.key] = thumbPath;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _applyFilter(String filterKey, {int? parentToken}) async {
    final warped = _warpedPreviewPath;
    if (warped == null) return;

    if (_filterCache.containsKey(filterKey)) {
      setState(() {
        _selectedFilter = filterKey;
        _currentPreviewPath = _filterCache[filterKey];
        _isBusy = false;
        _statusText = null;
      });
      return;
    }

    final token = parentToken ?? ++_previewToken;
    setState(() {
      _isBusy = true;
      _statusText = 'جار تطبيق الفلتر...';
      _selectedFilter = filterKey;
    });

    try {
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      final tag = DateTime.now().millisecondsSinceEpoch;
      final filteredPath = '${draftsDir.path}/preview_${filterKey}_$tag.jpg';
      _tempFiles.add(filteredPath);

      await NativeScannerBridge.applyFilter(
        path: warped,
        filter: filterKey,
        outPath: filteredPath,
        maxSide: 1600,
      ).timeout(const Duration(seconds: 20));

      if (token != _previewToken || !mounted) return;

      _filterCache[filterKey] = filteredPath;
      setState(() {
        _currentPreviewPath = filteredPath;
        _isBusy = false;
        _statusText = null;
      });
    } catch (e) {
      if (token != _previewToken || !mounted) return;
      setState(() {
        _isBusy = false;
        _statusText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تطبيق الفلتر: $e')),
      );
    }
  }

  Future<void> _rotateLeft() async {
    if (_isBusy) return;
    _quarterRotations = (_quarterRotations + 1) % 4;
    await _preparePreview();
  }

  Future<void> _confirmAndSave({bool saveAllRemaining = false}) async {
    setState(() {
      _isBusy = true;
      _statusText = 'جار حفظ المستند بجودة كاملة...';
    });

    final intermediateFiles = <String>[];
    try {
      final pageId = widget.pageId ?? const Uuid().v4();
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      final fullWarpPath = '${draftsDir.path}/full_warp_$pageId.jpg';
      final fullFilteredPath = '${draftsDir.path}/full_filtered_$pageId.jpg';
      intermediateFiles.addAll([fullWarpPath, fullFilteredPath]);

      // 1. Hardware-accelerated warp (+ in-memory rotation before single encode)
      // Capped at 2048px (200 DPI A4) so PdfBuilderService hits its 0ms fast path directly!
      await NativeScannerBridge.warp(
        path: widget.rawImagePath,
        corners: _corners,
        outPath: fullWarpPath,
        maxSide: 2048,
        quarterTurns: _quarterRotations,
      ).timeout(const Duration(seconds: 20));

      // 2. Native OpenCV filter directly on the rotated warped document
      await NativeScannerBridge.applyFilter(
        path: fullWarpPath,
        filter: _selectedFilter,
        outPath: fullFilteredPath,
        maxSide: 2048,
      ).timeout(const Duration(seconds: 20));

      if (widget.sessionId != null) {
        // 3. Save directly into session files without memory overhead
        final savedPath = await ref.read(localDocumentStoreProvider).savePageFile(
              sessionId: widget.sessionId!,
              pageId: pageId,
              sourcePath: fullFilteredPath,
            );

        // 4. Preserve raw capture inside session directory for non-destructive re-warps
        String preservedRawPath = widget.rawImagePath;
        if (!preservedRawPath.contains(widget.sessionId!)) {
          preservedRawPath =
              await ref.read(localDocumentStoreProvider).importRawScanFile(
                    sessionId: widget.sessionId!,
                    sourcePath: widget.rawImagePath,
                  );
        }

        // Clean up intermediate full-res files immediately
        for (final p in intermediateFiles) {
          try {
            final f = File(p);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }

        if (!mounted) return;
        final scanPage = ScanPage(
          id: pageId,
          imagePath: savedPath,
          createdAt: DateTime.now(),
          originalPath: preservedRawPath,
          corners: _corners,
          filter: ImageFilterType.fromKey(_selectedFilter),
          quarterTurns: _quarterRotations,
        );
        Navigator.of(context).pop(
          saveAllRemaining
              ? ScanReviewResult(page: scanPage, saveAllRemaining: true)
              : scanPage,
        );
      } else {
        // Standalone mode: save final image to draftsDir and return ScanPage
        final finalEnhancedPath = '${draftsDir.path}/enhanced_$pageId.jpg';
        final filteredFile = File(fullFilteredPath);
        if (await filteredFile.exists()) {
          await filteredFile.copy(finalEnhancedPath);
        } else {
          await File(fullWarpPath).copy(finalEnhancedPath);
        }

        // Clean up intermediate files
        for (final p in intermediateFiles) {
          try {
            final f = File(p);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }

        if (!mounted) return;
        final scanPage = ScanPage(
          id: pageId,
          imagePath: finalEnhancedPath,
          createdAt: DateTime.now(),
          originalPath: widget.rawImagePath,
          corners: _corners,
          filter: ImageFilterType.fromKey(_selectedFilter),
          quarterTurns: _quarterRotations,
        );
        Navigator.of(context).pop(scanPage);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء حفظ الصفحة: $e')),
      );
    }
  }

  Future<void> _handleBackPress() async {
    if (_isBusy) return;
    final isSession = widget.sessionId != null;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isSession ? 'الخروج من مراجعة الصفحة؟' : 'الخروج من مراجعة الصورة؟',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          isSession
              ? 'هل تريد حفظ هذه الصفحة وإضافتها للمستند، أم إلغاء هذه اللقطة فقط؟'
              : 'هل تريد حفظ الصورة المحسنة واستخدامها، أم إلغاء هذه اللقطة؟',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('إلغاء اللقطة'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('متابعة التعديل'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            child: const Text(
              'حفظ ومتابعة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'save') {
      await _confirmAndSave();
    } else if (action == 'discard') {
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isEditingCrop) {
          setState(() => _isEditingCrop = false);
          return;
        }
        await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        appBar: AppBar(
          backgroundColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
          elevation: 0,
          title: Text(
            _isEditingCrop
                ? (widget.totalPages != null && widget.totalPages! > 1
                    ? 'تحديد حدود المستند (${widget.pageIndex ?? 1} من ${widget.totalPages})'
                    : 'تحديد حدود المستند')
                : (widget.totalPages != null && widget.totalPages! > 1
                    ? 'مراجعة الصفحة (${widget.pageIndex ?? 1} من ${widget.totalPages})'
                    : 'مراجعة وتحسين المسح'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              if (_isEditingCrop) {
                setState(() => _isEditingCrop = false);
              } else {
                _handleBackPress();
              }
            },
          ),
          actions: [
            if (!_isEditingCrop &&
                widget.totalPages != null &&
                widget.totalPages! > 1)
              TextButton(
                onPressed: _isBusy
                    ? null
                    : () => _confirmAndSave(saveAllRemaining: true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8E8E93),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                child: const Text('حفظ الكل'),
              ),
            if (!_isEditingCrop)
              TextButton.icon(
                icon: const Icon(Icons.crop_rounded, size: 18),
                label: const Text('تعديل الحواف'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _isBusy
                    ? null
                    : () {
                        setState(() => _isEditingCrop = true);
                      },
              ),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () {
                      if (_isEditingCrop) {
                        setState(() => _isEditingCrop = false);
                        _preparePreview();
                      } else {
                        _confirmAndSave();
                      }
                    },
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              child: Text(_isEditingCrop ? 'معاينة' : 'حفظ'),
            ),
          ],
        ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              if (_isBlurry)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'الصورة مهزوزة أو غير واضحة. يفضل إعادة التصوير لدقة أفضل.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _isBlurry = false),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Center(
                    child: _isEditingCrop
                        ? QuadCropEditor(
                            key: _cropEditorKey,
                            imagePath: widget.rawImagePath,
                            initialCorners: _corners,
                            imageWidth: widget.imageWidth,
                            imageHeight: widget.imageHeight,
                            onCornersChanged: (newCorners) {
                              _corners = newCorners;
                            },
                          )
                        : _buildPreviewDisplay(),
                  ),
                ),
              ),
              if (_isEditingCrop)
                _buildCropToolbar()
              else
                _buildReviewToolbar(theme),
            ],
          ),
          if (_isBusy)
            Container(
              color: Colors.black45,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white)
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.4 : 0.12,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(palette.accent),
                            strokeWidth: 3,
                          ),
                          if (_statusText != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _statusText!,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildPreviewDisplay() {
    final palette = context.appThemePalette;
    final preview = _currentPreviewPath;
    if (preview == null) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(preview),
        fit: BoxFit.contain,
        cacheWidth: 1440,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: 48,
            color: Color(0xFF8E8E93),
          ),
        ),
      ),
    );
  }

  Widget _buildCropToolbar() {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                .withValues(alpha: 0.94),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('الحدود المكتشفة'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _corners = List<double>.from(
                          widget.initialCorners.length == 8
                              ? widget.initialCorners
                              : [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95],
                        );
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fullscreen_rounded, size: 18),
                    label: const Text('كامل الصورة'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _corners = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('تطبيق القص'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      setState(() => _isEditingCrop = false);
                      _preparePreview();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewToolbar(ThemeData theme) {
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                .withValues(alpha: 0.94),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter Thumbnails Horizontal List
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final filter = _filters[index];
                      final isSelected = filter.key == _selectedFilter;
                      final thumbPath =
                          _filterThumbnails[filter.key] ?? _warpedPreviewPath;

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _isBusy ? null : () => _applyFilter(filter.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 74,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? palette.accent.withValues(alpha: 0.12)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? palette.accent
                                  : (isDark
                                      ? Colors.white12
                                      : Colors.black.withValues(alpha: 0.08)),
                              width: isSelected ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: thumbPath != null &&
                                          File(thumbPath).existsSync()
                                      ? Image.file(
                                          File(thumbPath),
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          cacheWidth: 160,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Icon(
                                              filter.icon,
                                              size: 20,
                                              color: isSelected
                                                  ? palette.accent
                                                  : const Color(0xFF8E8E93),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Icon(
                                            filter.icon,
                                            size: 20,
                                            color: isSelected
                                                ? palette.accent
                                                : const Color(0xFF8E8E93),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                filter.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected
                                      ? palette.accent
                                      : (isDark
                                          ? Colors.white
                                          : Colors.black87),
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Actions row: Rotate & Edit Crop & Save Page
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'تدوير 90 درجة لليسار',
                          icon: const Icon(Icons.rotate_left_rounded, size: 22),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            foregroundColor:
                                isDark ? Colors.white : Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isBusy ? null : _rotateLeft,
                        ),
                        const SizedBox(width: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.crop_free_rounded, size: 20),
                          label: const Text('إعادة ضبط حدود القص'),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                isDark ? Colors.white70 : Colors.black87,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isBusy
                              ? null
                              : () {
                                  setState(() => _isEditingCrop = true);
                                },
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.done_all_rounded, size: 20),
                          label: const Text('حفظ الصفحة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isBusy ? null : _confirmAndSave,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
