import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/motion_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/id_card_a4_service.dart';
import '../data/native_scanner_bridge.dart';
import 'scan_review_screen.dart';

/// Screen for combining Front and Back of an ID / Driver's License onto
/// a single A4 page strictly at true 1:1 physical size (85.60 x 53.98 mm).
///
/// Redesigned with Apple Bento Paper Design:
/// - Refined, balanced typography for Arabic (Cairo) without oversized glyphs.
/// - Integrated interactive ID Card Bento Stage with real card proportions.
/// - Segmented Apple Bento layout selector with visual mini-diagrams.
/// - Proportional A4 paper live preview with true aspect ratio.
/// - Apple Inset Grouped settings with iOS-style adaptive toggles and filters.
/// - Fully responsive across small phones (iPhone SE / 320px) up to tablets.
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
  bool _includeCutGuidelines = true;
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
      text: widget.initialTitle ?? 'وثيقة إثبات الهوية الرسمية',
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
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
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
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'اختر طريقة إدراج صورة البطاقة للدمج على ورقة A4',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
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
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
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
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                        title: Text(
                          stripFileExtension(d.fileName),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          formatPageCount(d.effectivePageCount),
                          style: const TextStyle(fontSize: 11),
                        ),
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
      final newPath = await compute((String pth) async {
        final file = File(pth);
        if (!file.existsSync()) return null;
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;

        final rotated = img.copyRotate(decoded, angle: 90);
        final newBytes = img.encodeJpg(rotated, quality: 92);
        final targetPath = p.join(
          p.dirname(pth),
          '${p.basenameWithoutExtension(pth)}_rot_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await File(targetPath).writeAsBytes(newBytes, flush: true);
        return targetPath;
      }, path);

      if (newPath != null && mounted) {
        setState(() {
          if (isFront) {
            _frontPath = newPath;
          } else {
            _backPath = newPath;
          }
        });
        HapticFeedback.selectionClick();
      }
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
      name: 'بطاقة_هوية_A4_مقياس_1_1.pdf',
    );
  }

  Future<void> _saveAndSharePdf() async {
    if (!_canExport) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ إعداد ورقة A4 بالأبعاد الحقيقية 1:1...';
    });

    try {
      final config = _buildConfig();
      final filePath = await _service.savePdfToFile(config);

      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(filePath);
      final fileSize = file.existsSync() ? file.lengthSync() : 0;
      final docName = _titleController.text.trim().isNotEmpty
          ? '${_titleController.text.trim()}.pdf'
          : 'بطاقة_هوية_A4_مقياس_1_1_$timeStamp.pdf';

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
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF34C759),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'تم تجهيز ورقة A4 بنجاح',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'أبعاد البطاقة مطابقة تماماً للمقياس الحقيقي 1:1 وجاهزة للطباعة والتقديم • $size',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text(
                        'طباعة فورية',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _previewPdf();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'مشاركة PDF',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Share.shareXFiles([XFile(filePath)], text: 'بطاقة هوية A4 بمقاس طبيعي 1:1');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(filePath);
                },
                child: const Text(
                  'فتح في عارض المستندات',
                  style: TextStyle(fontSize: 12.5),
                ),
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
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF121214) : Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'بطاقة وش وضهر',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'ورقة A4 • مقياس 1:1 حقيقي للطباعة',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
              ),
            ),
          ],
        ),
        actions: [
          if (_frontPath != null && _backPath != null)
            IconButton(
              tooltip: 'تبديل الوجهين',
              icon: const Icon(Icons.swap_horiz_rounded, size: 22),
              onPressed: _swapSlots,
            ),
          IconButton(
            tooltip: 'معاينة الطباعة',
            icon: const Icon(Icons.remove_red_eye_outlined, size: 22),
            onPressed: _canExport ? _previewPdf : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth > 600;
          final content = ListView(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 32 : 16,
              14,
              isTablet ? 32 : 16,
              100,
            ),
            children: [
              // 1. Bento Stage: Interactive Dual-Card Capture Slot
              _buildAppleBentoStage(isDark),
              const SizedBox(height: 14),

              // 2. Bento Card: A4 Page Layout Selector
              _buildAppleLayoutSelector(isDark),
              const SizedBox(height: 14),

              // 3. Bento Card: Interactive Live A4 Preview
              _buildAppleLiveSheetPreview(isDark),
              const SizedBox(height: 14),

              // 4. Bento Card: Apple Inset Grouped Document & Print Settings
              _buildAppleSettingsGroup(isDark),
            ],
          );

          return Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: content,
                ),
              ),

              // Loading overlay
              if (_isProcessing)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF242426) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2.8),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
      bottomNavigationBar: _buildAppleBottomBar(isDark),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE BENTO HERO STAGE (DUAL CARD SLOTS)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppleBentoStage(bool isDark) {
    final hasBoth = _canExport;
    final hasOne = (_frontPath != null && File(_frontPath!).existsSync()) ||
        (_backPath != null && File(_backPath!).existsSync());

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF007AFF),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تصوير وجهي البطاقة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'الوجه الأمامي والظهر بمقاس البطاقة الحقيقي 1:1',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: hasBoth
                      ? const Color(0xFF34C759).withValues(alpha: 0.14)
                      : (hasOne
                          ? const Color(0xFFFF9500).withValues(alpha: 0.14)
                          : (isDark ? Colors.white10 : const Color(0xFFF2F2F7))),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasBoth
                          ? Icons.check_circle_rounded
                          : (hasOne ? Icons.timelapse_rounded : Icons.crop_free_rounded),
                      size: 12,
                      color: hasBoth
                          ? const Color(0xFF34C759)
                          : (hasOne ? const Color(0xFFFF9500) : const Color(0xFF8E8E93)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasBoth
                          ? 'جاهز 1:1'
                          : (hasOne ? '1 من 2' : 'مقياس طبيعي'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: hasBoth
                            ? const Color(0xFF34C759)
                            : (hasOne ? const Color(0xFFFF9500) : const Color(0xFF8E8E93)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Two Side-by-Side Physical Card Slots (Ratio ~1.586)
          Row(
            children: [
              Expanded(
                child: _buildPhysicalCardSlot(
                  isFront: true,
                  imagePath: _frontPath,
                  title: 'الوجه الأمامي',
                  hint: 'اضغط للتصوير',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPhysicalCardSlot(
                  isFront: false,
                  imagePath: _backPath,
                  title: 'الوجه الخلفي',
                  hint: 'اضغط للتصوير',
                  isDark: isDark,
                ),
              ),
            ],
          ),

          // Action Toolbar below slots (if at least one photo exists)
          if (hasOne) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (hasBoth)
                  InkWell(
                    onTap: _swapSlots,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 15,
                            color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'تبديل الوجهين',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _frontPath = null;
                      _backPath = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFFF3B30)),
                        SizedBox(width: 4),
                        Text(
                          'مسح الوجهين',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF3B30),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhysicalCardSlot({
    required bool isFront,
    required String? imagePath,
    required String title,
    required String hint,
    required bool isDark,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return AspectRatio(
      aspectRatio: 85.60 / 53.98,
      child: Material(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _pickImage(isFront),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasImage
                    ? const Color(0xFF007AFF).withValues(alpha: 0.6)
                    : (isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
                width: hasImage ? 1.4 : 1.0,
              ),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(imagePath),
                          cacheWidth: 500,
                          fit: BoxFit.cover,
                        ),
                        // Top label badge (Frosted Glass)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        // Bottom floating actions
                        Positioned(
                          bottom: 5,
                          left: 5,
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
                                    size: 13,
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
                                    color: const Color(0xFFFF3B30).withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 13,
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
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_a_photo_rounded,
                                color: Color(0xFF007AFF),
                                size: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              hint,
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE LAYOUT SELECTOR (BENTO SEGMENTED TABS)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppleLayoutSelector(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF5856D6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.view_agenda_outlined,
                  color: Color(0xFF5856D6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'توزيع البطاقة على الورقة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'اختر مكان تموضع الوجهين في ورقة A4',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLayoutTabItem(
                  layout: IdCardA4Layout.verticalCenter,
                  title: 'رأسي بالمنتصف',
                  subtitle: 'النمط الرسمي المعتمد',
                  isDark: isDark,
                  sheetDiagram: _buildMiniDiagramVertical(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLayoutTabItem(
                  layout: IdCardA4Layout.sideBySideTop,
                  title: 'متجاوران بالأعلى',
                  subtitle: 'مساحة للأختام بالأسفل',
                  isDark: isDark,
                  sheetDiagram: _buildMiniDiagramSideBySide(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLayoutTabItem(
                  layout: IdCardA4Layout.foldable,
                  title: 'تنسيق الطي',
                  subtitle: 'للقص والطي ككارنيه',
                  isDark: isDark,
                  sheetDiagram: _buildMiniDiagramFoldable(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutTabItem({
    required IdCardA4Layout layout,
    required String title,
    required String subtitle,
    required bool isDark,
    required Widget sheetDiagram,
  }) {
    final isSel = _selectedLayout == layout;

    return Material(
      color: isSel
          ? (isDark
              ? const Color(0xFF007AFF).withValues(alpha: 0.18)
              : const Color(0xFF007AFF).withValues(alpha: 0.08))
          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedLayout = layout);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
              width: isSel ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 38,
                child: Center(child: sheetDiagram),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                  color: isSel
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniDiagramVertical() {
    return Container(
      width: 26,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black26, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Container(height: 10, decoration: BoxDecoration(color: const Color(0xFF007AFF), borderRadius: BorderRadius.circular(1.5))),
          Container(height: 0.5, color: Colors.black12),
          Container(height: 10, decoration: BoxDecoration(color: const Color(0xFF007AFF), borderRadius: BorderRadius.circular(1.5))),
        ],
      ),
    );
  }

  Widget _buildMiniDiagramSideBySide() {
    return Container(
      width: 26,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black26, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Container(height: 10, decoration: BoxDecoration(color: const Color(0xFF007AFF), borderRadius: BorderRadius.circular(1)))),
              const SizedBox(width: 2),
              Expanded(child: Container(height: 10, decoration: BoxDecoration(color: const Color(0xFF007AFF), borderRadius: BorderRadius.circular(1)))),
            ],
          ),
          const Spacer(),
          Container(
            height: 12,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12, width: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDiagramFoldable() {
    return Container(
      width: 26,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black26, width: 0.6),
      ),
      child: Center(
        child: Container(
          width: 20,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26, width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            children: [
              Expanded(child: Container(color: const Color(0xFF007AFF).withValues(alpha: 0.4))),
              Container(height: 0.6, color: Colors.black45),
              Expanded(child: Container(color: const Color(0xFF007AFF).withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE LIVE SHEET PREVIEW (BENTO CARD)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppleLiveSheetPreview(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF34C759),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معاينة ورقة A4 للطباعة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'أبعاد الورقة الحقيقية 210 × 297 مم',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              if (_canExport)
                InkWell(
                  onTap: _previewPdf,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fullscreen_rounded,
                          size: 15,
                          color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'معاينة كاملة',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Paper simulation (True A4 Ratio 1 : 1.414)
          Center(
            child: Container(
              width: 190,
              height: 268,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade300, width: 0.8),
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
              border: Border(bottom: BorderSide(color: Colors.black26, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _titleController.text.trim().isNotEmpty
                        ? _titleController.text.trim()
                        : 'وثيقة إثبات الهوية الرسمية',
                    style: const TextStyle(fontSize: 4.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(
                  'A4 • 1:1',
                  style: TextStyle(fontSize: 4, color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: _buildMiniLayoutCards(),
        ),
        if (_includeRuler) ...[
          const SizedBox(height: 3),
          Container(
            height: 7,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('مقياس 5 سم', style: TextStyle(fontSize: 3.5, color: Colors.black87)),
                Container(width: 35, height: 1.5, color: Colors.black87),
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
          _buildMiniCard(hasFront ? _frontPath : null, 'الوجه الأمامي'),
          if (_includeCutGuidelines)
            Row(
              children: [
                const Text('✂', style: TextStyle(fontSize: 4.5, color: Colors.grey)),
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: Colors.grey.shade400,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ],
            ),
          _buildMiniCard(hasBack ? _backPath : null, 'الوجه الخلفي'),
        ],
      );
    } else if (_selectedLayout == IdCardA4Layout.sideBySideTop) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniCard(hasFront ? _frontPath : null, 'الأمامي', width: 78, height: 49),
              const SizedBox(width: 4),
              _buildMiniCard(hasBack ? _backPath : null, 'الخلفي', width: 78, height: 49),
            ],
          ),
          if (_includeCutGuidelines) ...[
            const SizedBox(height: 4),
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
                  border: Border.all(color: Colors.black12, width: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'مساحة أختام وتوقيعات الجهة الرسمية',
                  style: TextStyle(fontSize: 4.5, color: Colors.grey),
                ),
              ),
            ),
          ] else
            const Spacer(),
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
              _buildMiniCard(hasFront ? _frontPath : null, 'الوجه الأمامي', width: 88, height: 55),
              Container(width: 88, height: 0.5, color: Colors.black26),
              _buildMiniCard(hasBack ? _backPath : null, 'الوجه الخلفي', width: 88, height: 55),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMiniCard(String? path, String placeholder, {double width = 96, double height = 60}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.grey.shade300, width: 0.6),
      ),
      child: path != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(2.5),
              child: Image.file(File(path), cacheWidth: 300, fit: BoxFit.cover),
            )
          : Center(
              child: Text(
                placeholder,
                style: const TextStyle(fontSize: 6.5, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE INSET GROUPED SETTINGS (BENTO CARD)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppleSettingsGroup(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFFFF9500),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'خيارات المستند والطباعة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'الفلاتر، الختم الأمني، وإرشادات القص',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Document Title Field
          TextFormField(
            controller: _titleController,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: 'عنوان المستند',
              labelStyle: const TextStyle(fontSize: 12),
              isDense: true,
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFE5E5EA),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFE5E5EA),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF007AFF),
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Color Filter Selection
          const Text(
            'فلتر تحسين وضوح البطاقة',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: IdCardColorFilter.values.map((f) {
              final isSel = _selectedColorFilter == f;
              return ChoiceChip(
                label: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                selected: isSel,
                onSelected: (val) {
                  if (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedColorFilter = f);
                  }
                },
                selectedColor: const Color(0xFF007AFF).withValues(alpha: 0.16),
                side: BorderSide(
                  color: isSel
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                ),
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
                labelStyle: TextStyle(
                  color: isSel
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // 3. Security Watermark Selector
          const Text(
            'العلامة المائية والختم الأمني',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: IdSecurityWatermarkPreset.values.map((w) {
              final isSel = _selectedWatermark == w;
              return ChoiceChip(
                label: Text(
                  w.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                selected: isSel,
                onSelected: (val) {
                  if (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedWatermark = w);
                  }
                },
                selectedColor: const Color(0xFFFF3B30).withValues(alpha: 0.14),
                side: BorderSide(
                  color: isSel
                      ? const Color(0xFFFF3B30)
                      : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                ),
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
                labelStyle: TextStyle(
                  color: isSel
                      ? const Color(0xFFFF3B30)
                      : (isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                ),
              );
            }).toList(),
          ),

          if (_selectedWatermark == IdSecurityWatermarkPreset.custom) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _customWatermarkController,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                labelText: 'نص الختم المخصص',
                hintText: 'مثال: مخصص لمعاملة بنك مصر فقط',
                hintStyle: const TextStyle(fontSize: 11),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : const Color(0xFFE5E5EA),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 6),

          // 4. Inset Toggle Rows
          _buildInsetSwitchTile(
            title: 'خط القص القياسي المنقّط (✂)',
            subtitle: 'يسهّل قص الوجهين بدقة بعد الطباعة',
            value: _includeCutGuidelines,
            onChanged: (val) => setState(() => _includeCutGuidelines = val),
            isDark: isDark,
          ),
          _buildInsetSwitchTile(
            title: 'تسمية الوجهين والمقاسات',
            subtitle: 'طباعة نص تعريفي لكل وجه وأبعاده 85.6 × 54 مم',
            value: _includeLabels,
            onChanged: (val) => setState(() => _includeLabels = val),
            isDark: isDark,
          ),
          _buildInsetSwitchTile(
            title: 'مسطرة التحقق من المقاس 1:1 (5 سم)',
            subtitle: 'مسطرة قياس بالمليمتر للتأكد من دقة الطابعة',
            value: _includeRuler,
            onChanged: (val) => setState(() => _includeRuler = val),
            isDark: isDark,
          ),
          _buildInsetSwitchTile(
            title: 'علامات أركان القص الزاوية',
            subtitle: 'إرشادات زاوية للقص الاحترافي الدقيق',
            value: _includeCropMarks,
            onChanged: (val) => setState(() => _includeCropMarks = val),
            isDark: isDark,
          ),
          _buildInsetSwitchTile(
            title: 'ترويسة رسمية وتاريخ الإصدار',
            subtitle: 'طباعة العنوان وتاريخ اليوم أعلى الورقة',
            value: _includeHeader,
            onChanged: (val) => setState(() => _includeHeader = val),
            isDark: isDark,
          ),
          if (_selectedLayout == IdCardA4Layout.sideBySideTop)
            _buildInsetSwitchTile(
              title: 'صندوق أختام وتوقيعات الجهة',
              subtitle: 'تخصيص مساحة فارغة مخصصة للموظف والختم',
              value: _includeSignaturesBox,
              onChanged: (val) => setState(() => _includeSignaturesBox = val),
              isDark: isDark,
            ),
        ],
      ),
    );
  }

  Widget _buildInsetSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: const Color(0xFF007AFF),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              onChanged(val);
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODAL PICK OPTION ITEM
  // ═══════════════════════════════════════════════════════════════════════════

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLE BOTTOM ACTION BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppleBottomBar(bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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
            // 1. Tonal Apple Print Button
            Expanded(
              child: Material(
                color: _canExport
                    ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7))
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: _canExport
                      ? () {
                          HapticFeedback.lightImpact();
                          _previewPdf();
                        }
                      : null,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: _canExport
                            ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06))
                            : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.print_rounded,
                          size: 18,
                          color: _canExport
                              ? (isDark ? Colors.white : const Color(0xFF1C1C1E))
                              : const Color(0xFF8E8E93),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'طباعة فورية',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: _canExport
                                  ? (isDark ? Colors.white : const Color(0xFF1C1C1E))
                                  : const Color(0xFF8E8E93),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 2. Primary Vibrant Apple Blue Save & Share Button
            Expanded(
              child: Material(
                color: _canExport
                    ? const Color(0xFF007AFF)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: _canExport
                      ? () {
                          HapticFeedback.mediumImpact();
                          _saveAndSharePdf();
                        }
                      : null,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
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
                        Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 18,
                          color: _canExport ? Colors.white : const Color(0xFF8E8E93),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _canExport ? 'حفظ ومشاركة A4' : 'أكمل الوجهين أولاً',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: _canExport ? Colors.white : const Color(0xFF8E8E93),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
