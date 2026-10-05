import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../data/government_preset_service.dart';

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
    extends ConsumerState<GovernmentDocumentsScreen> {
  // National ID state
  String? _idFrontPath;
  String? _idBackPath;

  // Compression state
  String? _compressionImagePath;
  int _selectedTargetKb = 200;
  bool _isCompressing = false;

  // Personal photo state
  String? _photoImagePath;
  GovDocType _selectedPhotoType = GovDocType.personalPhoto3x4;

  bool _isProcessing = false;
  String? _statusText;

  Future<String?> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      return result.files.first.path;
    }
    return null;
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
              Text(subtitle, style: const TextStyle(fontSize: 13.5)),
              const SizedBox(height: 8),
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
                      'حجم الملف الناتج: $sizeStr',
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
              label: const Text('طباعة'),
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
      _statusText = 'جارٍ دمج بطاقة الرقم القومي في صفحة A4 واحدة...';
    });

    try {
      final service = ref.read(governmentPresetServiceProvider);
      final pdfPath = await service.buildNationalIdA4(_idFrontPath!, _idBackPath!);
      if (!mounted) return;
      _showResultDialog(
        filePath: pdfPath,
        title: 'تم دمج بطاقة الرقم القومي بنجاح',
        subtitle: 'الصفحة متوافقة 100% مع متطلبات التقديم الحكومي المصري.',
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
      _showResultDialog(
        filePath: outPath,
        title: 'تم ضغط الصورة للموقع الحكومي',
        subtitle:
            'الصورة مضغوطة لتكون أقل من $_selectedTargetKb كيلوبايت وجاهزة للرفع.',
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
        subtitle: 'ورقة A4 مجهزة بخطوط القص جاهزة للطباعة فوراً.',
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

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الأوراق الحكومية المصرية',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: palette.accent, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'قوالب مصممة خصيصاً للمواطنين والطلاب في مصر للتقديم في البوابات الحكومية والجامعات والوظائف دون الحاجة لسايبر.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── 1. بطاقة الرقم القومي ──
              _buildSectionCard(
                title: 'بطاقة الرقم القومي (وش وضهر في A4)',
                subtitle:
                    'دمج وجه وظهر البطاقة في ورقة A4 واحدة بالأبعاد القياسية الرسمية ID-1.',
                icon: Icons.badge_rounded,
                iconColor: const Color(0xFF2563EB),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildPickerButton(
                            label: 'وجه البطاقة',
                            imagePath: _idFrontPath,
                            onPick: () async {
                              final path = await _pickImage();
                              if (path != null) setState(() => _idFrontPath = path);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPickerButton(
                            label: 'ظهر البطاقة',
                            imagePath: _idBackPath,
                            onPick: () async {
                              final path = await _pickImage();
                              if (path != null) setState(() => _idBackPath = path);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text(
                        'دمج البطاقة وتوليد PDF A4',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: (_idFrontPath != null && _idBackPath != null)
                          ? _buildNationalIdA4
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. ضغط البوابات الحكومية المصرية ──
              _buildSectionCard(
                title: 'ضغط مخصص للبوابات الحكومية',
                subtitle:
                    'تقليل الحجم بدقة ليتوافق مع القيود الصارمة للمواقع الحكومية (أقل من 200KB أو 500KB).',
                icon: Icons.speed_rounded,
                iconColor: palette.warning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPickerButton(
                      label: 'اختيار المستند أو الصورة للضغط',
                      imagePath: _compressionImagePath,
                      onPick: () async {
                        final path = await _pickImage();
                        if (path != null) {
                          setState(() {
                            _compressionImagePath = path;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'الحد الأقصى المسموح به للموقع:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: GovernmentPresetService.portalPresets.map((preset) {
                        final isSelected = _selectedTargetKb == preset.kb;
                        return ChoiceChip(
                          avatar: Icon(preset.icon, size: 16),
                          label: Text(preset.label),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setState(() => _selectedTargetKb = preset.kb);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: palette.warning,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.compress_rounded),
                      label: Text(
                        'ضغط الصورة لأقل من $_selectedTargetKb KB',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: (_compressionImagePath != null && !_isCompressing)
                          ? _compressForGovernmentPortal
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. صور شخصية رسمية ──
              _buildSectionCard(
                title: 'تخطيط الصور الشخصية (3×4 و 4×6)',
                subtitle:
                    'تجهيز شبكة صور شخصية متعددة على صفحة A4 واحدة جاهزة للطباعة والقص.',
                icon: Icons.photo_size_select_actual_rounded,
                iconColor: palette.success,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPickerButton(
                      label: 'اختيار صورتك الشخصية',
                      imagePath: _photoImagePath,
                      onPick: () async {
                        final path = await _pickImage();
                        if (path != null) setState(() => _photoImagePath = path);
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('3×4 سم (8 صور) - بطاقة وشهادات'),
                          selected: _selectedPhotoType ==
                              GovDocType.personalPhoto3x4,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedPhotoType =
                                  GovDocType.personalPhoto3x4);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('4×6 سم (4 صور) - جواز السفر'),
                          selected: _selectedPhotoType ==
                              GovDocType.personalPhoto4x6,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedPhotoType =
                                  GovDocType.personalPhoto4x6);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: palette.success,
                      ),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text(
                        'إنشاء ورقة A4 للطباعة',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed:
                          _photoImagePath != null ? _buildPersonalPhotoGrid : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 4. جواز السفر والشهادات ──
              _buildSectionCard(
                title: 'جواز السفر والشهادات الرسمية',
                subtitle: 'توسيط دقيق على A4 طولي أو عرضي.',
                icon: Icons.card_membership_rounded,
                iconColor: const Color(0xFF7C3AED),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            icon: const Icon(Icons.book_rounded, size: 18),
                            label: const Text('جواز سفر (طولي)'),
                            onPressed: () async {
                              final path = await _pickImage();
                              if (path == null) return;
                              final s = ref.read(governmentPresetServiceProvider);
                              final res = await s.buildPassportPage(path);
                              _showResultDialog(
                                filePath: res,
                                title: 'تم تجهيز جواز السفر',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            icon: const Icon(Icons.workspace_premium_rounded,
                                size: 18),
                            label: const Text('شهادة (عرضي)'),
                            onPressed: () async {
                              final path = await _pickImage();
                              if (path == null) return;
                              final s = ref.read(governmentPresetServiceProvider);
                              final res = await s.buildCertificatePage(path);
                              _showResultDialog(
                                filePath: res,
                                title: 'تم تجهيز الشهادة الرسمية',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242428) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusText ?? 'جارٍ المعالجة...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildPickerButton({
    required String label,
    required String? imagePath,
    required VoidCallback onPick,
  }) {
    final palette = context.appThemePalette;
    final isSelected = imagePath != null && File(imagePath).existsSync();

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.08)
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? palette.accent
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: isSelected
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(imagePath), fit: BoxFit.cover),
                    Container(color: Colors.black26),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_rounded,
                      color: palette.accent, size: 26),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }
}
