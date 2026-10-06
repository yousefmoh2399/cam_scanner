import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/native_scanner_bridge.dart';
import '../data/stamp_storage_service.dart';

/// Screen for managing, creating, and selecting Digital Stamps & Seals (100% Offline).
class StampStudioScreen extends StatefulWidget {
  const StampStudioScreen({
    super.key,
    this.targetPageImagePath,
  });

  /// If provided, selecting a stamp will return its transparent bytes for placement
  final String? targetPageImagePath;

  @override
  State<StampStudioScreen> createState() => _StampStudioScreenState();
}

class _StampStudioScreenState extends State<StampStudioScreen> {
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

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'إضافة ختم جديد للمكتبة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF007AFF)),
              title: const Text('تصوير ختم من ورقة حقيقية'),
              subtitle: const Text('وجّه الكاميرا نحو الختم المطبوع على الورقة'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF34C759)),
              title: const Text('اختيار صورة ختم من المعرض'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    String? capturedPath;
    if (choice == 'camera') {
      final docResults = await NativeScannerBridge.startScan();
      if (docResults.isNotEmpty) {
        capturedPath = docResults.first.path;
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
                  FilledButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () async {
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
                        : const Icon(Icons.check_rounded),
                    label: Text(isProcessing ? 'جاري الاستخراج والتفريغ...' : 'حفظ الختم في المكتبة'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    if (mounted) {
      Navigator.of(context).pop(bytes);
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'استوديو ومكتبة الأختام',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
                      const Icon(Icons.verified_user_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'لا توجد أختام محفوظة',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createNewStampDialog,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة ختم جديد'),
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
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
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
                                      child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.grey),
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
                                fontWeight: FontWeight.w800,
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
                                fontWeight: FontWeight.w700,
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
