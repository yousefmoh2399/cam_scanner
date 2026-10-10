import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/id_card_a4_service.dart';
import '../data/native_scanner_bridge.dart';
import 'scan_review_screen.dart';

/// Screen for combining Front and Back of an ID / Driver's License onto
/// a single A4 page strictly at true 1:1 physical size ($85.60 \times 53.98$ mm).
class IdCardA4Screen extends ConsumerStatefulWidget {
  const IdCardA4Screen({
    super.key,
    this.initialFrontPath,
    this.initialBackPath,
    this.initialTitle,
  });

  final String? initialFrontPath;
  final String? initialBackPath;
  final String? initialTitle;

  @override
  ConsumerState<IdCardA4Screen> createState() => _IdCardA4ScreenState();
}

class _IdCardA4ScreenState extends ConsumerState<IdCardA4Screen> {
  final IdCardA4Service _service = const IdCardA4Service();

  String? _frontPath;
  String? _backPath;
  late TextEditingController _titleController;
  late TextEditingController _customWatermarkController;

  IdCardA4Layout _selectedLayout = IdCardA4Layout.verticalCenter;
  IdCardColorFilter _selectedColorFilter = IdCardColorFilter.magicColor;
  IdSecurityWatermarkPreset _selectedWatermark = IdSecurityWatermarkPreset.none;

