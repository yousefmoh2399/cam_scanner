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
        if (results.isNotEmpty) pickedPath = results.first.path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
      }
    } else if (source == 'gallery') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.isNotEmpty) {
        pickedPath = res.files.first.path;
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

              // Dual Capture Slots
              _buildSlotsCard(isDark),
              const SizedBox(height: 16),

              // Layout Selector
              _buildLayoutSelector(isDark),
              const SizedBox(height: 16),

              // Color & Quality Filter
              _buildFilterSelector(isDark),
              const SizedBox(height: 16),

              // Anti-Fraud Watermark
              _buildWatermarkSelector(isDark),
              const SizedBox(height: 16),

              // Settings toggles (Ruler, crop marks, header)
              _buildTogglesCard(isDark),
              const SizedBox(height: 16),

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          // Front Slot
          _buildSingleSlot(
            isFront: true,
            imagePath: _frontPath,
            label: 'الوجه الأمامي للبطاقة (Front)',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          // Divider with swap button
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white12 : Colors.black12,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: InkWell(
                  onTap: (_frontPath != null && _backPath != null) ? _swapSlots : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_vert_rounded, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'تبديل الوجهين',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white12 : Colors.black12,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Back Slot
          _buildSingleSlot(
            isFront: false,
            imagePath: _backPath,
            label: 'الوجه الخلفي للبطاقة (Back)',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSingleSlot({
    required bool isFront,
    required String? imagePath,
    required String label,
    required bool isDark,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasImage)
              Row(
                children: [
                  InkWell(
                    onTap: () => _rotateSlot(isFront),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.rotate_right_rounded, size: 17),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() {
                      if (isFront) {
                        _frontPath = null;
                      } else {
                        _backPath = null;
                      }
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 17, color: Colors.red),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 85.6 / 54.0,
          child: InkWell(
            onTap: () => _pickImage(isFront),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
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
                          Image.file(File(imagePath), fit: BoxFit.cover),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'تغيير',
                                    style: TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_a_photo_rounded,
                            color: Color(0xFF007AFF),
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isFront ? 'التقاط الوجه الأمامي' : 'التقاط الوجه الخلفي',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'انقر للتصوير أو اختيار صورة',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تخطيط وضع البطاقة في ورقة A4',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          for (final layout in IdCardA4Layout.values) ...[
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedLayout = layout);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedLayout == layout
                      ? const Color(0xFF007AFF).withValues(alpha: 0.1)
                      : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedLayout == layout
                        ? const Color(0xFF007AFF)
                        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                    width: _selectedLayout == layout ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedLayout == layout
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _selectedLayout == layout ? const Color(0xFF007AFF) : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            layout.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _selectedLayout == layout ? const Color(0xFF007AFF) : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            layout.description,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          const Text(
            'فلتر تحسين وضوح بيانات الهوية',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: IdCardColorFilter.values.map((f) {
              final isSel = _selectedColorFilter == f;
              return ChoiceChip(
                label: Text(f.label),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedColorFilter = f);
                },
                selectedColor: const Color(0xFF007AFF).withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? const Color(0xFF007AFF) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWatermarkSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security_rounded, color: Colors.red, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'علامة مائية أمنية لحماية الهوية من التزوير',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      'طباعة ختم حماية مائل عبر البطاقة لمنع استغلالها إلكترونياً',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: IdSecurityWatermarkPreset.values.map((w) {
              final isSel = _selectedWatermark == w;
              return ChoiceChip(
                label: Text(w.label),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedWatermark = w);
                },
                selectedColor: Colors.red.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? Colors.red.shade700 : null,
                ),
              );
            }).toList(),
          ),
          if (_selectedWatermark == IdSecurityWatermarkPreset.custom) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customWatermarkController,
              decoration: InputDecoration(
                labelText: 'اكتب نص الختم الأمني',
                hintText: 'مثلاً: مخصص لمعاملة بيع سيارة فقط',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTogglesCard(bool isDark) {
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF007AFF), size: 18),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عناصر وهوامش الورقة الإضافية',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      Text(
                        'مغلقة افتراضياً لتوفير طباعة نقية ونظيفة للصور فقط بدون نصوص',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _includeLabels,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تسمية الوجهين والمقاسات (الوجه الأمامي / الخلفي)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'كتابة نصوص وأبعاد (85.6 × 54 مم) فوق كل صورة',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              activeThumbColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _includeLabels = val),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: _includeCutGuidelines,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'خط القص القياسي المنقّط (✂)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'خط فاصل بمنتصف الورقة لتسهيل القص الدقيق',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              activeThumbColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _includeCutGuidelines = val),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: _includeRuler,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'مسطرة التحقق من المقاس 1:1 في الأسفل (5 سم)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'شريط أسفل الورقة للتأكد من عدم تصغير الطابعة للمستند',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              activeThumbColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _includeRuler = val),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: _includeCropMarks,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'علامات أركان القص الزاوية (Crop Marks)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'تحديد زوايا البطاقة الأربعة للمساعدة في القص بمقص يدوي',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              activeThumbColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _includeCropMarks = val),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: _includeHeader,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'ترويسة رسمية وتاريخ الإصدار في الأعلى',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'تضمين عنوان الوثيقة وتاريخ استخراجها في أعلى الورقة',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              activeThumbColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _includeHeader = val),
            ),
            if (_selectedLayout == IdCardA4Layout.sideBySideTop) ...[
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _includeSignaturesBox,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'صندوق الأختام والتوقيعات الرسمية',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'مساحة سفلية لتوقيع العميل وختم الجهة الحكومية أو البنك',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                activeThumbColor: const Color(0xFF007AFF),
                onChanged: (val) => setState(() => _includeSignaturesBox = val),
              ),
            ],
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
              child: Image.file(File(path), fit: BoxFit.cover),
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Colors.grey, size: 18),
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
          color: isDark ? const Color(0xFF101012) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: Row(
          children: [
            // Instant Print Button
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.print_rounded, size: 19),
                label: const Text(
                  'طباعة فورية',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: _canExport ? _previewPdf : null,
              ),
            ),
            const SizedBox(width: 10),
            // Primary Save & Share Button
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                label: Text(
                  _canExport ? 'تصدير ورقة A4 (1:1)' : 'التقط وجهي البطاقة أولاً',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                onPressed: _canExport ? _saveAndSharePdf : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
