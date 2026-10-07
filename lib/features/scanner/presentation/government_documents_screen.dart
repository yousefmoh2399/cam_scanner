import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../data/government_preset_service.dart';
import '../data/native_scanner_bridge.dart';
import 'widgets/apple_bottom_nav_bar.dart';
import 'id_card_a4_screen.dart';
import 'scan_review_screen.dart';

/// Available document modes in the official studio.
enum OfficialDocMode {
  idCard(
    'بطاقة وجهين',
    Icons.badge_rounded,
    'دمج وجهي البطاقة في A4 (معيار ISO ID-1)',
  ),
  passport(
    'جواز السفر',
    Icons.menu_book_rounded,
    'تنسيق صفحة البيانات (معيار ICAO الدولي)',
  ),
  certificate(
    'وثائق وشهادات',
    Icons.workspace_premium_rounded,
    'تنسيق وتأطير رسمي للشهادات والعقود',
  ),
  photos(
    'صور التأشيرات',
    Icons.photo_camera_front_rounded,
    'طباعة فورية بمقاسات شنغن وأمريكا والعالم',
  ),
  compress(
    'ضغط المستندات',
    Icons.speed_rounded,
    'تقليص دقيق للحجم للبوابات والسفارات',
  );

  const OfficialDocMode(this.label, this.icon, this.description);
  final String label;
  final IconData icon;
  final String description;
}

/// A world-class, international Official ID & Document Studio conforming
/// to Apple Human Interface Guidelines.
///
/// Supports:
/// - 2-in-1 Dual Side ID & Driver's License cards (ISO/IEC 7810 ID-1 standard)
/// - International Passport Data Pages (ICAO Doc 9303 standard)
/// - Official Documents & Academic Certificates (Landscape & Portrait)
/// - Universal Visa & Passport Photo Sheets (Schengen 35x45mm, US Visa 2x2", 4x6cm, 3x4cm)
/// - Precision File Compression for Global Embassies and Online Portals (<100KB to <2MB)
class GovernmentDocumentsScreen extends ConsumerStatefulWidget {
  const GovernmentDocumentsScreen({
    super.key,
    this.initialMode = OfficialDocMode.idCard,
  });

  final OfficialDocMode initialMode;

  @override
  ConsumerState<GovernmentDocumentsScreen> createState() =>
      _GovernmentDocumentsScreenState();
}

/// Backwards-compatibility alias
typedef OfficialDocumentsScreen = GovernmentDocumentsScreen;

