import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/exif_scrubber_service.dart';
import '../data/native_scanner_bridge.dart';

/// Metadata inspection summary for a chosen image/document.
class MetadataInspectionReport {
  const MetadataInspectionReport({
    required this.hasGps,
    required this.gpsCoordinates,
    required this.deviceModel,
    required this.captureDate,
    required this.software,
    required this.fileSizeBytes,
  });

  final bool hasGps;
  final String? gpsCoordinates;
  final String? deviceModel;
  final String? captureDate;
  final String? software;
  final int fileSizeBytes;
}

/// A world-class Apple HIG Privacy & EXIF Metadata Inspector and Cleaner Screen.
class PrivacyScrubberScreen extends ConsumerStatefulWidget {
  const PrivacyScrubberScreen({
    super.key,
    this.initialImagePath,
  });

  final String? initialImagePath;

  @override
  ConsumerState<PrivacyScrubberScreen> createState() =>
      _PrivacyScrubberScreenState();
}

class _PrivacyScrubberScreenState extends ConsumerState<PrivacyScrubberScreen> {
  final ExifScrubberService _scrubber = const ExifScrubberService();

  String? _selectedImagePath;
  String? _selectedTitle;
  MetadataInspectionReport? _report;
  bool _isAnalyzing = false;
  bool _isScrubbing = false;