  bool _includeLabels = false;
  bool _includeCutGuidelines = false;
  bool _includeRuler = false;
  bool _includeCropMarks = false;
  bool _includeHeader = false;
  bool _includeSignaturesBox = false;
  bool _isProcessing = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _frontPath = widget.initialFrontPath;
    _backPath = widget.initialBackPath;
    _titleController = TextEditingController(
      text: widget.initialTitle ?? 'وثيقة إثبات الهوية الرسمية (National ID)',
    );
    _customWatermarkController = TextEditingController(text: 'صورة طبق الأصل فقط');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customWatermarkController.dispose();
    super.dispose();
  }

  bool get _canExport =>
      _frontPath != null &&
      File(_frontPath!).existsSync() &&
      _backPath != null &&
      File(_backPath!).existsSync();

  IdCardA4Config _buildConfig() {
    return IdCardA4Config(
      frontImagePath: _frontPath!,
      backImagePath: _backPath!,
      layout: _selectedLayout,
      colorFilter: _selectedColorFilter,
      watermarkPreset: _selectedWatermark,
      customWatermarkText: _customWatermarkController.text,
      includeCardLabels: _includeLabels,
      includeCalibrationRuler: _includeRuler,
      includeCutGuidelines: _includeCutGuidelines,
      includeCornerCropMarks: _includeCropMarks,
      includeHeader: _includeHeader,
      includeOfficialSignaturesBox: _includeSignaturesBox,
      documentTitle: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'وثيقة إثبات الهوية الرسمية',
    );
  }

  Future<void> _pickImage(bool isFront) async {
    HapticFeedback.lightImpact();
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isFront ? 'التقاط الوجه الأمامي للبطاقة' : 'التقاط الوجه الخلفي للبطاقة',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _buildPickOption(
                icon: Icons.camera_alt_rounded,
                title: 'تصوير بالكاميرا فوراً',
                subtitle: 'مع ضبط الأبعاد والإطار تلقائياً',
                color: const Color(0xFF007AFF),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              const SizedBox(height: 8),
              _buildPickOption(
                icon: Icons.photo_library_rounded,
                title: 'اختيار من معرض الصور',
                subtitle: 'ملف صورة JPG أو PNG من الهاتف',
                color: const Color(0xFFAF52DE),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (docs.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPickOption(
                  icon: Icons.folder_special_rounded,
                  title: 'من مكتبة المستندات',
                  subtitle: 'استخدام صفحة ممسوحة مسبقاً (${docs.length} مستند)',
                  color: const Color(0xFF34C759),
                  onTap: () => Navigator.pop(ctx, 'library'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    String? pickedPath;
    if (source == 'camera') {
      try {
        final draftsDir =
            await ref.read(localDocumentStoreProvider).getDraftsDirectory();
        final results = await NativeScannerBridge.startScan(
          destDir: draftsDir.path,
          batch: false,
        );
        if (results.isNotEmpty && mounted) {
          final res = results.first;
          pickedPath = await openScanReviewScreen(
            context,
            rawImagePath: res.path,
            initialCorners: res.corners,
            imageWidth: res.width,
            imageHeight: res.height,
          );
        }
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) {
          await showScannerPermissionDialog(context, e);
        }
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
      }
    } else if (source == 'gallery') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
        if (!mounted) return;
        pickedPath = await openScanReviewScreen(
          context,
          rawImagePath: res.files.first.path!,
        );
      }
    } else if (source == 'library') {
      if (!mounted) return;
      pickedPath = await _pickFromLibraryModal(docs);
    }

    if (pickedPath != null && mounted) {
      setState(() {
        if (isFront) {
          _frontPath = pickedPath;
        } else {
          _backPath = pickedPath;
        }
      });
    }
  }

  Future<String?> _pickFromLibraryModal(List<PendingUpload> docs) async {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'اختر مستنداً من مكتبتك',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (_, idx) {
                      final d = docs[idx];
                      final firstPage = d.previewImagePath ?? '';
                      return ListTile(
                        leading: firstPage.isNotEmpty && File(firstPage).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(firstPage),
                                  cacheWidth: 120,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.description_rounded),
                        title: Text(stripFileExtension(d.fileName)),
                        subtitle: Text(formatPageCount(d.effectivePageCount)),
                        onTap: () => Navigator.pop(ctx, firstPage),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rotateSlot(bool isFront) async {
    final path = isFront ? _frontPath : _backPath;
    if (path == null) return;

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final rotated = img.copyRotate(decoded, angle: 90);
      final newBytes = img.encodeJpg(rotated, quality: 95);
      final newPath = p.join(
        p.dirname(path),
        '${p.basenameWithoutExtension(path)}_rot_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(newPath).writeAsBytes(newBytes, flush: true);

      setState(() {
        if (isFront) {
          _frontPath = newPath;
        } else {
          _backPath = newPath;
        }
      });
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تدوير الصورة: $e')),
        );
      }
    }
  }

  void _swapSlots() {
    HapticFeedback.mediumImpact();
    setState(() {
      final tmp = _frontPath;
      _frontPath = _backPath;
      _backPath = tmp;
    });
  }

  Future<void> _previewPdf() async {
    if (!_canExport) return;
    HapticFeedback.lightImpact();
    final config = _buildConfig();
    await Printing.layoutPdf(
      onLayout: (_) => _service.buildPdfBytes(config),
      name: 'بطاقة_هوية_A4_مقاس_1_1.pdf',
    );
  }

  Future<void> _saveAndSharePdf() async {
    if (!_canExport) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ إنشاء وتجهيز ورقة A4 بالأبعاد الدقيقة...';
    });

    try {
      final config = _buildConfig();
      final filePath = await _service.savePdfToFile(config);

      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(filePath);
      final fileSize = file.existsSync() ? file.lengthSync() : 0;
      final docName = _titleController.text.trim().isNotEmpty
          ? '${_titleController.text.trim()}.pdf'
          : 'بطاقة_هوية_A4_مقاس_1_1_$timeStamp.pdf';

      final doc = PendingUpload(
        id: 'id_a4_$timeStamp',
        fileName: docName,
        filePath: filePath,
        fileSize: fileSize,
        createdAt: DateTime.now(),
        pageCount: 1,
        thumbnailPath: _frontPath,
        pages: [
          ScanPage(
            id: 'p_id_front_$timeStamp',
            imagePath: _frontPath!,
          ),
          if (_backPath != null)
            ScanPage(
              id: 'p_id_back_$timeStamp',
              imagePath: _backPath!,
            ),
        ],
      );

      await ref.read(pendingUploadsControllerProvider.notifier).addDocument(doc);

      if (!mounted) return;
      HapticFeedback.mediumImpact();

      // Show result sheet
      _showResultSheet(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إنشاء الملف: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showResultSheet(String filePath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final file = File(filePath);
    final size = file.existsSync() ? formatFileSize(file.lengthSync()) : '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF34C759),
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'تم تجهيز ورقة A4 بنجاح (مقياس 1:1)',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'أبعاد البطاقة مطابقة تماماً للمعيار الدولي (85.6 × 54 مم) وجاهزة للطباعة والتقديم • $size',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 22),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 19),
                      label: const Text('طباعة فورية'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _previewPdf();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 19),
                      label: const Text('مشاركة PDF'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Share.shareXFiles([XFile(filePath)], text: 'بطاقة هوية A4 بمقاس طبيعي 1:1');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(filePath);
                },
                child: const Text('فتح في عارض المستندات'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'بطاقة وش وظهر A4 (مقياس 1:1)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              'الأبعاد الفيزيائية الحقيقية CR-80 • جاهز للطباعة الورقية',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (_frontPath != null && _backPath != null)
            IconButton(
              tooltip: 'عكس الوجهين',
              icon: const Icon(Icons.swap_vert_rounded),
              onPressed: _swapSlots,
            ),
          IconButton(
            tooltip: 'معاينة الطباعة 1:1',
            icon: const Icon(Icons.remove_red_eye_rounded),
            onPressed: _canExport ? _previewPdf : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Notice Card
              _buildDimensionsNotice(isDark),
              const SizedBox(height: 14),

              // Dual Capture Slots (Compact Side-by-Side 50% / 50%)
              _buildSlotsCard(isDark),
              const SizedBox(height: 14),

              // Layout Selector (3-Segment Apple Selector)
              _buildLayoutSelector(isDark),
              const SizedBox(height: 14),

              // Collapsible Advanced Settings (Filters, Watermark, Extra Margins, Title)
              _buildAdvancedOptionsCard(isDark),
              const SizedBox(height: 14),

              // Visual Live Sheet Preview
              _buildLiveSheetPreview(isDark),
            ],
          ),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242426) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDimensionsNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF007AFF).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.straighten_rounded,
              color: Color(0xFF007AFF),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أبعاد فيزيائية دقيقة 100% (85.60 × 53.98 مم)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'يتم وضع وجهي البطاقة بدقة المليمتر على ورقة A4، بحيث تخرج من الطابعة بحجم بطاقتك الأصلية تماماً بدون تكبير أو تصغير.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildCompactSlot(
                  isFront: true,
                  imagePath: _frontPath,
                  label: 'الوجه الأمامي',
                  subtitle: 'Front Side',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompactSlot(
                  isFront: false,
                  imagePath: _backPath,
                  label: 'الوجه الخلفي',
                  subtitle: 'Back Side',
                  isDark: isDark,
                ),
              ),
            ],
          ),
          if (_frontPath != null || _backPath != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onPressed: (_frontPath != null && _backPath != null) ? _swapSlots : null,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text(
                    'تبديل الوجهين',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _frontPath = null;
                      _backPath = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                  label: const Text(
                    'مسح الوجهين',
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSlot({
    required bool isFront,
    required String? imagePath,
    required String label,
    required String subtitle,
    required bool isDark,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return AspectRatio(
      aspectRatio: 85.6 / 54.0,
      child: Material(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _pickImage(isFront),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasImage
                    ? const Color(0xFF007AFF)
                    : (isDark ? Colors.white12 : Colors.black12),
                width: hasImage ? 1.5 : 1.0,
              ),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(imagePath), cacheWidth: 500, fit: BoxFit.cover),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _rotateSlot(isFront),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.rotate_right_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setState(() {
                                  if (isFront) {
                                    _frontPath = null;
                                  } else {
                                    _backPath = null;
                                  }
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_a_photo_rounded,
                          color: Color(0xFF007AFF),
                          size: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dashboard_customize_rounded, size: 18, color: Color(0xFF007AFF)),
              SizedBox(width: 8),
              Text(
                'تخطيط وضع البطاقة في ورقة A4',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: IdCardA4Layout.values.map((layout) {
              final isSel = _selectedLayout == layout;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Material(
                    color: isSel
                        ? const Color(0xFF007AFF)
                        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedLayout = layout);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        alignment: Alignment.center,
                        child: Text(
                          layout.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSel
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedOptionsCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xFF007AFF), size: 18),
          ),
          title: const Text(
            'خيارات متقدمة، فلاتر، وعلامة مائية',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          subtitle: const Text(
            'تخصيص الفلتر، الختم الأمني، والمسطرة وعنوان الوثيقة',
            style: TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Title Field
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'عنوان المستند الرسمي',
                      isDense: true,
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Filter selector
                  const Text(
                    'فلتر تحسين الوضوح:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: IdCardColorFilter.values.map((f) {
                      final isSel = _selectedColorFilter == f;
                      return ChoiceChip(
                        label: Text(f.label, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) setState(() => _selectedColorFilter = f);
                        },
                        selectedColor: const Color(0xFF007AFF).withValues(alpha: 0.18),
                        labelStyle: TextStyle(
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                          color: isSel ? const Color(0xFF007AFF) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Watermark selector
                  const Text(
                    'العلامة المائية والختم الأمني:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: IdSecurityWatermarkPreset.values.map((w) {
                      final isSel = _selectedWatermark == w;
                      return ChoiceChip(
                        label: Text(w.label, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) setState(() => _selectedWatermark = w);
                        },
                        selectedColor: Colors.red.withValues(alpha: 0.16),
                        labelStyle: TextStyle(
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                          color: isSel ? Colors.red.shade700 : null,
                        ),
                      );
                    }).toList(),
                  ),
                  if (_selectedWatermark == IdSecurityWatermarkPreset.custom) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _customWatermarkController,
                      decoration: InputDecoration(
                        labelText: 'نص الختم الأمني المخصص',
                        hintText: 'مثلاً: مخصص لمعاملة بنكية فقط',
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  // Toggles
                  SwitchListTile.adaptive(
                    value: _includeLabels,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'تسمية الوجهين والمقاسات (85.6 × 54 مم)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    activeThumbColor: const Color(0xFF007AFF),
                    onChanged: (val) => setState(() => _includeLabels = val),
                  ),
                  SwitchListTile.adaptive(
                    value: _includeCutGuidelines,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'خط القص القياسي المنقّط (✂)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    activeThumbColor: const Color(0xFF007AFF),
                    onChanged: (val) => setState(() => _includeCutGuidelines = val),
                  ),
                  SwitchListTile.adaptive(
                    value: _includeRuler,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'مسطرة التحقق من المقاس 1:1 في الأسفل (5 سم)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    activeThumbColor: const Color(0xFF007AFF),
                    onChanged: (val) => setState(() => _includeRuler = val),
                  ),
                  SwitchListTile.adaptive(
                    value: _includeCropMarks,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'علامات أركان القص الزاوية (Crop Marks)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    activeThumbColor: const Color(0xFF007AFF),
                    onChanged: (val) => setState(() => _includeCropMarks = val),
                  ),
                  SwitchListTile.adaptive(
                    value: _includeHeader,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'ترويسة رسمية وتاريخ الإصدار في الأعلى',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    activeThumbColor: const Color(0xFF007AFF),
                    onChanged: (val) => setState(() => _includeHeader = val),
                  ),
                  if (_selectedLayout == IdCardA4Layout.sideBySideTop) ...[
                    SwitchListTile.adaptive(
                      value: _includeSignaturesBox,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'صندوق الأختام والتوقيعات الرسمية',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      activeThumbColor: const Color(0xFF007AFF),
                      onChanged: (val) => setState(() => _includeSignaturesBox = val),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSheetPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'معاينة شكل ورقة A4 التفاعلية',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_canExport) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _previewPdf,
                  icon: const Icon(Icons.fullscreen_rounded, size: 16),
                  label: const Text('معاينة كاملة'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 210,
              height: 297,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade400, width: 0.8),
              ),
              child: _buildSheetContentMiniPreview(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetContentMiniPreview() {
    return Column(
      children: [
        if (_includeHeader) ...[
          Container(
            height: 12,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'وثيقة إثبات الهوية',
                  style: TextStyle(fontSize: 5, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                Text(
                  'A4 • 1:1 Scale',
                  style: TextStyle(fontSize: 4, color: Colors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: _buildMiniLayoutCards(),
        ),
        if (_includeRuler) ...[
          const SizedBox(height: 4),
          Container(
            height: 6,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('معيار 1:1', style: TextStyle(fontSize: 3.5, color: Colors.black)),
                Container(width: 40, height: 2, color: Colors.black),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMiniLayoutCards() {
    final hasFront = _frontPath != null && File(_frontPath!).existsSync();
    final hasBack = _backPath != null && File(_backPath!).existsSync();

    if (_selectedLayout == IdCardA4Layout.verticalCenter) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_includeLabels) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text('الوجه الأمامي • 85.6 × 54 مم', style: TextStyle(fontSize: 4, color: Colors.black87)),
            ),
            const SizedBox(height: 1),
          ],
          _buildMiniCard(hasFront ? _frontPath : null, 'الوجه الأمامي'),
          if (_includeCutGuidelines) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Text('✂', style: TextStyle(fontSize: 5, color: Colors.grey)),
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: Colors.grey.shade400,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          if (_includeLabels) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text('الوجه الخلفي • 85.6 × 54 مم', style: TextStyle(fontSize: 4, color: Colors.black87)),
            ),
            const SizedBox(height: 1),
          ],
          _buildMiniCard(hasBack ? _backPath : null, 'الوجه الخلفي'),
        ],
      );
    } else if (_selectedLayout == IdCardA4Layout.sideBySideTop) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  if (_includeLabels) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text('الوجه الأمامي', style: TextStyle(fontSize: 4, color: Colors.black87)),
                    ),
                    const SizedBox(height: 1),
                  ],
                  _buildMiniCard(hasFront ? _frontPath : null, 'الوجه الأمامي', width: 85, height: 54),
                ],
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (_includeLabels) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text('الوجه الخلفي', style: TextStyle(fontSize: 4, color: Colors.black87)),
                    ),
                    const SizedBox(height: 1),
                  ],
                  _buildMiniCard(hasBack ? _backPath : null, 'الوجه الخلفي', width: 85, height: 54),
                ],
              ),
            ],
          ),
          if (_includeCutGuidelines) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('✂', style: TextStyle(fontSize: 4, color: Colors.grey)),
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ],
            ),
          ],
          if (_includeSignaturesBox) ...[
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'مساحة أختام وتوقيعات الجهة الرسمية',
                  style: TextStyle(fontSize: 5, color: Colors.grey),
                ),
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
        ],
      );
    } else {
      // Foldable
      return Center(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMiniCard(hasFront ? _frontPath : null, 'الوجه الأمامي', width: 95, height: 60),
              Container(width: 95, height: 0.5, color: Colors.blueGrey),
              _buildMiniCard(hasBack ? _backPath : null, 'الوجه الخلفي', width: 95, height: 60),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMiniCard(String? path, String placeholder, {double width = 110, double height = 70}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.grey.shade400, width: 0.5),
      ),
      child: path != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.file(File(path), cacheWidth: 320, fit: BoxFit.cover),
            )
          : Center(
              child: Text(
                placeholder,
                style: const TextStyle(fontSize: 6, color: Colors.grey),
              ),
            ),
    );
  }

  Widget _buildPickOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: isDark ? Colors.white38 : Colors.black38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121214) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 1. Tonal Apple Print Button (50%)
            Expanded(
              child: Material(
                color: _canExport
                    ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7))
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _canExport
                      ? () {
                          HapticFeedback.lightImpact();
                          _previewPdf();
                        }
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _canExport
                            ? (isDark
                                ? Colors.white12
                                : Colors.black.withValues(alpha: 0.06))
                            : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _canExport
                                ? (isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.print_rounded,
                            size: 18,
                            color: _canExport
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'طباعة فورية',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: _canExport
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'بالمقاس الطبيعي 1:1',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  color: _canExport
                                      ? (isDark ? Colors.white60 : Colors.black54)
                                      : Colors.grey,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 2. Primary Vibrant Blue Export Button (50%)
            Expanded(
              child: Material(
                color: _canExport
                    ? const Color(0xFF007AFF)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _canExport
                      ? () {
                          HapticFeedback.mediumImpact();
                          _saveAndSharePdf();
                        }
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _canExport
                          ? [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _canExport
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 18,
                            color: _canExport ? Colors.white : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _canExport ? 'تصدير ورقة A4' : 'أكمل الوجهين',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: _canExport ? Colors.white : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _canExport ? 'حفظ ومشاركة PDF' : 'التقط الأمامي والخلفي',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  color: _canExport ? Colors.white70 : Colors.grey,
                                ),
                                maxLines: 1,
                              ),
                            ],
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
      ),
    );
  }
}
