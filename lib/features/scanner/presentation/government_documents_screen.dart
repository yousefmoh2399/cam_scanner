import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../data/government_preset_service.dart';
import '../data/native_scanner_bridge.dart';

/// Screen offering specialized Egyptian Government document templates:
/// - National ID Card (Front & Back merged on single A4 with exact ID-1 scale).
/// - Passport & Certificate presets.
/// - Calibrated compression limits (<100KB, <200KB, <500KB, <1MB).
/// - Official photo cutouts & print layouts (3x4 cm & 4x6 cm).
class GovernmentDocumentsScreen extends ConsumerStatefulWidget {
  const GovernmentDocumentsScreen({super.key});

  @override
  ConsumerState<GovernmentDocumentsScreen> createState() =>
      _GovernmentDocumentsScreenState();
}

class _GovernmentDocumentsScreenState
    extends ConsumerState<GovernmentDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // National ID state
  String? _idFrontPath;
  String? _idBackPath;
  bool _idActualSize = false; // false = 1.35x enlarged, true = 1:1 official

  // Compression state
  String? _compressionImagePath;
  int _selectedTargetKb = 200;
  bool _isCompressing = false;
  final TextEditingController _customKbController = TextEditingController();

  // Personal photo state
  String? _photoImagePath;
  GovDocType _selectedPhotoType = GovDocType.personalPhoto3x4;

  // Passport & Certificate state
  String? _passportImagePath;
  String? _certificateImagePath;

  bool _isProcessing = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customKbController.dispose();
    super.dispose();
  }

  /// Unified source picker: Camera, Gallery/Files, or Existing Library Document
  Future<String?> _pickImageWithSource(BuildContext context, {String? title}) async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];

    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                ),
                title: const Text('تصوير بالكاميرا الآن (مسح ضوئي)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('التقاط فوري مع ضبط الحدود تلقائياً'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.purple),
                ),
                title: const Text('اختيار من المعرض أو ملفات الجهاز',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('اختيار صورة محفوظة بصيغة JPG أو PNG'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (docs.isNotEmpty)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_shared_rounded, color: Colors.teal),
                  ),
                  title: const Text('اختيار من مستندات المكتبة',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${docs.length} مستندات متوفرة في مكتبتك'),
                  onTap: () => Navigator.pop(ctx, 'library'),
                ),
            ],
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
        if (scanResults.isNotEmpty) {
          return scanResults.first.path;
        }
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
      if (result != null && result.files.isNotEmpty) {
        return result.files.first.path;
      }
      return null;
    } else if (source == 'library') {
      if (!context.mounted) return null;
      return _pickPageFromLibrary(context, docs);
    }

    return null;
  }

  Future<String?> _pickPageFromLibrary(
    BuildContext context,
    List<PendingUpload> docs,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مستنداً من المكتبة لاستخدامه:',
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
                    final firstPagePath = d.pages.isNotEmpty
                        ? d.pages.first.imagePath
                        : (d.thumbnailPath ?? '');
                    return ListTile(
                      leading: firstPagePath.isNotEmpty &&
                              File(firstPagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(firstPagePath),
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
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

  /// Rotates an image file 90 degrees clockwise in place
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
      final newPath = p.join(dir, '${base}_rot_${DateTime.now().millisecondsSinceEpoch}.jpg');
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

  void _showResultDialog({
    required String filePath,
    required String title,
    String? subtitle,
  }) {
    final palette = context.appThemePalette;
    final file = File(filePath);
    final sizeStr = file.existsSync() ? formatFileSize(file.lengthSync()) : '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Text(subtitle, style: const TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 12),
            ],
            if (sizeStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: palette.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'حجم الملف النهائي: $sizeStr',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة'),
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(filePath)]);
            },
          ),
          if (filePath.endsWith('.pdf'))
            TextButton.icon(
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('طباعة فورية'),
              onPressed: () async {
                Navigator.pop(ctx);
                final bytes = await File(filePath).readAsBytes();
                await Printing.layoutPdf(onLayout: (_) => bytes);
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('فتح الملف'),
            onPressed: () {
              Navigator.pop(ctx);
              OpenFilex.open(filePath);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _buildNationalIdA4() async {
    if (_idFrontPath == null || _idBackPath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ توليد ورقة A4 بالأبعاد الرسمية لبطاقة الرقم القومي...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildNationalIdA4(
        _idFrontPath!,
        _idBackPath!,
        isActualSize: _idActualSize,
      );
      if (!mounted) return;
      _showResultDialog(
        filePath: pdfPath,
        title: 'تم دمج بطاقة الرقم القومي بنجاح',
        subtitle:
            'ورقة A4 الرسمية جاهزة ومجهزة بخطوط القص ومطابقة لمتطلبات التقديم الحكومي المصري والتعاملات البنكية.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الإنشاء: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _compressForGovernmentPortal() async {
    if (_compressionImagePath == null) return;
    setState(() => _isCompressing = true);

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final outPath = await service.compressToTargetSizeAndSave(
        _compressionImagePath!,
        targetKb: _selectedTargetKb,
      );
      if (!mounted) return;
      final originalSize = File(_compressionImagePath!).lengthSync();
      final newSize = File(outPath).lengthSync();
      final reduction =
          originalSize > 0 ? (((originalSize - newSize) / originalSize) * 100).round() : 0;

      _showResultDialog(
        filePath: outPath,
        title: 'تم ضغط الصورة للموقع الحكومي',
        subtitle:
            'الحجم قبل الضغط: ${formatFileSize(originalSize)}\nالحجم بعد الضغط: ${formatFileSize(newSize)} (تم توفير $reduction%)\nالملف جاهز للرفع على بوابات التقديم الرسمية.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الضغط: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCompressing = false);
    }
  }

  Future<void> _buildPersonalPhotoGrid() async {
    if (_photoImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ إعداد شبكة الصور الشخصية للطباعة...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildPersonalPhotoGrid(
        _photoImagePath!,
        _selectedPhotoType,
      );
      if (!mounted) return;
      final typeLabel = _selectedPhotoType == GovDocType.personalPhoto3x4
          ? '3×4 سم (8 صور)'
          : '4×6 سم (4 صور)';
      _showResultDialog(
        filePath: pdfPath,
        title: 'تم إعداد صفحة الصور الشخصية $typeLabel',
        subtitle:
            'ورقة A4 مصممة بمركز الصفحة ومجهزة بإطارات القص، جاهزة للطباعة على ورق الصور أو العادي.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الإعداد: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _buildPassportPage() async {
    if (_passportImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ تنسيق صفحة جواز السفر على A4...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildPassportPage(_passportImagePath!);
      if (!mounted) return;
      _showResultDialog(
        filePath: pdfPath,
        title: 'تم تجهيز جواز السفر على A4',
        subtitle:
            'تم توسيط وثيقة السفر وتأطيرها بنقاء عالي وتنسيق طولي مطابق لاشتراطات السفارات والجهات الرسمية.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تجهيز جواز السفر: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _buildCertificatePage() async {
    if (_certificateImagePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusText = 'جارٍ تنسيق الشهادة الرسمية على A4 عرضي...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildCertificatePage(_certificateImagePath!);
      if (!mounted) return;
      _showResultDialog(
        filePath: pdfPath,
        title: 'تم تجهيز الشهادة الرسمية',
        subtitle:
            'تم توسيط الشهادة وتأطيرها بإطار رسمي مذهب عرضي جاهز للأرشفة والتقديم الجامعي والحكومي.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تجهيز الشهادة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الأوراق الحكومية المصرية',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.badge_rounded, size: 20), text: 'بطاقة الرقم القومي'),
            Tab(icon: Icon(Icons.speed_rounded, size: 20), text: 'ضغط البوابات'),
            Tab(icon: Icon(Icons.photo_library_rounded, size: 20), text: 'صور شخصية'),
            Tab(icon: Icon(Icons.workspace_premium_rounded, size: 20), text: 'جواز وشهادات'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildNationalIdTab(palette),
              _buildPortalCompressionTab(palette),
              _buildPersonalPhotosTab(palette),
              _buildPassportAndCertificatesTab(palette),
            ],
          ),
          if (_isProcessing || _isCompressing)
            Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusText ?? 'جارٍ المعالجة...',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: بطاقة الرقم القومي
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNationalIdTab(AppThemePalette palette) {
    final canBuild = _idFrontPath != null && _idBackPath != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Intro Notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'دمج وجه وظهر البطاقة في ورقة A4 واحدة بالأبعاد القياسية ID-1 مع خطوط القص، مقبولة رسمياً في كافة المصالح الحكومية والبنوك المصرية.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Live A4 Page Preview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Page Header Simulation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'جمهورية مصر العربية',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'معاينة A4',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const Flexible(
                    child: Text(
                      'بطاقة الرقم القومي',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Front Card Slot
              _buildIdCardSlot(
                label: 'الوجه الأمامي للبطاقة (Front)',
                imagePath: _idFrontPath,
                onPick: () async {
                  final p = await _pickImageWithSource(
                    context,
                    title: 'اختيار الوجه الأمامي للبطاقة',
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

              const SizedBox(height: 8),
              // Cut line simulation
              Row(
                children: [
                  const Text('✂', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      height: 1,
                      color: Colors.grey.withValues(alpha: 0.35),
                    ),
                  ),
                  const Text('خط القص الرسمي',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 8),

              // Back Card Slot
              _buildIdCardSlot(
                label: 'الوجه الخلفي للبطاقة (Back)',
                imagePath: _idBackPath,
                onPick: () async {
                  final p = await _pickImageWithSource(
                    context,
                    title: 'اختيار الوجه الخلفي للبطاقة',
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

        // Scale Toggle: Actual vs Enlarged
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.straighten_rounded, size: 20, color: Colors.blueGrey),
              SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المقاس الفعلي الطبيعي (1:1)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      '85.6 × 54 مم (أوقف التكبير لطباعة الحجم الطبيعي للبطاقة)',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _idActualSize,
                onChanged: (val) => setState(() => _idActualSize = val),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Action Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: const Color(0xFF2563EB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: Text(
            canBuild
                ? 'دمج البطاقة وتوليد مستند A4 رسمي'
                : 'التقط أو اختر الوجهين لتوليد الملف',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: canBuild ? _buildNationalIdA4 : null,
        ),
      ],
    );
  }

  Widget _buildIdCardSlot({
    required String label,
    required String? imagePath,
    required VoidCallback onPick,
    required VoidCallback onRotate,
    required VoidCallback onClear,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasImage ? Colors.transparent : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasImage
              ? const Color(0xFF2563EB)
              : Colors.grey.withValues(alpha: 0.3),
          width: hasImage ? 1.5 : 1,
        ),
      ),
      child: hasImage
          ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Center(
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    children: [
                      IconButton.filledTonal(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.rotate_right_rounded),
                        tooltip: 'تدوير 90 درجة',
                        onPressed: onRotate,
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'تغيير الصورة',
                        onPressed: onPick,
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, color: Colors.red),
                        tooltip: 'حذف',
                        onPressed: onClear,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPick,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded,
                        size: 32, color: Color(0xFF2563EB)),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'اضغط للتصوير أو الاختيار من المعرض',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: ضغط البوابات الحكومية
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPortalCompressionTab(AppThemePalette palette) {
    final hasImage =
        _compressionImagePath != null && File(_compressionImagePath!).existsSync();
    final originalSize =
        hasImage ? File(_compressionImagePath!).lengthSync() : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.speed_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'يضمن التطبيق عدم تجاوز سقف الحجم المطلوب إطلاقاً حتى يقبله موقع التقديم الحكومي دون رسالة "حجم الملف يتعدى الحد المسموح".',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // File Selector Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_compressionImagePath!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.basename(_compressionImagePath!),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الحجم الأصلي: ${formatFileSize(originalSize)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: originalSize > _selectedTargetKb * 1024
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.change_circle_rounded),
                      tooltip: 'تغيير الصورة',
                      onPressed: () async {
                        final pth = await _pickImageWithSource(
                          context,
                          title: 'اختيار المستند المراد ضغطه',
                        );
                        if (pth != null) {
                          setState(() => _compressionImagePath = pth);
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 26),
                  label: const Text(
                    'اختر المستند أو الصورة للضغط (كاميرا / معرض / مكتبة)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    final pth = await _pickImageWithSource(
                      context,
                      title: 'اختيار المستند المراد ضغطه',
                    );
                    if (pth != null) {
                      setState(() => _compressionImagePath = pth);
                    }
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          'اختر السقف المطلوب للموقع الحكومي:',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 10),

        // Presets Grid
        Column(
          children: GovernmentPresetService.portalPresets.map((preset) {
            final isSelected = _selectedTargetKb == preset.kb;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: isSelected ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? palette.accent
                      : Colors.grey.withValues(alpha: 0.2),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? palette.accent
                      : Colors.grey.withValues(alpha: 0.15),
                  foregroundColor: isSelected ? Colors.white : Colors.blueGrey,
                  child: Icon(preset.icon, size: 20),
                ),
                title: Text(
                  preset.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                trailing: Text(
                  '< ${preset.kb} KB',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? palette.accent : Colors.grey,
                  ),
                ),
                onTap: () => setState(() => _selectedTargetKb = preset.kb),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // Action Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.compress_rounded),
          label: Text(
            'ضغط الصورة لتكون أقل من $_selectedTargetKb KB بدقة',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: (hasImage && !_isCompressing)
              ? _compressForGovernmentPortal
              : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: صور شخصية رسمية (3×4 و 4×6)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPersonalPhotosTab(AppThemePalette palette) {
    final hasImage =
        _photoImagePath != null && File(_photoImagePath!).existsSync();
    final is3x4 = _selectedPhotoType == GovDocType.personalPhoto3x4;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Intro Notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.photo_size_select_actual_rounded,
                  color: Colors.green, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تجهيز شبكة صور شخصية متعددة على ورقة A4 واحدة بمركز الصفحة ومجهزة بخطوط القص للطباعة فوراً.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Image Selector
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: hasImage
              ? Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_photoImagePath!),
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تم اختيار الصورة الشخصية',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('جاهزة لترتيبها في شبكة الطباعة A4',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'تغيير الصورة',
                      onPressed: () async {
                        final pth = await _pickImageWithSource(
                          context,
                          title: 'اختيار صورتك الشخصية',
                        );
                        if (pth != null) setState(() => _photoImagePath = pth);
                      },
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_a_photo_rounded, size: 26),
                  label: const Text(
                    'التقط صورتك بالكاميرا أو اخترها من المعرض',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    final pth = await _pickImageWithSource(
                      context,
                      title: 'اختيار صورتك الشخصية',
                    );
                    if (pth != null) setState(() => _photoImagePath = pth);
                  },
                ),
        ),

        const SizedBox(height: 18),

        // Photo Dimension Selector
        const Text(
          'اختر مقاس الصورة المطلوب:',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _selectedPhotoType = GovDocType.personalPhoto3x4),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: is3x4 ? palette.accent.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: is3x4 ? palette.accent : Colors.grey.withValues(alpha: 0.3),
                      width: is3x4 ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '3×4 سم (8 صور)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: is3x4 ? palette.accent : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'للبطاقة والكارنيهات',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _selectedPhotoType = GovDocType.personalPhoto4x6),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: !is3x4 ? palette.accent.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: !is3x4 ? palette.accent : Colors.grey.withValues(alpha: 0.3),
                      width: !is3x4 ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '4×6 سم (4 صور)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: !is3x4 ? palette.accent : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'للجواز والسفارات',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Live preview sheet representation
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                is3x4 ? 8 : 4,
                (_) => Container(
                  width: is3x4 ? 32 : 45,
                  height: is3x4 ? 42 : 65,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.grey.shade400, width: 0.5),
                  ),
                  child: hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.file(
                            File(_photoImagePath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.person, size: 20, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Action Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.print_rounded),
          label: Text(
            'إنشاء ورقة A4 للطباعة (${is3x4 ? '8 صور 3×4' : '4 صور 4×6'})',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: hasImage ? _buildPersonalPhotoGrid : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: جواز السفر والشهادات الرسمية
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPassportAndCertificatesTab(AppThemePalette palette) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Intro Notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: Colors.deepPurple, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تنسيق وثائق السفر والشهادات الأكاديمية والرسمية على صفحة A4 مخصصة بإطارات رسمية معتمدة.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Passport Section
        _buildDocCard(
          title: 'جواز السفر (تنسيق طولي A4)',
          subtitle:
              'توسيط وثيقة السفر وتنسيق أبعادها بدقة مع إضافة ترويسة جمهورية مصر العربية وإطار التأشيرات.',
          icon: Icons.menu_book_rounded,
          iconColor: Colors.blue.shade700,
          imagePath: _passportImagePath,
          buttonText: 'توليد ورقة جواز السفر A4',
          onPick: () async {
            final pth = await _pickImageWithSource(
              context,
              title: 'اختيار صورة صفحة جواز السفر',
            );
            if (pth != null) setState(() => _passportImagePath = pth);
          },
          onClear: () => setState(() => _passportImagePath = null),
          onGenerate: _buildPassportPage,
        ),

        const SizedBox(height: 18),

        // Certificate Section
        _buildDocCard(
          title: 'الشهادات الرسمية (تنسيق عرضي A4)',
          subtitle:
              'تنسيق شهادات التخرج، الميلاد، والخبرة في إطار مذهب رسمي فاخر صالحة للتقديم والأرشفة.',
          icon: Icons.card_membership_rounded,
          iconColor: Colors.amber.shade800,
          imagePath: _certificateImagePath,
          buttonText: 'توليد الشهادة الرسمية A4',
          onPick: () async {
            final pth = await _pickImageWithSource(
              context,
              title: 'اختيار صورة الشهادة الرسمية',
            );
            if (pth != null) setState(() => _certificateImagePath = pth);
          },
          onClear: () => setState(() => _certificateImagePath = null),
          onGenerate: _buildCertificatePage,
        ),
      ],
    );
  }

  Widget _buildDocCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String? imagePath,
    required String buttonText,
    required VoidCallback onPick,
    required VoidCallback onClear,
    required VoidCallback onGenerate,
  }) {
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: iconColor.withValues(alpha: 0.12),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (hasImage) ...[
            Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: IconButton.filledTonal(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, color: Colors.red),
                      onPressed: onClear,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text('اختيار الوثيقة (كاميرا / معرض / مكتبة)'),
              onPressed: onPick,
            ),
            const SizedBox(height: 12),
          ],

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: iconColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: Text(
              buttonText,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            onPressed: hasImage ? onGenerate : null,
          ),
        ],
      ),
    );
  }
}