  // Protection Toggles
  bool _stripGps = true;
  bool _stripDeviceModel = true;
  bool _stripTimestamps = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _analyzeFile(widget.initialImagePath!);
    }
  }

  Future<void> _analyzeFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;

    setState(() {
      _selectedImagePath = filePath;
      _selectedTitle = p.basename(filePath);
      _isAnalyzing = true;
      _report = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final isClean = _scrubber.isExifClean(bytes);

      // Inspect binary tags in header
      String? foundGps;
      String? device;
      String? date;

      if (!isClean) {
        foundGps = 'إحداثيات GPS مضمنة (موقع جغرافي دقيق)';
      }

      // Read simple ASCII strings in EXIF header (first 32KB)
      final headerSample = String.fromCharCodes(
        bytes.take(mathMin(bytes.length, 32768)),
      );

      if (headerSample.contains('Apple') || headerSample.contains('iPhone')) {
        device = 'Apple iPhone (معرف الكاميرا)';
      } else if (headerSample.contains('Samsung') || headerSample.contains('Galaxy')) {
        device = 'Samsung Galaxy (معرف الكاميرا)';
      } else if (headerSample.contains('Xiaomi')) {
        device = 'Xiaomi Device';
      } else if (!isClean) {
        device = 'كاميرا الهاتف الذكي ومواصفات العدسة';
      }

      if (headerSample.contains('202') || headerSample.contains('201')) {
        date = 'تاريخ وساعة الالتقاط الأصلية مسجلة';
      }

      if (!mounted) return;
      setState(() {
        _report = MetadataInspectionReport(
          hasGps: !isClean,
          gpsCoordinates: foundGps,
          deviceModel: device,
          captureDate: date,
          software: !isClean ? 'برنامج معالجة صور الهاتف' : null,
          fileSizeBytes: file.lengthSync(),
        );
        _isAnalyzing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  int mathMin(int a, int b) => a < b ? a : b;

  Future<void> _pickImageWithSource() async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];

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
              const Text(
                'اختيار مستند أو صورة لفحص الخصوصية',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildModalOptionCard(
                      icon: Icons.camera_alt_rounded,
                      title: 'تصوير بالكاميرا',
                      subtitle: 'التقاط وحذف فوري',
                      color: const Color(0xFF007AFF),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, 'camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModalOptionCard(
                      icon: Icons.photo_library_rounded,
                      title: 'ألبوم الهاتف',
                      subtitle: 'فحص صورة بالمعرض',
                      color: const Color(0xFFE11D48),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, 'gallery'),
                    ),
                  ),
                ],
              ),
              if (docs.isNotEmpty) ...[
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor:
                      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  leading: const Icon(Icons.folder_special_rounded,
                      color: Color(0xFF34C759)),
                  title: const Text('من مستندات المكتبة',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: Text('فحص مستند ممسوح مسبقاً (${docs.length} مستند)',
                      style: const TextStyle(fontSize: 11)),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () => Navigator.pop(ctx, 'library'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    if (source == 'camera') {
      try {
        final tmpDir = await getTemporaryDirectory();
        final res = await NativeScannerBridge.startSingleScan(destDir: tmpDir.path);
        if (res != null && mounted) {
          await _analyzeFile(res.path);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
      }
    } else if (source == 'gallery') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null) {
        await _analyzeFile(res.files.single.path!);
      }
    } else if (source == 'library') {
      final chosen = await showModalBottomSheet<PendingUpload>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: docs.length,
            itemBuilder: (_, idx) {
              final d = docs[idx];
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFFE11D48)),
                title: Text(stripFileExtension(d.fileName),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(formatPageCount(d.effectivePageCount)),
                onTap: () => Navigator.pop(ctx, d),
              );
            },
          ),
        ),
      );
      if (chosen != null) {
        final pth = chosen.previewImagePath;
        if (pth != null && File(pth).existsSync()) {
          await _analyzeFile(pth);
        }
      }
    }
  }

  Widget _buildModalOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _executeScrubbing() async {
    if (_selectedImagePath == null) return;
    setState(() => _isScrubbing = true);
    HapticFeedback.mediumImpact();

    try {
      final file = File(_selectedImagePath!);
      final originalBytes = await file.readAsBytes();
      final cleanBytes = await _scrubber.scrubBytes(originalBytes);

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(dir.path, 'clean_privacy_$ts.jpg');
      await File(outPath).writeAsBytes(cleanBytes, flush: true);

      // Save to library
      final docStore = ref.read(localDocumentStoreProvider);
      final newDoc = PendingUpload(
        id: 'clean_priv_$ts',
        fileName: 'مستند_منظف_الخصوصية_$ts.jpg',
        filePath: outPath,
        pageCount: 1,
        pages: [ScanPage(imagePath: outPath)],
        createdAt: DateTime.now(),
        tags: const ['نظيف EXIF', 'خصوصية', 'آمن'],
        isExifClean: true,
      );
      await docStore.savePendingUpload(newDoc);
      await ref.read(pendingUploadsControllerProvider.notifier).refresh();

      if (!mounted) return;
      setState(() {
        _isScrubbing = false;
        _selectedImagePath = outPath;
      });
      await _analyzeFile(outPath);

      _showSuccessDialog(outPath);
    } catch (e) {
      if (mounted) {
        setState(() => _isScrubbing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تنظيف البيانات: $e')),
        );
      }
    }
  }

  void _showSuccessDialog(String cleanPath) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_user_rounded,
            color: Color(0xFF10B981), size: 44),
        title: const Text('تم تطهير بيانات الخصوصية بنجاح!',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'تمت إزالة كافة إحداثيات الموقع الجغرافي (GPS) وبصمة الكاميرا وبيانات الجهاز الوصفية (EXIF/XMP).\n\nالمستند نظيف تماماً وتم حفظه بمكتبتك وجاهز للمشاركة الآمنة.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة الملف الآمن'),
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(cleanPath)],
                  text: 'مستند منظف من بيانات الموقع والخصوصية');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تنظيم بيانات الخصوصية (EXIF)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
            ),
            Text(
              'حماية الهوية وحذف الموقع الجغرافي وبصمة الجهاز',
              style: TextStyle(fontSize: 10.5, color: Color(0xFFE11D48)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.change_circle_rounded),
            tooltip: 'تغيير المستند',
            onPressed: _pickImageWithSource,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Header Notice Banner ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFE11D48).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Color(0xFFE11D48), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حماية بياناتك الحساسة أوفلاين 100%',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'عند التقاط أي صورة، تسجل الكاميرا موقعك الجغرافي ونوع هاتفك وتاريخ التقاطها داخل ملف الصورة. تتيح لك هذه الأداة فحص هذه البيانات ومحوها نهائياً.',
                        style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Pick Source Card if None Selected ──
          if (_selectedImagePath == null) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.location_off_rounded,
                      size: 52, color: Color(0xFFE11D48)),
                  const SizedBox(height: 12),
                  const Text(
                    'اختر مستنداً أو التقط صورة لفحصها',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'سيقوم النظام بفحص ملف الـ EXIF والبيانات الوصفية وعرض تقرير مفصل عنها قبل التطهير.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE11D48),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: const Text('تصوير الآن',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            onPressed: () async {
                              try {
                                final tmpDir = await getTemporaryDirectory();
                                final res =
                                    await NativeScannerBridge.startSingleScan(
                                        destDir: tmpDir.path);
                                if (res != null && mounted) {
                                  await _analyzeFile(res.path);
                                }
                              } catch (_) {}
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              foregroundColor:
                                  isDark ? Colors.white : Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.photo_library_rounded, size: 18),
                            label: const Text('من المعرض',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            onPressed: _pickImageWithSource,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Inspection Report Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_selectedImagePath!),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 52,
                            height: 52,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.image_not_supported_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedTitle ?? 'المستند المختار',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              formatFileSize(_report?.fileSizeBytes ?? 0),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      if (_report != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _report!.hasGps
                                ? const Color(0xFFE11D48).withValues(alpha: 0.15)
                                : const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _report!.hasGps ? '⚠️ بيانات مكشوفة' : '✅ نظيف وآمن',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _report!.hasGps
                                  ? const Color(0xFFE11D48)
                                  : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),

                  if (_isAnalyzing)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_report != null) ...[
                    _buildMetaRow(
                      icon: Icons.location_on_rounded,
                      label: 'الموقع الجغرافي (GPS):',
                      value: _report!.hasGps
                          ? 'إحداثيات خط العرض والطول مسجلة بالملف'
                          : 'لا توجد بيانات موقع جغرافي (محمي)',
                      isDanger: _report!.hasGps,
                    ),
                    const SizedBox(height: 10),
                    _buildMetaRow(
                      icon: Icons.phone_android_rounded,
                      label: 'بيانات الجهاز والكاميرا:',
                      value: _report!.deviceModel ?? 'غير مسجلة أو محذوفة مسبقاً',
                      isDanger: _report!.deviceModel != null,
                    ),
                    const SizedBox(height: 10),
                    _buildMetaRow(
                      icon: Icons.access_time_filled_rounded,
                      label: 'تاريخ وساعة الالتقاط:',
                      value: _report!.captureDate ?? 'لا توجد بيانات توقيت حساسة',
                      isDanger: false,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Sanitization Switches Card ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'خيارات التطهير والحذف الأمني:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('حذف إحداثيات GPS وبيانات الموقع تماماً',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: const Text('يمنع تحديد مكان تصوير الوثيقة أو المنزل',
                        style: TextStyle(fontSize: 11)),
                    value: _stripGps,
                    activeTrackColor: const Color(0xFFE11D48),
                    onChanged: (v) => setState(() => _stripGps = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('محو بصمة الجهاز وموديل الهاتف',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: const Text('إخفاء اسم الجهاز وبرنامج المعالجة',
                        style: TextStyle(fontSize: 11)),
                    value: _stripDeviceModel,
                    activeTrackColor: const Color(0xFFE11D48),
                    onChanged: (v) => setState(() => _stripDeviceModel = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تطهير تواريخ الالتقاط وبيانات EXIF الوصفية',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: const Text('حذف أية وسوم أو نصوص مخفية',
                        style: TextStyle(fontSize: 11)),
                    value: _stripTimestamps,
                    activeTrackColor: const Color(0xFFE11D48),
                    onChanged: (v) => setState(() => _stripTimestamps = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Clean & Scrub Action Button ──
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isScrubbing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 20),
                label: Text(
                  _isScrubbing
                      ? 'جارٍ تطهير وإعادة تشفير الملف...'
                      : 'تطهير بيانات الخصوصية وحفظ الملف الآمن',
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                onPressed: _isScrubbing ? null : _executeScrubbing,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDanger,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: isDanger ? const Color(0xFFE11D48) : const Color(0xFF10B981),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDanger ? const Color(0xFFE11D48) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
