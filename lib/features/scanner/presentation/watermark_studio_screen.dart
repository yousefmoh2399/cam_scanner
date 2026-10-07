import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/watermark_service.dart';

class WatermarkStudioScreen extends ConsumerStatefulWidget {
  const WatermarkStudioScreen({
    super.key,
    this.initialDocument,
    this.initialImagePath,
  });

  final PendingUpload? initialDocument;
  final String? initialImagePath;

  @override
  ConsumerState<WatermarkStudioScreen> createState() =>
      _WatermarkStudioScreenState();
}

class _WatermarkStudioScreenState extends ConsumerState<WatermarkStudioScreen> {
  final WatermarkService _watermarkService = WatermarkService();
  final TextEditingController _textController =
      TextEditingController(text: 'صورة طبق الأصل');

  String? _selectedImagePath;
  PendingUpload? _selectedDoc;

  WatermarkStyle _style = WatermarkStyle.tiledDiagonal;
  WatermarkColorTheme _colorTheme = WatermarkColorTheme.securityRed;
  double _opacity = 0.28;
  bool _includeDate = true;

  Uint8List? _previewBytes;
  bool _isGeneratingPreview = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDoc = widget.initialDocument;
    if (widget.initialImagePath != null) {
      _selectedImagePath = widget.initialImagePath;
    } else if (widget.initialDocument != null &&
        widget.initialDocument!.pages.isNotEmpty) {
      _selectedImagePath = widget.initialDocument!.pages.first.imagePath;
    }

