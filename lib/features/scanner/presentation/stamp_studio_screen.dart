import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import '../data/stamp_storage_service.dart';
import 'scan_review_screen.dart';
import 'signature_placement_screen.dart';

/// Screen for managing, creating, and selecting Digital Stamps & Seals (100% Offline).
class StampStudioScreen extends ConsumerStatefulWidget {
  const StampStudioScreen({
    super.key,
    this.targetPageImagePath,
  });

  /// If provided, selecting a stamp will return its transparent bytes for placement
  final String? targetPageImagePath;

  @override
  ConsumerState<StampStudioScreen> createState() => _StampStudioScreenState();
}

class _StampStudioScreenState extends ConsumerState<StampStudioScreen> {
  final StampStorageService _storageService = StampStorageService();
  List<DigitalStamp> _stamps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStamps();
  }

  Future<void> _loadStamps() async {
    setState(() => _isLoading = true);
    final list = await _storageService.loadAllStamps();
    if (mounted) {
      setState(() {
        _stamps = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewStampDialog() async {
    HapticFeedback.lightImpact();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'إضافة ختم جديد للمكتبة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'التقط ختماً من ورقة حقيقية أو استورد تصميماً جاهزاً',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'camera');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF007AFF), size: 22),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'تصوير ختم حي',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'من ورقة بالكاميرا',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'gallery');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF34C759).withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.photo_library_rounded, color: Color(0xFF34C759), size: 22),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'ألبوم الصور',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'استيراد صورة ختم',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
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
        ),
      ),
    );

    if (choice == null || !mounted) return;

    String? capturedPath;
    if (choice == 'camera') {
      try {
        final docResults = await NativeScannerBridge.startScan();
        if (docResults.isNotEmpty && mounted) {
          final res = docResults.first;
          capturedPath = await openScanReviewScreen(
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
        return;
      }
    } else {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null) {
        capturedPath = res.files.single.path;
      }
    }

    if (capturedPath == null || !mounted) return;

    await _showStampEditorSheet(capturedPath);
  }

  Future<void> _showStampEditorSheet(String rawImagePath) async {
    final rawBytes = await File(rawImagePath).readAsBytes();
    final nameController = TextEditingController(text: 'ختم رسمي جديد');
    StampColorFilter selectedColor = StampColorFilter.officialRed;
    double sensitivity = 0.82;
    double opacity = 0.88;
    bool isProcessing = false;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ضبط وتفريغ الختم الذكي',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Name Field
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'اسم الختم',
                      prefixIcon: const Icon(Icons.label_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Color Tint Selector
                  const Text(
                    'لون حبر الختم:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildColorChip(
                        label: 'أحمر رسمي',
                        color: const Color(0xFFD62B2B),
                        isSelected: selectedColor == StampColorFilter.officialRed,
                        onTap: () => setSheetState(
                          () => selectedColor = StampColorFilter.officialRed,
                        ),
                      ),
                      _buildColorChip(
                        label: 'أزرق ملكي',
                        color: const Color(0xFF007AFF),
                        isSelected: selectedColor == StampColorFilter.royalBlue,
                        onTap: () => setSheetState(
                          () => selectedColor = StampColorFilter.royalBlue,
                        ),
                      ),
                      _buildColorChip(
                        label: 'أخضر زمردي',
                        color: const Color(0xFF34C759),
                        isSelected: selectedColor == StampColorFilter.emeraldGreen,
                        onTap: () => setSheetState(
                          () => selectedColor = StampColorFilter.emeraldGreen,
                        ),
                      ),
                      _buildColorChip(
                        label: 'أسود تنفيذي',
                        color: const Color(0xFF2C2C2E),
                        isSelected: selectedColor == StampColorFilter.executiveBlack,
                        onTap: () => setSheetState(
                          () => selectedColor = StampColorFilter.executiveBlack,
                        ),
                      ),
                      _buildColorChip(
                        label: 'اللون الأصلي',
                        color: Colors.grey,
                        isSelected: selectedColor == StampColorFilter.original,
                        onTap: () => setSheetState(
                          () => selectedColor = StampColorFilter.original,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Sensitivity Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'دقة تفريغ خلفية الورق',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        '${(sensitivity * 100).toInt()}%',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                  Slider(
                    value: sensitivity,
                    min: 0.60,
                    max: 0.95,
                    onChanged: (v) => setSheetState(() => sensitivity = v),
                  ),

                  // Opacity Slider (Ink Bleed)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'شفافية وتشبع الحبر (Ink Bleed)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        '${(opacity * 100).toInt()}%',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                  Slider(
                    value: opacity,
                    min: 0.40,
                    max: 1.0,
                    onChanged: (v) => setSheetState(() => opacity = v),
                  ),
                  const SizedBox(height: 16),

                  // Save Button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () async {
                              HapticFeedback.mediumImpact();
                              setSheetState(() => isProcessing = true);
                              try {
                                await _storageService.createCustomStampFromBytes(
                                  rawImageBytes: rawBytes,
                                  title: nameController.text.trim().isEmpty
                                      ? 'ختم رسمي'
                                      : nameController.text.trim(),
                                  sensitivity: sensitivity,
                                  colorFilter: selectedColor,
                                  opacity: opacity,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _loadStamps();
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('تعذر استخراج الختم: $e')),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) setSheetState(() => isProcessing = false);
                              }
                            },
                      icon: isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        isProcessing ? 'جاري الاستخراج والتفريغ...' : 'حفظ الختم في المكتبة',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorChip({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectStamp(DigitalStamp stamp) async {
    HapticFeedback.lightImpact();
    final bytes = await File(stamp.imagePath).readAsBytes();
    if (widget.targetPageImagePath != null) {
      if (mounted) {
        Navigator.of(context).pop(bytes);
      }
      return;
    }
    await _showStampActionsSheet(stamp, bytes);
  }

  Future<void> _showStampActionsSheet(DigitalStamp stamp, Uint8List stampBytes) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title & Badge Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stamp.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stamp.isBuiltIn ? 'ختم رسمي معتمد' : 'ختم مخصص من مكتبتك',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!stamp.isBuiltIn)
                    IconButton(
                      tooltip: 'حذف الختم',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteStamp(stamp);
                      },
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // High-Res Checkerboard Transparency Stamp Preview Card
              Container(
                height: 150,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Image.file(
                    File(stamp.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Action 1: Apply to document (Stamp a page)
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _applyStampToDocumentFlow(stamp, stampBytes);
                  },
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text(
                    'تطبيق الختم على وثيقة أو ورقة',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Action 2: Share transparent PNG
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                    Share.shareXFiles(
                      [XFile(stamp.imagePath)],
                      text: 'ختم رقمي مفرغ (${stamp.title})',
                    );
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text(
                    'مشاركة صورة الختم المفرغة (PNG شفاف)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyStampToDocumentFlow(DigitalStamp stamp, Uint8List stampBytes) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sourceChoice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'اختر المستند المراد ختمه',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'التقط صورة بالكاميرا أو اختر مستنداً لختمه رسمياً',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'camera');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF007AFF), size: 20),
                            ),
                            const SizedBox(height: 8),
                            const Text('الكاميرا', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                            const SizedBox(height: 1),
                            Text('مسح وثيقة', style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'gallery');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF34C759).withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.photo_library_rounded, color: Color(0xFF34C759), size: 20),
                            ),
                            const SizedBox(height: 8),
                            const Text('معرض الصور', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                            const SizedBox(height: 1),
                            Text('من الهاتف', style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'library');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFF9500).withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.folder_open_rounded, color: Color(0xFFFF9500), size: 20),
                            ),
                            const SizedBox(height: 8),
                            const Text('المكتبة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                            const SizedBox(height: 1),
                            Text('مستند محفوظ', style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (sourceChoice == null || !mounted) return;

    String? targetPath;
    if (sourceChoice == 'camera') {
      try {
        final tmpDir = await getTemporaryDirectory();
        final res = await NativeScannerBridge.startSingleScan(destDir: tmpDir.path);
        if (res != null) targetPath = res.path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
          );
        }
        return;
      }
    } else if (sourceChoice == 'gallery') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null) {
        targetPath = res.files.single.path;
      }
    } else if (sourceChoice == 'library') {
      final docs = await ref.read(pendingUploadsControllerProvider.future);
      if (!mounted) return;
      if (docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً')),
        );
        return;
      }

      final chosenDoc = await showModalBottomSheet<PendingUpload>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetCtx) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'اختر مستنداً من المكتبة لختمه',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      return ListTile(
                        leading: const Icon(Icons.description_rounded, color: Color(0xFF007AFF)),
                        title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${d.pages.length} صفحات'),
                        onTap: () => Navigator.of(sheetCtx).pop(d),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (chosenDoc != null && chosenDoc.pages.isNotEmpty) {
        targetPath = chosenDoc.pages.first.imagePath;
      }
    }

    if (targetPath == null || !mounted) return;

    // Open Signature/Stamp placement editor!
    final compositedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => SignaturePlacementScreen(
          pageImagePath: targetPath!,
          signatureBytes: stampBytes,
        ),
        fullscreenDialog: true,
      ),
    );

    if (compositedBytes == null || !mounted) return;

    // Save stamped image to app docs and add to library
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(docsDir.path, 'stamped_${stamp.id}_$timeStamp.jpg');
      await File(outPath).writeAsBytes(compositedBytes, flush: true);

      final newDoc = PendingUpload(
        id: 'stamped_doc_$timeStamp',
        fileName: 'مستند_مختوم_${stamp.title}',
        filePath: outPath,
        pageCount: 1,
        pages: [ScanPage(imagePath: outPath)],
        createdAt: DateTime.now(),
        tags: const ['مختوم', 'أختام'],
      );

      final docStore = ref.read(localDocumentStoreProvider);
      await docStore.savePendingUpload(newDoc);
      await ref.read(pendingUploadsControllerProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF34C759),
            content: Text('تم ختم المستند بـ "${stamp.title}" وحفظه بالمكتبة بنجاح!'),
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ المستند المختوم: $e')),
        );
      }
    }
  }

  Future<void> _deleteStamp(DigitalStamp stamp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('حذف الختم'),
        content: Text('هل أنت متأكد من حذف ختم "${stamp.title}" من مكتبتك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2D55)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deleteStamp(stamp.id);
      await _loadStamps();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.appThemePalette;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'استوديو ومكتبة الأختام',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'إضافة ختم جديد',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _createNewStampDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _stamps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 64, color: Color(0xFF8E8E93)),
                      const SizedBox(height: 12),
                      const Text(
                        'لا توجد أختام محفوظة',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _createNewStampDialog();
                          },
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('إضافة ختم جديد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.95,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _stamps.length,
                  itemBuilder: (ctx, idx) {
                    final stamp = _stamps[idx];
                    return InkWell(
                      onTap: () => _selectStamp(stamp),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header badge & delete button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (stamp.isBuiltIn
                                            ? const Color(0xFF007AFF)
                                            : const Color(0xFF34C759))
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    stamp.isBuiltIn ? 'رسمي' : 'مخصص',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: stamp.isBuiltIn
                                          ? const Color(0xFF007AFF)
                                          : const Color(0xFF34C759),
                                    ),
                                  ),
                                ),
                                if (!stamp.isBuiltIn)
                                  InkWell(
                                    onTap: () => _deleteStamp(stamp),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFF8E8E93)),
                                    ),
                                  ),
                              ],
                            ),
                            const Spacer(),

                            // Stamp Image (Checkerboard background to demonstrate transparency)
                            Center(
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 80),
                                child: Image.file(
                                  File(stamp.imagePath),
                                  cacheWidth: 320,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_rounded, size: 36),
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),

                            // Title & Tap action
                            Text(
                              stamp.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.targetPageImagePath != null
                                  ? 'اضغط لوضع الختم'
                                  : 'اضغط للنسخ والاستخدام',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: palette.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewStampDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة ختم جديد'),
      ),
    );
  }
}
