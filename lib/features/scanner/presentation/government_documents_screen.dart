import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/motion_tokens.dart';
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

  // ── ID Card Margins & Header State ──
  bool _idIncludeHeader = false;
  final TextEditingController _idHeaderController = TextEditingController();
  bool _idIncludeFooter = false;
  final TextEditingController _idFooterController = TextEditingController();
  bool _idIncludeDate = false;
  bool _idIncludeCutGuideline = true;

  // ── Passport Margins & Header State ──
  bool _passportIncludeHeader = false;
  final TextEditingController _passportHeaderController = TextEditingController();
  bool _passportIncludeFooter = false;
  final TextEditingController _passportFooterController = TextEditingController();
  bool _passportIncludeDate = false;
  bool _passportIncludeBorder = true;

  // ── Certificate Margins & Header State ──
  bool _certIncludeHeader = false;
  final TextEditingController _certHeaderController = TextEditingController();
  bool _certIncludeFooter = false;
  final TextEditingController _certFooterController = TextEditingController();
  bool _certIncludeDate = false;
  bool _certIncludeBorder = true;

  // ── Photo Grid Margins & Header State ──
  bool _photoIncludeHeader = false;
  final TextEditingController _photoHeaderController = TextEditingController();
  bool _photoIncludeFooter = false;
  final TextEditingController _photoFooterController = TextEditingController();
  bool _photoIncludeDate = false;
  bool _photoIncludeCutGuidelines = true;

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
    _idHeaderController.dispose();
    _idFooterController.dispose();
    _passportHeaderController.dispose();
    _passportFooterController.dispose();
    _certHeaderController.dispose();
    _certFooterController.dispose();
    _photoHeaderController.dispose();
    _photoFooterController.dispose();
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
    String? directSource,
  }) async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = directSource ??
        await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
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
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
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
                      fontWeight: FontWeight.w800,
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
              color: isDark ? Colors.white38 : Colors.black38,
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
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
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

  /// Rotates an image file 90 degrees clockwise in place with high JPEG quality in background isolate.
  Future<String?> _rotateImage(String imagePath) async {
    try {
      final newPath = await compute((String pth) async {
        final file = File(pth);
        if (!file.existsSync()) return null;
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;

        final rotated = img.copyRotate(decoded, angle: 90);
        final newBytes = img.encodeJpg(rotated, quality: 92);

        final dir = p.dirname(pth);
        final base = p.basenameWithoutExtension(pth);
        final targetPath = p.join(
          dir,
          '${base}_rot_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await File(targetPath).writeAsBytes(newBytes, flush: true);
        return targetPath;
      }, imagePath);

      return newPath ?? imagePath;
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
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
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

                // Primary: Open Preview
                Material(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                      OpenFilex.open(filePath);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'فتح المستند للمعاينة',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Secondary row: Share + Print (Balanced 50% / 50%)
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(ctx);
                            Share.shareXFiles([XFile(filePath)]);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.black.withValues(alpha: 0.06),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.share_rounded,
                                  size: 18,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'مشاركة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isPdf) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              Navigator.pop(ctx);
                              final bytes = await File(filePath).readAsBytes();
                              await Printing.layoutPdf(onLayout: (_) => bytes);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black.withValues(alpha: 0.06),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.print_rounded,
                                    size: 18,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'طباعة فورية',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
        includeHeader: _idIncludeHeader,
        headerTitle: _idHeaderController.text.trim().isNotEmpty
            ? _idHeaderController.text.trim()
            : null,
        includeFooter: _idIncludeFooter,
        footerText: _idFooterController.text.trim().isNotEmpty
            ? _idFooterController.text.trim()
            : null,
        includeDate: _idIncludeDate,
        includeCutGuideline: _idIncludeCutGuideline,
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
        includeHeader: _passportIncludeHeader,
        headerTitle: _passportHeaderController.text.trim().isNotEmpty
            ? _passportHeaderController.text.trim()
            : null,
        includeFooter: _passportIncludeFooter,
        footerText: _passportFooterController.text.trim().isNotEmpty
            ? _passportFooterController.text.trim()
            : null,
        includeDate: _passportIncludeDate,
        includeBorder: _passportIncludeBorder,
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
        includeHeader: _certIncludeHeader,
        headerTitle: _certHeaderController.text.trim().isNotEmpty
            ? _certHeaderController.text.trim()
            : null,
        includeFooter: _certIncludeFooter,
        footerText: _certFooterController.text.trim().isNotEmpty
            ? _certFooterController.text.trim()
            : null,
        includeDate: _certIncludeDate,
        includeBorder: _certIncludeBorder,
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
        includeHeader: _photoIncludeHeader,
        headerTitle: _photoHeaderController.text.trim().isNotEmpty
            ? _photoHeaderController.text.trim()
            : null,
        includeFooter: _photoIncludeFooter,
        footerText: _photoFooterController.text.trim().isNotEmpty
            ? _photoFooterController.text.trim()
            : null,
        includeDate: _photoIncludeDate,
        includeCutGuidelines: _photoIncludeCutGuidelines,
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
        backgroundColor: isDark ? const Color(0xFF121214) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'استوديو الهوية والوثائق',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'المعايير الرسمية المعتمدة للطباعة والجهات الحكومية',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
              ),
            ),
          ],
        ),
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
        color: isDark ? const Color(0xFF121214) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: OfficialDocMode.values.map((mode) {
            final isSelected = _currentMode == mode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _currentMode = mode);
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF007AFF)
                        : (isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF2F2F7)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                      width: isSelected ? 1.2 : 0.8,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withValues(alpha: 0.28),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mode.icon,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
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
  // REUSABLE MARGINS & HEADERS SETTINGS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMarginAndHeaderSettings({
    required bool isDark,
    required Color accentColor,
    required bool includeHeader,
    required ValueChanged<bool> onHeaderChanged,
    required TextEditingController headerController,
    required String headerPlaceholder,
    required bool includeFooter,
    required ValueChanged<bool> onFooterChanged,
    required TextEditingController footerController,
    required String footerPlaceholder,
    required bool includeDate,
    required ValueChanged<bool> onDateChanged,
    bool? includeBorder,
    ValueChanged<bool>? onBorderChanged,
    String borderTitle = 'إطار أو خطوط القص',
    String borderSubtitle = 'تحديد حدود الوثيقة وإرشادات القص الورقي',
  }) {
    final hasActiveMargins = includeHeader || includeFooter || includeDate;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: accentColor,
              size: 20,
            ),
          ),
          title: const Text(
            'تخصيص الهوامش والترويسة (اختياري)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          subtitle: Text(
            hasActiveMargins
                ? 'تم تفعيل عناصر مخصصة بالهامش'
                : 'الورقة نقية وخالية تماماً من أي نصوص أو تواريخ إضافية',
            style: TextStyle(
              fontSize: 11,
              fontWeight: hasActiveMargins ? FontWeight.w700 : FontWeight.normal,
              color: hasActiveMargins
                  ? accentColor
                  : (isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 1. Header Toggle & Custom Text
            _buildMarginSwitchTile(
              title: 'إضافة ترويسة علوية (Header)',
              subtitle: 'نص رسمي أو عنوان أعلى الصفحة',
              value: includeHeader,
              onChanged: onHeaderChanged,
              accentColor: accentColor,
              isDark: isDark,
            ),
            if (includeHeader) ...[
              const SizedBox(height: 8),
              TextField(
                controller: headerController,
                decoration: InputDecoration(
                  hintText: headerPlaceholder,
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(Icons.title_rounded, size: 18, color: accentColor),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
            ],

            // 2. Footer Toggle & Custom Text
            _buildMarginSwitchTile(
              title: 'إضافة تذييل سفلي (Footer)',
              subtitle: 'ملاحظات أو نص اعتماد أسفل الصفحة',
              value: includeFooter,
              onChanged: onFooterChanged,
              accentColor: accentColor,
              isDark: isDark,
            ),
            if (includeFooter) ...[
              const SizedBox(height: 8),
              TextField(
                controller: footerController,
                decoration: InputDecoration(
                  hintText: footerPlaceholder,
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(Icons.notes_rounded, size: 18, color: accentColor),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
            ],

            // 3. Date Toggle
            _buildMarginSwitchTile(
              title: 'إضافة تاريخ اليوم (Date Stamp)',
              subtitle: 'طباعة التاريخ الحالي (${DateFormat('yyyy/MM/dd').format(DateTime.now())})',
              value: includeDate,
              onChanged: onDateChanged,
              accentColor: accentColor,
              isDark: isDark,
            ),

            // 4. Border / Guidelines Toggle (if provided)
            if (includeBorder != null && onBorderChanged != null) ...[
              _buildMarginSwitchTile(
                title: borderTitle,
                subtitle: borderSubtitle,
                value: includeBorder,
                onChanged: onBorderChanged,
                accentColor: accentColor,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMarginSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accentColor,
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              onChanged(val);
            },
            activeThumbColor: accentColor,
          ),
        ],
      ),
    );
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

        const SizedBox(height: 14),

        // Margins, Header, Footer, and Date customization
        _buildMarginAndHeaderSettings(
          isDark: isDark,
          accentColor: const Color(0xFF007AFF),
          includeHeader: _idIncludeHeader,
          onHeaderChanged: (val) => setState(() => _idIncludeHeader = val),
          headerController: _idHeaderController,
          headerPlaceholder: 'مثال: وثيقة إثبات الهوية الرسمية',
          includeFooter: _idIncludeFooter,
          onFooterChanged: (val) => setState(() => _idIncludeFooter = val),
          footerController: _idFooterController,
          footerPlaceholder: 'مثال: نسخة رسمية معتمدة • مسح ضوئي عالي الدقة',
          includeDate: _idIncludeDate,
          onDateChanged: (val) => setState(() => _idIncludeDate = val),
          includeBorder: _idIncludeCutGuideline,
          onBorderChanged: (val) => setState(() => _idIncludeCutGuideline = val),
          borderTitle: 'خط القص القياسي (✂)',
          borderSubtitle: 'إظهار خط القص الفاصل بين وجهي البطاقة في منتصف الورقة',
        ),

        const SizedBox(height: 20),

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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_rounded, size: 16, color: Color(0xFF5856D6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'دليل ICAO: تأكد من ظهور سطري الرموز <<<<<<<< MRZ بالأسفل',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
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

        const SizedBox(height: 14),

        // Margins, Header, Footer, and Date customization
        _buildMarginAndHeaderSettings(
          isDark: isDark,
          accentColor: const Color(0xFF5856D6),
          includeHeader: _passportIncludeHeader,
          onHeaderChanged: (val) => setState(() => _passportIncludeHeader = val),
          headerController: _passportHeaderController,
          headerPlaceholder: 'مثال: وثيقة سفر رسمية - صورة الجواز',
          includeFooter: _passportIncludeFooter,
          onFooterChanged: (val) => setState(() => _passportIncludeFooter = val),
          footerController: _passportFooterController,
          footerPlaceholder: 'مثال: نسخة معتمدة مطابقة لأصل وثيقة السفر لغايات التأشيرات',
          includeDate: _passportIncludeDate,
          onDateChanged: (val) => setState(() => _passportIncludeDate = val),
          includeBorder: _passportIncludeBorder,
          onBorderChanged: (val) => setState(() => _passportIncludeBorder = val),
          borderTitle: 'إطار وثيقة السفر المعتمد',
          borderSubtitle: 'إطار رمادي رفيع يحيط بصفحة بيانات الجواز (ICAO)',
        ),

        const SizedBox(height: 20),

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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        // 1. Hero Bento Header
        _buildStudioHeader(
          title: 'الشهادات والمستندات والعقود الرسمية',
          description:
              'تنسيق الشهادات الأكاديمية والمهنية وتأطيرها بدقة عالية في صفحة A4 مجهزة للأرشفة والجهات الحكومية والشركات.',
          badge: hasImage ? 'جاهز للتصدير ✓' : 'A4 رسمي معتمد',
          icon: Icons.workspace_premium_rounded,
          accentColor: const Color(0xFFFF9500),
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        // 2. Bento Certificate Stage (Interactive Canvas with Live Frame Preview)
        _buildCertificateBentoStage(isDark, hasImage),
        const SizedBox(height: 14),

        // 3. A4 Page Orientation Bento Selector
        _buildCertificateOrientationSelector(isDark),
        const SizedBox(height: 14),

        // 4. Official Border & Framing Bento Selector
        _buildCertificateFramingSelector(isDark),
        const SizedBox(height: 14),

        // 5. Official Margins & Certification (Apple Inset)
        _buildCertificateCertificationSettings(isDark),
        const SizedBox(height: 14),

        // 6. Live A4 Paper Sheet Preview
        _buildCertificateLiveSheetPreview(isDark, hasImage),
        const SizedBox(height: 18),

        // 7. Action CTA Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: const Color(0xFFFF9500),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            shadowColor: const Color(0xFFFF9500).withValues(alpha: 0.3),
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
          label: Text(
            hasImage
                ? 'تصدير المستند الرسمي A4 (PDF)'
                : 'التقط أو اختر صورة الوثيقة أولاً',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          onPressed: hasImage ? _buildCertificatePage : null,
        ),
      ],
    );
  }

  // ── Bento Certificate Stage ──
  Widget _buildCertificateBentoStage(bool isDark, bool hasImage) {
    final double sheetRatio = _certificateLandscape ? 1.414 : 0.707;

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
                  color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.card_membership_rounded,
                  color: Color(0xFFFF9500),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مسرح الشهادة والمستند',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      _certificateLandscape
                          ? 'تنسيق عرضي (Landscape) • مقياس A4'
                          : 'تنسيق طولي (Portrait) • مقياس A4',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasImage)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF34C759)),
                      SizedBox(width: 4),
                      Text(
                        'مدرج ✓',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Certificate Canvas
          AspectRatio(
            aspectRatio: sheetRatio,
            child: Container(
              decoration: BoxDecoration(
                color: hasImage
                    ? Colors.transparent
                    : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasImage
                      ? const Color(0xFFFF9500).withValues(alpha: 0.5)
                      : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                  width: hasImage ? 1.4 : 1.0,
                ),
              ),
              child: hasImage
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Center(
                            child: Image.file(
                              File(_certificateImagePath!),
                              cacheWidth: 800,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                        ),
                        // Live Gold Border Preview Overlay
                        if (_certIncludeBorder)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37),
                                    width: 2.2,
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Top label badge
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _certificateLandscape ? 'شهادة عرضية A4' : 'وثيقة طولية A4',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        // Bottom floating action toolbar
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildGlassMiniButton(
                                icon: Icons.rotate_right_rounded,
                                tooltip: 'تدوير 90°',
                                onTap: () async {
                                  if (_certificateImagePath != null) {
                                    final rot = await _rotateImage(_certificateImagePath!);
                                    if (rot != null) setState(() => _certificateImagePath = rot);
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              _buildGlassMiniButton(
                                icon: Icons.refresh_rounded,
                                tooltip: 'تغيير الصورة',
                                onTap: () async {
                                  final p = await _pickImageWithSource(
                                    context,
                                    title: 'اختيار الشهادة أو الوثيقة',
                                    subtitle: 'شهادات التخرج، العقود، أو خطابات التوثيق الرسمية',
                                  );
                                  if (p != null) setState(() => _certificateImagePath = p);
                                },
                              ),
                              const SizedBox(width: 6),
                              _buildGlassMiniButton(
                                icon: Icons.close_rounded,
                                tooltip: 'حذف',
                                color: const Color(0xFFFF3B30),
                                onTap: () => setState(() => _certificateImagePath = null),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: () async {
                        final p = await _pickImageWithSource(
                          context,
                          title: 'اختيار الشهادة أو الوثيقة',
                          subtitle: 'شهادات التخرج، العقود، أو خطابات التوثيق الرسمية',
                        );
                        if (p != null) setState(() => _certificateImagePath = p);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_a_photo_rounded,
                                    size: 22,
                                    color: Color(0xFFFF9500),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'التقاط أو اختيار الشهادة أو الوثيقة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'شهادات التخرج، التقدير، العقود، أو خطابات التوثيق',
                                  style: TextStyle(
                                    fontSize: 10,
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
        ],
      ),
    );
  }

  // ── A4 Orientation Bento Selector ──
  Widget _buildCertificateOrientationSelector(bool isDark) {
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
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.aspect_ratio_rounded,
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
                      'اتجاه صفحة A4 للشهادة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'اختر الوضع المناسب لتصميم شهادتك',
                      style: TextStyle(
                        fontSize: 10.5,
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
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _certificateLandscape = true);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _certificateLandscape
                          ? const Color(0xFFFF9500).withValues(alpha: isDark ? 0.2 : 0.08)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _certificateLandscape
                            ? const Color(0xFFFF9500)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: _certificateLandscape ? 1.4 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2.5),
                            border: Border.all(
                              color: _certificateLandscape ? const Color(0xFFFF9500) : Colors.black26,
                              width: 0.8,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 16,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFD4AF37),
                                  width: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'عرضي (أفقي)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _certificateLandscape ? FontWeight.w700 : FontWeight.w500,
                            color: _certificateLandscape
                                ? const Color(0xFFFF9500)
                                : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                          ),
                        ),
                        Text(
                          'شهادات التخرج والدورات',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _certificateLandscape = false);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: !_certificateLandscape
                          ? const Color(0xFFFF9500).withValues(alpha: isDark ? 0.2 : 0.08)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !_certificateLandscape
                            ? const Color(0xFFFF9500)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: !_certificateLandscape ? 1.4 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 24,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2.5),
                            border: Border.all(
                              color: !_certificateLandscape ? const Color(0xFFFF9500) : Colors.black26,
                              width: 0.8,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 16,
                              height: 28,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFD4AF37),
                                  width: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'طولي (رأسي)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: !_certificateLandscape ? FontWeight.w700 : FontWeight.w500,
                            color: !_certificateLandscape
                                ? const Color(0xFFFF9500)
                                : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                          ),
                        ),
                        Text(
                          'العقود والخطابات الرسمية',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
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
    );
  }

  // ── Official Border & Framing Bento Selector ──
  Widget _buildCertificateFramingSelector(bool isDark) {
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
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.filter_frames_rounded,
                  color: Color(0xFFD4AF37),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'خيارات تأطير الشهادة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'إضافة الإطار الذهبي الفاخر حول الشهادة في ورقة A4',
                      style: TextStyle(
                        fontSize: 10.5,
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
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _certIncludeBorder = true);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _certIncludeBorder
                          ? const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.2 : 0.1)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _certIncludeBorder
                            ? const Color(0xFFD4AF37)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: _certIncludeBorder ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _certIncludeBorder ? const Color(0xFFD4AF37) : Colors.transparent,
                                border: Border.all(
                                  color: _certIncludeBorder ? const Color(0xFFD4AF37) : Colors.grey,
                                  width: 1.5,
                                ),
                              ),
                              child: _certIncludeBorder
                                  ? const Icon(Icons.check, size: 9, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'الإطار الذهبي المزدوج',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إطار فاخر للشهادات الأكاديمية والمهنية',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _certIncludeBorder = false);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: !_certIncludeBorder
                          ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.2 : 0.08)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !_certIncludeBorder
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: !_certIncludeBorder ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: !_certIncludeBorder ? const Color(0xFF007AFF) : Colors.transparent,
                                border: Border.all(
                                  color: !_certIncludeBorder ? const Color(0xFF007AFF) : Colors.grey,
                                  width: 1.5,
                                ),
                              ),
                              child: !_certIncludeBorder
                                  ? const Icon(Icons.check, size: 9, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'بدون إطار إضافي',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'للمستندات ذات الإطار المطبوع مسبقاً',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF8E8E93),
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
    );
  }

  // ── Official Margins & Certification (Apple Inset) ──
  Widget _buildCertificateCertificationSettings(bool isDark) {
    return _buildMarginAndHeaderSettings(
      isDark: isDark,
      accentColor: const Color(0xFFFF9500),
      includeHeader: _certIncludeHeader,
      onHeaderChanged: (val) => setState(() => _certIncludeHeader = val),
      headerController: _certHeaderController,
      headerPlaceholder: 'مثال: وثيقة ومستند رسمي معتمد',
      includeFooter: _certIncludeFooter,
      onFooterChanged: (val) => setState(() => _certIncludeFooter = val),
      footerController: _certFooterController,
      footerPlaceholder: 'مثال: وثيقة رسمية معتمدة - صالحة للجهات الحكومية والجامعات',
      includeDate: _certIncludeDate,
      onDateChanged: (val) => setState(() => _certIncludeDate = val),
    );
  }

  // ── Live A4 Paper Sheet Preview ──
  Widget _buildCertificateLiveSheetPreview(bool isDark, bool hasImage) {
    final isLandscape = _certificateLandscape;
    final double sheetWidth = isLandscape ? 220 : 160;
    final double sheetHeight = isLandscape ? 160 : 226;

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
                  Icons.visibility_outlined,
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
                      'معاينة ورقة A4 قبل الطباعة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'شكل المستند والإطار والهوامش الحقيقية للورقة',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasImage)
                InkWell(
                  onTap: _buildCertificatePage,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fullscreen_rounded, size: 14, color: Color(0xFF007AFF)),
                        const SizedBox(width: 3),
                        Text(
                          'معاينة كاملة',
                          style: TextStyle(
                            fontSize: 11,
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

          // Paper simulation
          Center(
            child: Container(
              width: sheetWidth,
              height: sheetHeight,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade300, width: 0.8),
              ),
              child: Column(
                children: [
                  // Optional Header
                  if (_certIncludeHeader) ...[
                    Container(
                      height: 10,
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.black26, width: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _certHeaderController.text.trim().isNotEmpty
                                  ? _certHeaderController.text.trim()
                                  : 'وثيقة ومستند رسمي معتمد',
                              style: const TextStyle(fontSize: 4, fontWeight: FontWeight.bold, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_certIncludeDate)
                            Text(
                              DateFormat('yyyy/MM/dd').format(DateTime.now()),
                              style: const TextStyle(fontSize: 3.5, color: Colors.black54),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],

                  // Certificate Center
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: _certIncludeBorder
                            ? Border.all(color: const Color(0xFFD4AF37), width: 1.5)
                            : null,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      padding: _certIncludeBorder ? const EdgeInsets.all(2) : EdgeInsets.zero,
                      child: Container(
                        decoration: BoxDecoration(
                          border: _certIncludeBorder
                              ? Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.5), width: 0.5)
                              : null,
                          color: const Color(0xFFF9F9FB),
                        ),
                        child: hasImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(1.5),
                                child: Image.file(
                                  File(_certificateImagePath!),
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              )
                            : Center(
                                child: Text(
                                  _certificateLandscape ? 'شهادة عرضية A4' : 'وثيقة طولية A4',
                                  style: const TextStyle(fontSize: 6, color: Colors.grey),
                                ),
                              ),
                      ),
                    ),
                  ),

                  // Optional Footer
                  if (_certIncludeFooter || (_certIncludeDate && !_certIncludeHeader)) ...[
                    const SizedBox(height: 3),
                    Container(
                      height: 8,
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.black26, width: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _certFooterController.text.trim().isNotEmpty
                                  ? _certFooterController.text.trim()
                                  : 'وثيقة رسمية معتمدة - صالحة للجهات الحكومية والجامعات',
                              style: const TextStyle(fontSize: 3.5, color: Colors.black54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
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

        // Visa format selection header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'اختر معيار ومقاس التأشيرة المطلوب:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'مقاسات معتمدة 100%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF34C759),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Apple 2x2 Grid of Visa Formats
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.22,
          children: [
            _buildVisaGridCard(
              type: GovDocType.personalPhoto35x45,
              flag: '🇪🇺',
              title: 'شنغن وأوروبا',
              dimensions: '35 × 45 مم',
              badge: '8 صور',
              isDark: isDark,
            ),
            _buildVisaGridCard(
              type: GovDocType.personalPhoto2x2,
              flag: '🇺🇸',
              title: 'أمريكا DS-160',
              dimensions: '2 × 2 بوصة (5×5)',
              badge: '6 صور',
              isDark: isDark,
            ),
            _buildVisaGridCard(
              type: GovDocType.personalPhoto4x6,
              flag: '🌍',
              title: 'جوازات عربية',
              dimensions: '4 × 6 سم',
              badge: '4 صور',
              isDark: isDark,
            ),
            _buildVisaGridCard(
              type: GovDocType.personalPhoto3x4,
              flag: '🪪',
              title: 'بطاقات وكارنيهات',
              dimensions: '3 × 4 سم',
              badge: '8 صور',
              isDark: isDark,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Margins, Header, Footer, and Date customization
        _buildMarginAndHeaderSettings(
          isDark: isDark,
          accentColor: const Color(0xFF34C759),
          includeHeader: _photoIncludeHeader,
          onHeaderChanged: (val) => setState(() => _photoIncludeHeader = val),
          headerController: _photoHeaderController,
          headerPlaceholder: 'مثال: استوديو صور التأشيرة وجواز السفر',
          includeFooter: _photoIncludeFooter,
          onFooterChanged: (val) => setState(() => _photoIncludeFooter = val),
          footerController: _photoFooterController,
          footerPlaceholder: 'مثال: جاهزة للطباعة الورقية بمقاسات دولية معتمدة',
          includeDate: _photoIncludeDate,
          onDateChanged: (val) => setState(() => _photoIncludeDate = val),
          includeBorder: _photoIncludeCutGuidelines,
          onBorderChanged: (val) => setState(() => _photoIncludeCutGuidelines = val),
          borderTitle: 'إطارات القص الرمادية الفاصلة',
          borderSubtitle: 'إطار دقيق حول كل صورة شخصية لتسهيل القص بالمقص',
        ),

        const SizedBox(height: 20),

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

  Widget _buildVisaGridCard({
    required GovDocType type,
    required String flag,
    required String title,
    required String dimensions,
    required String badge,
    required bool isDark,
  }) {
    final isSelected = _selectedPhotoType == type;

    return Material(
      color: isSelected
          ? const Color(0xFF34C759).withValues(alpha: 0.12)
          : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedPhotoType = type);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF34C759)
                  : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(flag, style: const TextStyle(fontSize: 20)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF34C759)
                          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: isSelected
                          ? const Color(0xFF34C759)
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dimensions,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO 5: PRECISION COMPRESSION (APPLE BENTO PAPER DESIGN)
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatTargetLabel(int kb) {
    if (kb >= 1024) {
      return '${kb ~/ 1024} ميجابايت';
    }
    return '$kb ك.ب';
  }

  Widget _buildSquircleSourceButton({
    required IconData icon,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFrostedMiniActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDestructive
            ? const Color(0xFFFF3B30).withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.65),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildCompressionStudio(bool isDark) {
    final hasImage =
        _compressImagePath != null && File(_compressImagePath!).existsSync();
    final originalSize =
        hasImage ? File(_compressImagePath!).lengthSync() : 0;
    final targetBytes = _selectedTargetKb * 1024;
    final bool willCompress = originalSize > targetBytes;
    final int savingsPct = willCompress
        ? (((originalSize - targetBytes) / (originalSize > 0 ? originalSize : 1)) * 100).clamp(0, 95).toInt()
        : 0;

    final presets = [
      (
        kb: 500,
        title: 'بوابات التوظيف والجهات الرسمية',
        desc: 'بوابة مصر الرقمية، مسابقات التعيين، والجامعات',
        badge: '< 500 ك.ب',
        icon: Icons.account_balance_rounded,
      ),
      (
        kb: 1024,
        title: 'السفارات والتأشيرات الدولية',
        desc: 'تأشيرات شنغن الأوروبية، بريطانيا، وأمريكا (ICAO)',
        badge: '< 1 م.ب',
        icon: Icons.flight_takeoff_rounded,
      ),
      (
        kb: 200,
        title: 'المواقع ذات السقف المنخفض جداً',
        desc: 'البوابات الحكومية القديمة والنماذج الإلكترونية الصارمة',
        badge: '< 200 ك.ب',
        icon: Icons.bolt_rounded,
      ),
      (
        kb: 2048,
        title: 'أقصى جودة ونقاء للأرشفة',
        desc: 'العقود التجارية الرسمية، المخططات، والشهادات الملونة',
        badge: '< 2 م.ب',
        icon: Icons.verified_rounded,
      ),
      (
        kb: 100,
        title: 'ضغط فائق للحالات الاستثنائية',
        desc: 'عند اشتراط موقع التقديم سقفاً دقيقاً لا يتعدى 100 ك.ب',
        badge: '< 100 ك.ب',
        icon: Icons.speed_rounded,
      ),
    ];

    return ListView(
      key: const ValueKey('compression_studio'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
      children: [
        _buildStudioHeader(
          title: 'ضغط وتقليص حجم المستندات',
          description:
              'تقليص حجم المستند بدقة هندسية ليطابق الحدود القصوى لبوابات التوظيف والجهات الرسمية مع حماية دقة النصوص والأختام.',
          badge: 'مطابق للشروط 100%',
          icon: Icons.speed_rounded,
          accentColor: const Color(0xFFFF2D55),
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // ── 1. Bento Paper Document Stage ──
        if (!hasImage)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.compress_rounded,
                    color: Color(0xFFFF2D55),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'اختر المستند المراد تقليص حجمه',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'التقط المستند بالكاميرا أو اختره من المعرض أو مكتبة التطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildSquircleSourceButton(
                        icon: Icons.camera_alt_rounded,
                        label: 'الكاميرا',
                        accentColor: const Color(0xFF007AFF),
                        onTap: () async {
                          final pth = await _pickImageWithSource(
                            context,
                            title: 'التقاط المستند بالكاميرا',
                            directSource: 'camera',
                          );
                          if (pth != null) setState(() => _compressImagePath = pth);
                        },
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSquircleSourceButton(
                        icon: Icons.photo_library_rounded,
                        label: 'المعرض',
                        accentColor: const Color(0xFFAF52DE),
                        onTap: () async {
                          final pth = await _pickImageWithSource(
                            context,
                            title: 'اختيار صورة المستند من المعرض',
                            directSource: 'gallery',
                          );
                          if (pth != null) setState(() => _compressImagePath = pth);
                        },
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSquircleSourceButton(
                        icon: Icons.folder_special_rounded,
                        label: 'المكتبة',
                        accentColor: const Color(0xFF34C759),
                        onTap: () async {
                          final pth = await _pickImageWithSource(
                            context,
                            title: 'اختيار مستند من مكتبة التطبيق',
                            directSource: 'library',
                          );
                          if (pth != null) setState(() => _compressImagePath = pth);
                        },
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          File(_compressImagePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            height: 140,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_rounded),
                          ),
                        ),
                      ),
                    ),
                    // Top Start badge: Original Size
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file_rounded, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'الحجم الأصلي: ${formatFileSize(originalSize)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Top End actions
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFrostedMiniActionButton(
                            icon: Icons.refresh_rounded,
                            tooltip: 'تغيير المستند',
                            onTap: () async {
                              final pth = await _pickImageWithSource(
                                context,
                                title: 'اختيار مستند جديد للضغط',
                              );
                              if (pth != null) {
                                setState(() => _compressImagePath = pth);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildFrostedMiniActionButton(
                            icon: Icons.close_rounded,
                            tooltip: 'حذف',
                            isDestructive: true,
                            onTap: () => setState(() => _compressImagePath = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        size: 14,
                        color: Color(0xFFFF2D55),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.basename(_compressImagePath!),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'جاهز للمعالجة',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // ── 2. Official Portal Limits (Apple Bento Group) ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'اختر السقف الحجمي المطلوب للبوابة:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF2D55).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'أقل من ${_formatTargetLabel(_selectedTargetKb)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF2D55),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Bento List of Presets
        Column(
          children: presets.map((p) {
            final isSel = _selectedTargetKb == p.kb;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSel
                    ? const Color(0xFFFF2D55).withValues(alpha: isDark ? 0.16 : 0.08)
                    : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTargetKb = p.kb);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel
                            ? const Color(0xFFFF2D55)
                            : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07)),
                        width: isSel ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFFFF2D55).withValues(alpha: 0.18)
                                : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            p.icon,
                            color: isSel
                                ? const Color(0xFFFF2D55)
                                : (isDark ? Colors.white70 : Colors.black54),
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.title,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.desc,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFFFF2D55)
                                : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p.badge,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isSel
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // ── 3. Real-Time Bento Reduction Gauge (if hasImage) ──
        if (hasImage) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 16, color: Color(0xFFFF2D55)),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'مؤشر التقليص والتوفير المتوقع',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: willCompress
                            ? const Color(0xFF34C759).withValues(alpha: 0.14)
                            : const Color(0xFF007AFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        willCompress
                            ? 'توفير متوقع ~$savingsPct%'
                            : 'مطابق للسقف بالفعل',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: willCompress
                              ? const Color(0xFF34C759)
                              : const Color(0xFF007AFF),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (targetBytes / (originalSize > 0 ? originalSize : 1))
                        .clamp(0.05, 1.0),
                    minHeight: 7,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF2D55)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الحجم الأصلي: ${formatFileSize(originalSize)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    Text(
                      'السقف المستهدف: أقل من ${_formatTargetLabel(_selectedTargetKb)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF2D55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF34C759)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'معالجة Smart DCT: تضمن بقاء نصوص الشهادات والأختام واضحة ومقروءة تماماً.',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 4. Apple Bento Primary Action Button ──
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: const Color(0xFFFF2D55),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.compress_rounded, size: 19),
          label: Text(
            hasImage
                ? 'بدء ضغط المستند (أقل من ${_formatTargetLabel(_selectedTargetKb)})'
                : 'اختر المستند لبدء الضغط',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 20),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366),
                    height: 1.35,
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
      aspectRatio: aspectRatio.clamp(0.65, 1.8),
      child: Container(
        decoration: BoxDecoration(
          color: hasImage
              ? Colors.transparent
              : (isDark
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFF9F9FB)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage
                ? const Color(0xFF007AFF)
                : (isDark ? Colors.white12 : const Color(0xFFE5E5EA)),
            width: hasImage ? 1.4 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
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
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
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
                          color: const Color(0xFFFF3B30),
                          onTap: onClear,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onPick();
                },
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_a_photo_rounded,
                              size: 18,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اضغط للمسح بالكاميرا أو الاختيار',
                            style: TextStyle(
                              fontSize: 10,
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
    );
  }

  Widget _buildGlassMiniButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 15,
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
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Icons.aspect_ratio_rounded,
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
                      'اتجاه صفحة A4',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'تحديد الوضع الأفقي أو الرأسي للورقة',
                      style: TextStyle(
                        fontSize: 10.5,
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
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(true);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isLandscape
                          ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.2 : 0.08)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLandscape
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: isLandscape ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.crop_landscape_rounded,
                          size: 18,
                          color: isLandscape
                              ? const Color(0xFF007AFF)
                              : (isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'عرضي (أفقي)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isLandscape ? FontWeight.w700 : FontWeight.w500,
                            color: isLandscape
                                ? const Color(0xFF007AFF)
                                : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(false);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: !isLandscape
                          ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.2 : 0.08)
                          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9F9FB)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isLandscape
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white10 : const Color(0xFFE5E5EA)),
                        width: !isLandscape ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.crop_portrait_rounded,
                          size: 18,
                          color: !isLandscape
                              ? const Color(0xFF007AFF)
                              : (isDark ? const Color(0xFFA1A1A6) : const Color(0xFF636366)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'طولي (رأسي)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: !isLandscape ? FontWeight.w700 : FontWeight.w500,
                            color: !isLandscape
                                ? const Color(0xFF007AFF)
                                : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
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
    );
  }
}