class _GovernmentDocumentsScreenState
    extends ConsumerState<GovernmentDocumentsScreen> {
  late OfficialDocMode _currentMode;

  // ── ID Card State ──
  String? _idFrontPath;
  String? _idBackPath;
  bool _idActualSize = true; // default: true = 1:1 ISO scale (85.6mm x 53.98mm)

  // ── Passport State ──
  String? _passportImagePath;
  bool _passportLandscape = false;

  // ── Certificate State ──
  String? _certificateImagePath;
  bool _certificateLandscape = true;

  // ── Photo Grid State ──
  String? _photoImagePath;
  GovDocType _selectedPhotoType = GovDocType.personalPhoto35x45;

  // ── Compression State ──
  String? _compressImagePath;
  int _selectedTargetKb = 200;
  final TextEditingController _customKbController = TextEditingController();

  // ── Process Indicator ──
  bool _isProcessing = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
  }

  @override
  void dispose() {
    _customKbController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOURCE PICKERS & HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apple-style unified source picker bottom sheet: Camera, Gallery, Library.
  Future<String?> _pickImageWithSource(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),

                // Option 1: Camera Scanner
                _buildSourceOptionTile(
                  icon: Icons.camera_alt_rounded,
                  iconColor: const Color(0xFF007AFF),
                  title: 'مسح ضوئي ذكي بالكاميرا',
                  subtitle: 'التقاط فوري مع ضبط الحدود والزوايا تلقائياً',
                  onTap: () => Navigator.pop(ctx, 'camera'),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                // Option 2: Gallery
                _buildSourceOptionTile(
                  icon: Icons.photo_library_rounded,
                  iconColor: const Color(0xFFAF52DE),
                  title: 'اختيار من الصور أو الملفات',
                  subtitle: 'تحديد صورة بصيغة JPG أو PNG من هاتفك',
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                // Option 3: Document Library
                if (docs.isNotEmpty) ...[
                  _buildSourceOptionTile(
                    icon: Icons.folder_special_rounded,
                    iconColor: const Color(0xFF34C759),
                    title: 'اختيار من مكتبة التطبيق',
                    subtitle: 'استخدام صفحات ممسوحة مسبقاً (${docs.length} مستند)',
                    onTap: () => Navigator.pop(ctx, 'library'),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (source == null) return null;

    if (source == 'camera') {
      try {
        final draftsDir =
            await ref.read(localDocumentStoreProvider).getDraftsDirectory();
        final scanResults = await NativeScannerBridge.startScan(
          destDir: draftsDir.path,
          batch: false,
        );
        if (scanResults.isNotEmpty && context.mounted) {
          final res = scanResults.first;
          return await openScanReviewScreen(
            context,
            rawImagePath: res.path,
            initialCorners: res.corners,
            imageWidth: res.width,
            imageHeight: res.height,
          );
        }
      } on ScannerPermissionDeniedException catch (e) {
        if (context.mounted) {
          await showScannerPermissionDialog(context, e);
        }
        return null;
      } catch (e) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
        );
      }
      return null;
    } else if (source == 'gallery') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        if (!context.mounted) return null;
        return await openScanReviewScreen(
          context,
          rawImagePath: result.files.first.path!,
        );
      }
      return null;
    } else if (source == 'library') {
      if (!context.mounted) return null;
      return _pickPageFromLibrary(context, docs);
    }

    return null;
  }

  Widget _buildSourceOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: isDark ? Colors.white30 : Colors.black26,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickPageFromLibrary(
    BuildContext context,
    List<PendingUpload> docs,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مستنداً من مكتبتك:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
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
                    final firstPagePath = d.previewImagePath ?? '';
                    return ListTile(
                      leading: firstPagePath.isNotEmpty &&
                              PendingUpload.isImageFilePath(firstPagePath) &&
                              File(firstPagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(firstPagePath),
                                cacheWidth: 120,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.picture_as_pdf_rounded),
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      title: Text(
                        stripFileExtension(d.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(formatPageCount(d.effectivePageCount)),
                      onTap: () {
                        if (firstPagePath.isNotEmpty) {
                          Navigator.pop(ctx, firstPagePath);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rotates an image file 90 degrees clockwise in place with high JPEG quality.
  Future<String?> _rotateImage(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return imagePath;

      final rotated = img.copyRotate(decoded, angle: 90);
      final newBytes = img.encodeJpg(rotated, quality: 95);

      final dir = p.dirname(imagePath);
      final base = p.basenameWithoutExtension(imagePath);
      final newPath = p.join(
        dir,
        '${base}_rot_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(newPath).writeAsBytes(newBytes, flush: true);
      return newPath;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تدوير الصورة: $e')),
        );
      }
      return imagePath;
    }
  }

  /// Apple HIG Result Modal with Share, Instant Print, and Open.
  void _showResultModal({
    required String filePath,
    required String title,
    String? subtitle,
  }) {
    final file = File(filePath);
    final sizeStr = file.existsSync() ? formatFileSize(file.lengthSync()) : '';
    final isPdf = filePath.toLowerCase().endsWith('.pdf');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Success icon
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF34C759),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),

                if (sizeStr.isNotEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'الحجم النهائي: $sizeStr',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Primary: Open
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  label: const Text(
                    'فتح المستند للمعاينة',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    OpenFilex.open(filePath);
                  },
                ),
                const SizedBox(height: 10),

                // Secondary row: Share + Print
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.share_rounded, size: 19),
                        label: const Text('مشاركة',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Share.shareXFiles([XFile(filePath)]);
                        },
                      ),
                    ),
                    if (isPdf) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.print_rounded, size: 19),
                          label: const Text('طباعة فورية',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final bytes = await File(filePath).readAsBytes();
                            await Printing.layoutPdf(onLayout: (_) => bytes);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS / GENERATORS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _buildIdCardA4() async {
    if (_idFrontPath == null || _idBackPath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ دمج بطاقة الهوية في مستند A4 معياري...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildNationalIdA4(
        _idFrontPath!,
        _idBackPath!,
        isActualSize: _idActualSize,
      );
      if (!mounted) return;
      _showResultModal(
        filePath: pdfPath,
        title: 'تم دمج بطاقة الهوية بنجاح',
        subtitle:
            'ورقة A4 رسمية ومجهزة بخطوط القص ومطابقة للمواصفة القياسية العالمية ISO/IEC 7810 ID-1.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء دمج البطاقة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _buildPassportPage() async {
    if (_passportImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ تنسيق وثيقة السفر وفق معايير ICAO الدولية...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildPassportPage(
        _passportImagePath!,
        isLandscape: _passportLandscape,
      );
      if (!mounted) return;
      _showResultModal(
        filePath: pdfPath,
        title: 'تم تجهيز ورقة جواز السفر A4',
        subtitle:
            'نسخة رسمية واضحة ومجهزة للتقديم في السفارات واستخراج التأشيرات.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تجهيز صفحة الجواز: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _buildCertificatePage() async {
    if (_certificateImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ تأطير وتنسيق المستند الرسمي...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildCertificatePage(
        _certificateImagePath!,
        isLandscape: _certificateLandscape,
      );
      if (!mounted) return;
      _showResultModal(
        filePath: pdfPath,
        title: 'تم تنسيق الوثيقة الرسمية بنجاح',
        subtitle:
            'ملف A4 بإطار معتمد وأبعاد منسقة صالحة للجهات الرسمية والجامعات.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تنسيق المستند: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _buildPhotoGrid() async {
    if (_photoImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ ترتيب شبكة الصور الشخصية للطباعة...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildPersonalPhotoGrid(
        _photoImagePath!,
        _selectedPhotoType,
      );
      if (!mounted) return;
      _showResultModal(
        filePath: pdfPath,
        title: 'تم إنشاء ورقة الصور الشخصية A4',
        subtitle:
            'ورقة مجهزة بمقاسات دقيقة وعلامات القص وجاهزة للطباعة الورقية فوراً.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إعداد ورقة الصور: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _compressDocument() async {
    if (_compressImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ ضغط المستند ليكون أقل من $_selectedTargetKb KB...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final outPath = await service.compressToTargetSizeAndSave(
        _compressImagePath!,
        targetKb: _selectedTargetKb,
      );
      if (!mounted) return;
      final originalSize = File(_compressImagePath!).lengthSync();
      final newSize = File(outPath).lengthSync();

      _showResultModal(
        filePath: outPath,
        title: 'تم ضغط المستند بنجاح',
        subtitle:
            'الحجم قبل: ${formatFileSize(originalSize)} ← الحجم الجديد: ${formatFileSize(newSize)} (مطابق لسقف البوابة)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل ضغط المستند: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'استوديو الهوية والوثائق',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── Apple Top Segmented Bar ──
              _buildAppleSegmentedBar(isDark),

              // ── Active Studio Content ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildActiveStudio(isDark),
                ),
              ),
            ],
          ),

          // ── Processing Overlay ──
          if (_isProcessing)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
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
                    const CircularProgressIndicator(strokeWidth: 3),
                    const SizedBox(height: 18),
                    Text(
                      _statusText ?? 'جارٍ المعالجة...',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppleBottomNavBar(currentIndex: 2),
    );
  }

  // ── Top Apple Segmented Pill Bar ──
  Widget _buildAppleSegmentedBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: OfficialDocMode.values.map((mode) {
            final isSelected = _currentMode == mode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => setState(() => _currentMode = mode),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF007AFF)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        mode.icon,
                        size: 17,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActiveStudio(bool isDark) {
    switch (_currentMode) {
      case OfficialDocMode.idCard:
        return _buildIdCardStudio(isDark);
      case OfficialDocMode.passport:
        return _buildPassportStudio(isDark);
      case OfficialDocMode.certificate:
        return _buildCertificateStudio(isDark);
      case OfficialDocMode.photos:
        return _buildPhotoStudio(isDark);
      case OfficialDocMode.compress:
        return _buildCompressionStudio(isDark);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 1: ID & DRIVER LICENSE (2-IN-1)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIdCardStudio(bool isDark) {
    final canBuild = _idFrontPath != null && _idBackPath != null;

    return ListView(
      key: const ValueKey('id_card_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        // Subtitle badge
        _buildStudioHeader(
          title: 'بطاقة الهوية ورخصة القيادة (2 في 1)',
          description:
              'دمج الوجه الأمامي والخلفي في ورقة A4 واحدة بالأبعاد القياسية ISO/IEC 7810 ID-1 مع خطوط القص المعتمدة عالمياً.',
          badge: 'معياري دولي',
          icon: Icons.badge_rounded,
          accentColor: const Color(0xFF007AFF),
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        // Banner to launch advanced A4 studio
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IdCardA4Screen(
                  initialFrontPath: _idFrontPath,
                  initialBackPath: _idBackPath,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.3),
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
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF007AFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'استوديو A4 المتقدم للهوية (1:1)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      Text(
                        'تخطيطات متعددة (بجانب بعض/رأسي)، علامات أمنية ضد التزوير، ومعاينة حية',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF007AFF)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Dual Slots Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Front slot
              _buildSlotItem(
                label: 'الوجه الأمامي للبطاقة (Front)',
                imagePath: _idFrontPath,
                aspectRatio: 85.6 / 54, // ISO card ratio
                isDark: isDark,
                onPick: () async {
                  final p = await _pickImageWithSource(
                    context,
                    title: 'التقاط الوجه الأمامي للبطاقة',
                    subtitle: 'تأكد من إضاءة جيدة ووضوح أركان البطاقة الأربعة',
                  );
                  if (p != null) setState(() => _idFrontPath = p);
                },
                onRotate: () async {
                  if (_idFrontPath != null) {
                    final rot = await _rotateImage(_idFrontPath!);
                    if (rot != null) setState(() => _idFrontPath = rot);
                  }
                },
                onClear: () => setState(() => _idFrontPath = null),
              ),

              const SizedBox(height: 12),
              // Divider guide
              Row(
                children: [
                  Text(
                    '✂',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 1,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  Text(
                    'خط القص القياسي A4',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Back slot
              _buildSlotItem(
                label: 'الوجه الخلفي للبطاقة (Back)',
                imagePath: _idBackPath,
                aspectRatio: 85.6 / 54,
                isDark: isDark,
                onPick: () async {
                  final p = await _pickImageWithSource(
                    context,
                    title: 'التقاط الوجه الخلفي للبطاقة',
                    subtitle: 'تأكد من ظهور الباركود أو الشرائح الإلكترونية بوضوح',
                  );
                  if (p != null) setState(() => _idBackPath = p);
                },
                onRotate: () async {
                  if (_idBackPath != null) {
                    final rot = await _rotateImage(_idBackPath!);
                    if (rot != null) setState(() => _idBackPath = rot);
                  }
                },
                onClear: () => setState(() => _idBackPath = null),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Scale Toggle (Actual vs Enlarged)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.straighten_rounded,
                  color: Color(0xFF007AFF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _idActualSize
                          ? 'المقاس الفعلي القياسي (1:1)'
                          : 'مقاس مكبر عالي الوضوح (1.35x)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _idActualSize
                          ? '85.6 × 54 مم • مقاس فيزيائي مطابق للطباعة الورقية'
                          : 'أفضل للتقديم الإلكتروني، البنوك، وقراءة البيانات',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _idActualSize,
                onChanged: (val) => setState(() => _idActualSize = val),
                activeThumbColor: const Color(0xFF007AFF),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Primary Action Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFF007AFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          label: Text(
            canBuild
                ? 'دمج البطاقة وتصدير PDF (A4)'
                : 'التقط وجهي البطاقة للمتابعة',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: canBuild ? _buildIdCardA4 : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 2: PASSPORT STUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPassportStudio(bool isDark) {
    final hasImage =
        _passportImagePath != null && File(_passportImagePath!).existsSync();

    return ListView(
      key: const ValueKey('passport_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        _buildStudioHeader(
          title: 'جواز السفر الدولي (صفحة البيانات)',
          description:
              'تنسيق وثيقة السفر بدقة مع إطار رسمي مطابق لمتطلبات الطيران المدني الدولي ICAO Doc 9303 للتأشيرات والسفارات.',
          badge: 'ICAO معتمد',
          icon: Icons.menu_book_rounded,
          accentColor: const Color(0xFF5856D6),
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // Document slot card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSlotItem(
                label: 'صفحة بيانات جواز السفر',
                imagePath: _passportImagePath,
                aspectRatio: 1.42,
                isDark: isDark,
                onPick: () async {
                  final p = await _pickImageWithSource(
                    context,
                    title: 'التقاط صفحة جواز السفر',
                    subtitle: 'تأكد من شمول شريط القراءة الآلية (MRZ) أسفل الصفحة',
                  );
                  if (p != null) setState(() => _passportImagePath = p);
                },
                onRotate: () async {
                  if (_passportImagePath != null) {
                    final rot = await _rotateImage(_passportImagePath!);
                    if (rot != null) setState(() => _passportImagePath = rot);
                  }
                },
                onClear: () => setState(() => _passportImagePath = null),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Orientation Selector
        _buildOrientationSelector(
          isLandscape: _passportLandscape,
          onChanged: (val) => setState(() => _passportLandscape = val),
          isDark: isDark,
        ),

        const SizedBox(height: 22),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFF5856D6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          label: Text(
            hasImage
                ? 'تصدير ورقة جواز السفر A4'
                : 'التقط أو اختر صورة الجواز',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: hasImage ? _buildPassportPage : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 3: CERTIFICATES & OFFICIAL DOCUMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCertificateStudio(bool isDark) {
    final hasImage = _certificateImagePath != null &&
        File(_certificateImagePath!).existsSync();

    return ListView(
      key: const ValueKey('certificate_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        _buildStudioHeader(
          title: 'الشهادات والمستندات والعقود الرسمية',
          description:
              'تنسيق الشهادات الأكاديمية والمهنية وتأطيرها بدقة عالية في صفحة A4 مجهزة للأرشفة والجهات الحكومية والشركات.',
          badge: 'A4 رسمي',
          icon: Icons.workspace_premium_rounded,
          accentColor: const Color(0xFFFF9500),
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _buildSlotItem(
            label: 'الشهادة أو الوثيقة الرسمية',
            imagePath: _certificateImagePath,
            aspectRatio: _certificateLandscape ? 1.41 : (1 / 1.41),
            isDark: isDark,
            onPick: () async {
              final p = await _pickImageWithSource(
                context,
                title: 'اختيار الشهادة أو الوثيقة',
                subtitle: 'شهادات التخرج، العقود، أو خطابات التوثيق الرسمية',
              );
              if (p != null) setState(() => _certificateImagePath = p);
            },
            onRotate: () async {
              if (_certificateImagePath != null) {
                final rot = await _rotateImage(_certificateImagePath!);
                if (rot != null) setState(() => _certificateImagePath = rot);
              }
            },
            onClear: () => setState(() => _certificateImagePath = null),
          ),
        ),

        const SizedBox(height: 16),

        _buildOrientationSelector(
          isLandscape: _certificateLandscape,
          onChanged: (val) => setState(() => _certificateLandscape = val),
          isDark: isDark,
        ),

        const SizedBox(height: 22),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFFFF9500),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          label: Text(
            hasImage
                ? 'تصدير المستند الرسمي A4'
                : 'التقط أو اختر صورة الوثيقة',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: hasImage ? _buildCertificatePage : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 4: UNIVERSAL PHOTO & VISA STUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoStudio(bool isDark) {
    final hasImage =
        _photoImagePath != null && File(_photoImagePath!).existsSync();

    return ListView(
      key: const ValueKey('photo_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        _buildStudioHeader(
          title: 'استوديو صور التأشيرة وجواز السفر',
          description:
              'تجهيز شبكة صور شخصية متعددة على ورقة A4 واحدة جاهزة للطباعة فوراً بمقاسات شنغن، أمريكا 2×2، والمقاسات العالمية.',
          badge: 'سفر وتأشيرات',
          icon: Icons.photo_camera_front_rounded,
          accentColor: const Color(0xFF34C759),
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // Photo slot card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _buildSlotItem(
            label: 'صورتك الشخصية (خلفية بيضاء)',
            imagePath: _photoImagePath,
            aspectRatio: 1.0, // Square preview
            isDark: isDark,
            onPick: () async {
              final p = await _pickImageWithSource(
                context,
                title: 'التقاط أو اختيار الصورة الشخصية',
                subtitle: 'يفضل خلفية محايدة (بيضاء أو رمادية فاتحة)',
              );
              if (p != null) setState(() => _photoImagePath = p);
            },
            onRotate: () async {
              if (_photoImagePath != null) {
                final rot = await _rotateImage(_photoImagePath!);
                if (rot != null) setState(() => _photoImagePath = rot);
              }
            },
            onClear: () => setState(() => _photoImagePath = null),
          ),
        ),

        const SizedBox(height: 16),

        // Size format selection pills
        Text(
          'اختر المعيار والمقاس المطلوب:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),

        Column(
          children: [
            _buildPhotoFormatOption(
              type: GovDocType.personalPhoto35x45,
              title: '35 × 45 مم (8 صور)',
              subtitle: 'تأشيرات شنغن الأوروبية، بريطانيا، كندا، وأستراليا',
              isSelected: _selectedPhotoType == GovDocType.personalPhoto35x45,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _buildPhotoFormatOption(
              type: GovDocType.personalPhoto2x2,
              title: '2 × 2 بوصة / 5 × 5 سم (6 صور)',
              subtitle: 'تأشيرات الولايات المتحدة الأمريكية (US Visa) والجرين كارد والهند',
              isSelected: _selectedPhotoType == GovDocType.personalPhoto2x2,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _buildPhotoFormatOption(
              type: GovDocType.personalPhoto4x6,
              title: '4 × 6 سم (4 صور)',
              subtitle: 'جوازات السفر العربية، آسيا، وأغلب استمارات التقديم',
              isSelected: _selectedPhotoType == GovDocType.personalPhoto4x6,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _buildPhotoFormatOption(
              type: GovDocType.personalPhoto3x4,
              title: '3 × 4 سم (8 صور)',
              subtitle: 'بطاقات الهوية الوطنية، رخص القيادة، والكارنيهات',
              isSelected: _selectedPhotoType == GovDocType.personalPhoto3x4,
              isDark: isDark,
            ),
          ],
        ),

        const SizedBox(height: 22),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFF34C759),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.print_rounded, size: 20),
          label: Text(
            hasImage ? 'إنشاء ورقة الصور للطباعة (A4)' : 'اختر الصورة الشخصية',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: hasImage ? _buildPhotoGrid : null,
        ),
      ],
    );
  }

  Widget _buildPhotoFormatOption({
    required GovDocType type,
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedPhotoType = type),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF34C759).withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF34C759)
                : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected
                  ? const Color(0xFF34C759)
                  : (isDark ? Colors.white30 : Colors.black26),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w700,
                      fontSize: 13.5,
                      color: isSelected
                          ? const Color(0xFF34C759)
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 5: PRECISION COMPRESSION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompressionStudio(bool isDark) {
    final hasImage =
        _compressImagePath != null && File(_compressImagePath!).existsSync();
    final originalSize =
        hasImage ? File(_compressImagePath!).lengthSync() : 0;

    return ListView(
      key: const ValueKey('compression_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        _buildStudioHeader(
          title: 'ضغط المستندات للبوابات والسفارات',
          description:
              'تقليص حجم المستندات بدقة هندسية لضمان عدم تجاوز السقف الحجمي المحدد لبوابات التوظيف ومواقع التقديم الإلكتروني.',
          badge: 'ضمان القبول',
          icon: Icons.speed_rounded,
          accentColor: const Color(0xFFFF2D55),
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // File Selector Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(_compressImagePath!),
                        cacheWidth: 180,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.basename(_compressImagePath!),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الحجم الحالي: ${formatFileSize(originalSize)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: originalSize > _selectedTargetKb * 1024
                                  ? const Color(0xFFFF2D55)
                                  : const Color(0xFF34C759),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.change_circle_rounded, size: 22),
                      tooltip: 'تغيير المستند',
                      onPressed: () async {
                        final pth = await _pickImageWithSource(
                          context,
                          title: 'اختيار مستند جديد للضغط',
                        );
                        if (pth != null) {
                          setState(() => _compressImagePath = pth);
                        }
                      },
                    ),
                  ],
                ),
              ] else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 24),
                  label: const Text(
                    'اختر المستند المراد ضغطه (كاميرا / معرض / مكتبة)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    final pth = await _pickImageWithSource(
                      context,
                      title: 'اختيار المستند المراد ضغطه',
                    );
                    if (pth != null) {
                      setState(() => _compressImagePath = pth);
                    }
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'اختر الحد الأقصى المطلوب للموقع:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),

        // Universal Preset Selector
        Column(
          children: GovernmentPresetService.portalPresets.map((preset) {
            final isSelected = _selectedTargetKb == preset.kb;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedTargetKb = preset.kb),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF2D55).withValues(alpha: 0.1)
                        : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF2D55)
                          : (isDark
                              ? Colors.white12
                              : Colors.black.withValues(alpha: 0.08)),
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? const Color(0xFFFF2D55)
                            : (isDark ? Colors.white12 : Colors.black12),
                        foregroundColor: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black54),
                        child: Icon(preset.icon, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          preset.label,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 13,
                            color: isSelected
                                ? const Color(0xFFFF2D55)
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                      Text(
                        '< ${preset.kb} KB',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: isSelected
                              ? const Color(0xFFFF2D55)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 22),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFFFF2D55),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.compress_rounded, size: 20),
          label: Text(
            hasImage
                ? 'ضغط المستند لأقل من $_selectedTargetKb KB'
                : 'اختر المستند لبدء الضغط',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: hasImage ? _compressDocument : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE APPLE COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudioHeader({
    required String title,
    required String description,
    required String badge,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.25 : 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotItem({
    required String label,
    required String? imagePath,
    required double aspectRatio,
    required bool isDark,
    required VoidCallback onPick,
    required VoidCallback onRotate,
    required VoidCallback onClear,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return AspectRatio(
      aspectRatio: aspectRatio.clamp(0.9, 1.8),
      child: Container(
        decoration: BoxDecoration(
          color: hasImage
              ? Colors.transparent
              : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage
                ? const Color(0xFF007AFF)
                : (isDark ? Colors.white24 : Colors.black26),
            width: hasImage ? 1.5 : 1,
            style: hasImage ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Center(
                      child: Image.file(
                        File(imagePath),
                        cacheWidth: 600,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_rounded, size: 36),
                        ),
                      ),
                    ),
                  ),
                  // Top badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // Floating action pills
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGlassMiniButton(
                          icon: Icons.rotate_right_rounded,
                          tooltip: 'تدوير 90°',
                          onTap: onRotate,
                        ),
                        const SizedBox(width: 6),
                        _buildGlassMiniButton(
                          icon: Icons.refresh_rounded,
                          tooltip: 'تغيير الصورة',
                          onTap: onPick,
                        ),
                        const SizedBox(width: 6),
                        _buildGlassMiniButton(
                          icon: Icons.close_rounded,
                          tooltip: 'حذف',
                          color: Colors.redAccent,
                          onTap: onClear,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_a_photo_rounded,
                          size: 26,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اضغط للمسح بالكاميرا أو الاختيار',
                        style: TextStyle(
                          fontSize: 11,
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

  Widget _buildGlassMiniButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 17,
          color: color ?? Colors.white,
        ),
      ),
    );
  }

  Widget _buildOrientationSelector({
    required bool isLandscape,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLandscape ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded,
            color: const Color(0xFF007AFF),
            size: 22,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اتجاه صفحة A4',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                Text(
                  'تحديد الوضع الأفقي أو الرأسي للمستند',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('طولي', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: true,
                label: Text('عرضي', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {isLandscape},
            onSelectionChanged: (set) => onChanged(set.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