    _textController.addListener(_debouncedUpdatePreview);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedImagePath != null) {
        _generatePreview();
      }
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_debouncedUpdatePreview);
    _textController.dispose();
    super.dispose();
  }

  void _debouncedUpdatePreview() {
    _generatePreview();
  }

  Future<void> _generatePreview() async {
    if (_selectedImagePath == null) return;
    final file = File(_selectedImagePath!);
    if (!file.existsSync()) return;

    setState(() => _isGeneratingPreview = true);

    try {
      final bytes = await file.readAsBytes();
      final config = WatermarkConfig(
        text: _textController.text.trim().isEmpty
            ? 'صورة طبق الأصل'
            : _textController.text.trim(),
        style: _style,
        colorTheme: _colorTheme,
        opacity: _opacity,
        includeDate: _includeDate,
      );

      final watermarked = await _watermarkService.applyWatermarkToBytes(
        imageBytes: bytes,
        config: config,
      );

      if (mounted) {
        setState(() {
          _previewBytes = watermarked;
          _isGeneratingPreview = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isGeneratingPreview = false);
      }
    }
  }

  Future<void> _pickExternalImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      setState(() {
        _selectedImagePath = result.files.first.path;
        _selectedDoc = null;
      });
      await _generatePreview();
    }
  }

  Future<void> _selectDocumentFromLibrary() async {
    final docs = await ref.read(pendingUploadsControllerProvider.future);
    if (!mounted) return;

    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<PendingUpload>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'اختر مستنداً لحمايته بالعلامة المائية',
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
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.description_rounded, color: Colors.blue),
                          ),
                          title: Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${d.pages.length} صفحات'),
                          onTap: () => Navigator.of(ctx).pop(d),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null && selected.pages.isNotEmpty) {
      setState(() {
        _selectedDoc = selected;
        _selectedImagePath = selected.pages.first.imagePath;
      });
      await _generatePreview();
    }
  }

  Future<void> _saveProtectedDocument() async {
    if (_selectedImagePath == null || _previewBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار مستند أولاً.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final config = WatermarkConfig(
        text: _textController.text.trim().isEmpty
            ? 'صورة طبق الأصل'
            : _textController.text.trim(),
        style: _style,
        colorTheme: _colorTheme,
        opacity: _opacity,
        includeDate: _includeDate,
      );

      final outPath = await _watermarkService.applyWatermarkToFile(
        sourceImagePath: _selectedImagePath!,
        config: config,
      );

      // Create new document in store
      final docStore = ref.read(localDocumentStoreProvider);
      final newDoc = PendingUpload(
        id: 'watermarked_${DateTime.now().millisecondsSinceEpoch}',
        fileName: '${_selectedDoc?.title ?? "مستند"}_محمي_أمنياً',
        filePath: outPath,
        pageCount: 1,
        pages: [
          ScanPage(
            imagePath: outPath,
          ),
        ],
        createdAt: DateTime.now(),
        tags: const ['محمي أمنياً', 'علامة مائية'],
      );

      await docStore.savePendingUpload(newDoc);
      await ref.read(pendingUploadsControllerProvider.notifier).refresh();

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: const Text(
              'تم حفظ المستند المحمي بالعلامة المائية بنجاح في مكتبتك!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.white,
              onPressed: () {
                Share.shareXFiles([XFile(outPath)], text: newDoc.title);
              },
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
        );
      }
    }
  }

  Future<void> _shareDirectly() async {
    if (_selectedImagePath == null) return;
    setState(() => _isSaving = true);
    try {
      final config = WatermarkConfig(
        text: _textController.text.trim().isEmpty
            ? 'صورة طبق الأصل'
            : _textController.text.trim(),
        style: _style,
        colorTheme: _colorTheme,
        opacity: _opacity,
        includeDate: _includeDate,
      );

      final outPath = await _watermarkService.applyWatermarkToFile(
        sourceImagePath: _selectedImagePath!,
        config: config,
      );

      setState(() => _isSaving = false);
      await Share.shareXFiles(
        [XFile(outPath)],
        text: 'مستند محمي بالعلامة المائية الأمنية (100% Offline)',
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في المشاركة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
          title: const Text(
            'العلامة المائية والأختام الأمنية',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: 'مشاركة فورية',
              icon: const Icon(Icons.share_rounded),
              onPressed: _selectedImagePath != null && !_isSaving ? _shareDirectly : null,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Document Selection Row ──
              Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: palette.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        color: _colorTheme.color,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedDoc != null
                                  ? _selectedDoc!.title
                                  : (_selectedImagePath != null
                                      ? 'صورة خارجية محددة'
                                      : 'لم يتم اختيار مستند'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'اختر من المكتبة أو المعرض',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'المكتبة',
                        icon: const Icon(Icons.folder_open_rounded, size: 22),
                        onPressed: _selectDocumentFromLibrary,
                      ),
                      IconButton(
                        tooltip: 'صورة من المعرض',
                        icon: const Icon(Icons.photo_library_rounded, size: 22),
                        onPressed: _pickExternalImage,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Interactive Live Preview Box ──
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF000000) : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_previewBytes != null)
                        InteractiveViewer(
                          maxScale: 4.0,
                          child: Center(
                            child: Image.memory(
                              _previewBytes!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded, size: 48),
                              ),
                            ),
                          ),
                        )
                      else if (_selectedImagePath != null)
                        Image.file(
                          File(_selectedImagePath!),
                          fit: BoxFit.contain,
                          cacheWidth: 1440,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, size: 48),
                          ),
                        )
                      else
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.security_rounded,
                              size: 48,
                              color: palette.accent.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'اضغط على "المكتبة" بالأعلى لاختيار بطاقة أو مستند لمعاينته هنا',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      if (_isGeneratingPreview)
                        Container(
                          color: Colors.black38,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'معاينة حية فورية',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Egyptian Security Presets (1-Tap Selection) ──
              const Text(
                'عبارات أمنية مصرية شائعة (اختر بنقرة واحدة):',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WatermarkConfig.egyptianPresets.map((preset) {
                  final isSelected = _textController.text == preset;
                  return ChoiceChip(
                    label: Text(
                      preset,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _textController.text = preset;
                      });
                      _generatePreview();
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // ── Custom Watermark Text Field ──
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'أو اكتب نصاً مخصصاً بالكامل',
                  hintText: 'مثال: مقدمة لشركة النور بتاريخ...',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              const SizedBox(height: 16),

              // ── Style Selection (Tiled Diagonal vs Stamp vs Diagonal Banner) ──
              const Text(
                'نمط العلامة المائية والأمان:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StyleCard(
                      title: 'شبكة متكررة',
                      subtitle: 'تغطي كامل الورقة لمنع التزوير',
                      icon: Icons.grid_on_rounded,
                      isSelected: _style == WatermarkStyle.tiledDiagonal,
                      onTap: () {
                        setState(() => _style = WatermarkStyle.tiledDiagonal);
                        _generatePreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StyleCard(
                      title: 'ختم أمني معتمد',
                      subtitle: 'مستطيل رسمي بإطار مزدوج وتاريخ',
                      icon: Icons.approval_rounded,
                      isSelected: _style == WatermarkStyle.officialStamp,
                      onTap: () {
                        setState(() => _style = WatermarkStyle.officialStamp);
                        _generatePreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StyleCard(
                      title: 'شريط مائل',
                      subtitle: 'شريط عريض بمنتصف الصفحة',
                      icon: Icons.remove_rounded,
                      isSelected: _style == WatermarkStyle.diagonalBanner,
                      onTap: () {
                        setState(() => _style = WatermarkStyle.diagonalBanner);
                        _generatePreview();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Color Theme Picker ──
              const Text(
                'لون الختم الأمني:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: WatermarkColorTheme.values.map((c) {
                    final isSelected = _colorTheme == c;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _colorTheme = c);
                          _generatePreview();
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    BoxShadow(
                                      color: c.color.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.labelAr,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // ── Opacity & Date Controls ──
              Row(
                children: [
                  const Text(
                    'الشفافية:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  Expanded(
                    child: Slider(
                      value: _opacity,
                      min: 0.12,
                      max: 0.70,
                      divisions: 10,
                      label: '${(_opacity * 100).round()}%',
                      onChanged: (v) {
                        setState(() => _opacity = v);
                        _generatePreview();
                      },
                    ),
                  ),
                  Text(
                    '${(_opacity * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'إضافة تاريخ اليوم تلقائياً مع الختم',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                subtitle: const Text(
                  'لتوثيق توقيت وتاريخ تقديم الوثيقة للجهة المستلمة',
                  style: TextStyle(fontSize: 11),
                ),
                value: _includeDate,
                onChanged: (v) {
                  setState(() => _includeDate = v);
                  _generatePreview();
                },
              ),

              const SizedBox(height: 20),

              // ── Save Button ──
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _colorTheme.color,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shield_rounded),
                label: Text(
                  _isSaving
                      ? 'جاري تطبيق الحماية الأمنية...'
                      : 'حفظ المستند المحمي في المكتبة',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                onPressed: _selectedImagePath != null && !_isSaving
                    ? _saveProtectedDocument
                    : null,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? palette.accent : Colors.transparent,
            width: 1.8,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? palette.accent : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
