import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/book_curve_service.dart';
import '../data/pdf_builder_service.dart';

class BookCurveFlattenerScreen extends ConsumerStatefulWidget {
  const BookCurveFlattenerScreen({
    super.key,
    required this.imagePath,
  });

  final String imagePath;

  @override
  ConsumerState<BookCurveFlattenerScreen> createState() =>
      _BookCurveFlattenerScreenState();
}

class _BookCurveFlattenerScreenState
    extends ConsumerState<BookCurveFlattenerScreen> {
  final BookCurveService _service = BookCurveService();

  late Uint8List _originalBytes;
  Uint8List? _flattenedBytes;

  bool _isLoading = true;
  bool _isProcessing = false;

  // Parameters
  BookSpinePosition _spinePosition = BookSpinePosition.left;
  double _curvatureStrength = 0.55;
  bool _removeGutterShadow = true;

  // Comparison Wipe Slider (0.0 to 1.0)
  double _splitRatio = 0.50;
  bool _isComparing = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      if (!file.existsSync() || await file.length() == 0) {
        throw Exception('ملف الصورة غير متوفر أو فارغ');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('ملف الصورة فارغ (0 بايت)');
      }
      if (mounted) {
        setState(() {
          _originalBytes = bytes;
          _isLoading = false;
        });
        _applyDewarp();
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

  Future<void> _applyDewarp() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    HapticFeedback.lightImpact();

    try {
      final result = await _service.flattenBookCurve(
        imageBytes: _originalBytes,
        curvatureStrength: _curvatureStrength,
        spinePosition: _spinePosition,
        removeGutterShadow: _removeGutterShadow,
      );

      if (mounted) {
        setState(() {
          _flattenedBytes = result;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء المعالجة: $e')),
        );
      }
    }
  }

  Future<void> _saveToLibrary() async {
    if (_flattenedBytes == null) return;
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final docsDir = await ref.read(localDocumentStoreProvider).getPendingDirectory();
      final docId = 'book_dewarp_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = 'كتاب_مسطح_${DateTime.now().millisecondsSinceEpoch}';

      final imgPath = p.join(docsDir.path, '${docId}_flat.jpg');
      await File(imgPath).writeAsBytes(_flattenedBytes!, flush: true);

      final pdfBuilder = PdfBuilderService();
      final pdfBytes = await pdfBuilder.buildPdf(
        imagePaths: [imgPath],
        paperSizes: [DocumentPaperSize.a4],
      );

      final pdfPath = p.join(docsDir.path, '$fileName.pdf');
      await File(pdfPath).writeAsBytes(pdfBytes, flush: true);

      final doc = PendingUpload(
        id: docId,
        fileName: '$fileName.pdf',
        filePath: pdfPath,
        fileType: 'pdf',
        createdAt: DateTime.now(),
        pageCount: 1,
        thumbnailPath: imgPath,
        pages: [
          ScanPage(
            id: '${docId}_p1',
            imagePath: imgPath,
            paperSize: DocumentPaperSize.a4,
          ),
        ],
      );

      await ref.read(pendingUploadsControllerProvider.notifier).addDocument(doc);

      if (mounted) {
        setState(() => _isProcessing = false);
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('تم حفظ الصفحة المسطحة كـ PDF في المكتبة بنجاح!'),
              ],
            ),
            backgroundColor: Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e')),
        );
      }
    }
  }

  void _shareFlattenedImage() {
    if (_flattenedBytes == null) return;
    HapticFeedback.lightImpact();
    Share.shareXFiles(
      [XFile.fromData(_flattenedBytes!, mimeType: 'image/jpeg', name: 'flattened_page.jpg')],
      subject: 'صفحة كتاب مسطحة ومعدلة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تسوية انحناء صفحات الكتب (3D)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Text(
              'فرد انحناء الكعب وإزالة الظل الداخلي 100% محلياً',
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isComparing ? 'إيقاف المقارنة' : 'تفعيل المقارنة',
            icon: Icon(
              _isComparing
                  ? Icons.compare_arrows_rounded
                  : Icons.compare_rounded,
              color: const Color(0xFFF59E0B),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _isComparing = !_isComparing);
            },
          ),
          IconButton(
            tooltip: 'مشاركة الصورة المسطحة',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _flattenedBytes != null ? _shareFlattenedImage : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // Main Viewer with Split Slider
                    Expanded(
                      flex: 6,
                      child: Container(
                        color: isDark ? const Color(0xFF000000) : const Color(0xFFE5E5EA),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _buildComparisonViewer(),
                          ),
                        ),
                      ),
                    ),

                    // Controls Dock
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          border: Border(
                            top: BorderSide(
                              color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
                              width: 0.5,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                            physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Spine Position Selector
                              Row(
                                children: [
                                  const Text(
                                    'موضع كعب الكتاب:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  _buildSpineChip(
                                    position: BookSpinePosition.left,
                                    label: 'كعب أيسر',
                                    icon: Icons.border_left_rounded,
                                  ),
                                  const SizedBox(width: 6),
                                  _buildSpineChip(
                                    position: BookSpinePosition.right,
                                    label: 'كعب أيمن',
                                    icon: Icons.border_right_rounded,
                                  ),
                                  const SizedBox(width: 6),
                                  _buildSpineChip(
                                    position: BookSpinePosition.center,
                                    label: 'بالمنتصف',
                                    icon: Icons.vertical_split_rounded,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Curvature Strength Slider
                              Row(
                                children: [
                                  const Icon(Icons.tune_rounded, size: 16, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'قوة فرد التقوس: ${(_curvatureStrength * 100).round()}%',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFFF59E0B),
                                  thumbColor: const Color(0xFFF59E0B),
                                  overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                ),
                                child: Slider(
                                  value: _curvatureStrength,
                                  min: 0.15,
                                  max: 0.95,
                                  divisions: 16,
                                  onChanged: (val) {
                                    setState(() => _curvatureStrength = val);
                                  },
                                  onChangeEnd: (_) => _applyDewarp(),
                                ),
                              ),

                              // Gutter Shadow Neutralizer Toggle
                              SwitchListTile.adaptive(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                activeTrackColor: const Color(0xFFF59E0B),
                                secondary: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.wb_sunny_rounded,
                                      color: Color(0xFFF59E0B), size: 18),
                                ),
                                title: const Text(
                                  'تبييض سواد وظلال الكعب الداخلي',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                subtitle: const Text(
                                  'معادلة إضاءة التماس لتبدو الورقة ناصعة ومستوية',
                                  style: TextStyle(fontSize: 10.5),
                                ),
                                value: _removeGutterShadow,
                                onChanged: (val) {
                                  setState(() => _removeGutterShadow = val);
                                  _applyDewarp();
                                },
                              ),

                              const SizedBox(height: 12),

                              // Bottom Save Button
                              SizedBox(
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: _flattenedBytes != null && !_isProcessing
                                      ? () {
                                          HapticFeedback.mediumImpact();
                                          _saveToLibrary();
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                                  label: const Text(
                                    'حفظ الصفحة المسطحة بالمكتبة (PDF)',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                ),

                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Color(0xFFF59E0B)),
                              SizedBox(height: 14),
                              Text(
                                'جارٍ فرد الانحناء بالذكاء الاصطناعي 100% محلياً...',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSpineChip({
    required BookSpinePosition position,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _spinePosition == position;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _spinePosition = position);
        _applyDewarp();
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.black : null,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.black : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonViewer() {
    if (_flattenedBytes == null) {
      return Image.memory(
        _originalBytes,
        cacheWidth: 1440,
        fit: BoxFit.contain,
        errorBuilder: (ctx, err, st) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('تعذر فك ترميز الصورة الأصلية'),
            ],
          ),
        ),
      );
    }

    if (!_isComparing) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _flattenedBytes!,
          cacheWidth: 1440,
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, st) => Image.memory(
            _originalBytes,
            cacheWidth: 1440,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // Split Wipe Comparison View
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Bottom Layer: Original curved image
              Positioned.fill(
                child: Image.memory(
                  _originalBytes,
                  cacheWidth: 1440,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

              // Top Layer: Flattened dewarped image clipped to split ratio
              Positioned.fill(
                child: ClipRect(
                  clipper: _HorizontalSplitClipper(_splitRatio),
                  child: Image.memory(
                    _flattenedBytes!,
                    cacheWidth: 1440,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),

              // Divider Line
              Positioned(
                left: (w * _splitRatio) - 1.5,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: Colors.white,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),

              // Before / After floating labels
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'بعد (مسطح)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'قبل (منحني)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // Drag Detector
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    final newRatio = (details.localPosition.dx / w).clamp(0.05, 0.95);
                    setState(() => _splitRatio = newRatio);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  const _HorizontalSplitClipper(this.splitRatio);
  final double splitRatio;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * splitRatio, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalSplitClipper oldClipper) {
    return oldClipper.splitRatio != splitRatio;
  }
}
