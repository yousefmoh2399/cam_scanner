import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/notebook_lines_remover_service.dart';

/// Screen allowing the user to photograph lined notebooks, lined pads, or graph paper,
/// and automatically erase ruling lines and grids while preserving handwriting.
class NotebookLinesRemoverScreen extends ConsumerStatefulWidget {
  const NotebookLinesRemoverScreen({
    super.key,
    this.initialImagePath,
  });

  final String? initialImagePath;

  @override
  ConsumerState<NotebookLinesRemoverScreen> createState() =>
      _NotebookLinesRemoverScreenState();
}

class _NotebookLinesRemoverScreenState
    extends ConsumerState<NotebookLinesRemoverScreen> {
  final NotebookLinesRemoverService _service =
      const NotebookLinesRemoverService();

  Uint8List? _originalBytes;
  Uint8List? _processedBytes;

  NotebookPaperType _selectedType = NotebookPaperType.horizontalLined;
  double _sensitivity = 0.55;
  bool _whitenBackground = true;
  bool _preserveColoredInk = true;
  bool _enhanceHandwriting = true;

  bool _isProcessing = false;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _loadImage(widget.initialImagePath!);
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _isProcessing = true;
      _processedBytes = null;
    });

    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _originalBytes = bytes;
      });
      await _processImage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الصورة: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      await _loadImage(result.files.single.path!);
    }
  }

  Future<void> _processImage() async {
    if (_originalBytes == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.selectionClick();

    try {
      final config = NotebookRemovalConfig(
        paperType: _selectedType,
        sensitivity: _sensitivity,
        whitenBackground: _whitenBackground,
        preserveColoredInk: _preserveColoredInk,
        enhanceHandwriting: _enhanceHandwriting,
      );

      final out = await _service.removeNotebookLines(
        inputBytes: _originalBytes!,
        config: config,
      );

      if (!mounted) return;
      setState(() {
        _processedBytes = out;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء معالجة الورقة: $e')),
      );
    }
  }

  Future<void> _saveResult() async {
    if (_processedBytes == null) return;
    HapticFeedback.mediumImpact();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(dir.path, 'clean_notes_$ts.png');
      await File(filePath).writeAsBytes(_processedBytes!, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الملاحظات النقية بنجاح:\n${p.basename(filePath)}'),
          action: SnackBarAction(
            label: 'فتح',
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الملف: $e')),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_processedBytes == null) return;
    HapticFeedback.mediumImpact();

    try {
      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(_processedBytes!);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Center(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(dir.path, 'clean_notes_doc_$ts.pdf');
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save(), flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم تصدير مستند PDF بنجاح'),
          action: SnackBarAction(
            label: 'فتح المستند',
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير PDF: $e')),
      );
    }
  }

  Future<void> _shareResult() async {
    if (_processedBytes == null) return;
    HapticFeedback.lightImpact();

    final dir = await getTemporaryDirectory();
    final tempPath = p.join(dir.path, 'clean_notes_share.png');
    await File(tempPath).writeAsBytes(_processedBytes!, flush: true);

    await Share.shareXFiles(
      [XFile(tempPath)],
      text: 'ملاحظات دفتر نقية بدون خطوط تسطير • تطبيق لقطة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text(
          'مزيل خطوط الدفاتر والشبكات',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded),
            tooltip: 'اختيار صورة جديدة',
            onPressed: _pickImage,
          ),
          if (_processedBytes != null) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'مشاركة',
              onPressed: _shareResult,
            ),
          ],
        ],
      ),
      body: _originalBytes == null
          ? _buildEmptyState(isDark)
          : Column(
              children: [
                // Top Interactive Preview Area
                Expanded(
                  flex: 5,
                  child: _buildPreviewArea(isDark),
                ),

                // Bottom Controls Card
                Expanded(
                  flex: 6,
                  child: _buildControlsArea(isDark),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 46,
                color: Color(0xFF007AFF),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'إزالة خطوط التسطير والشبكات 📓',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'التقط صورة لكشكول مسطر أو ورق رسم بياني، وسيقوم التطبيق بإزالة خطوط التسطير بالكامل مع الحفاظ التام على خط يدك وملاحظاتك.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.photo_library_rounded, size: 20),
              label: const Text(
                'اختيار صفحة كشكول من المعرض',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: _pickImage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Image Content
            if (_showOriginal || _processedBytes == null)
              Image.memory(
                _originalBytes!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              )
            else
              Image.memory(
                _processedBytes!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),

            // Loading overlay
            if (_isProcessing)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'جارٍ مسح خطوط التسطير بدقة أوفلاين...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Status Badge
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showOriginal
                          ? Icons.history_rounded
                          : Icons.auto_awesome_rounded,
                      size: 13,
                      color: _showOriginal ? Colors.amber : Colors.greenAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showOriginal ? 'الأصل (مع الخطوط)' : 'النتيجة (ورقة نقية)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hold to Compare Button
            if (_processedBytes != null && !_isProcessing)
              Positioned(
                bottom: 10,
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _showOriginal = true),
                  onTapUp: (_) => setState(() => _showOriginal = false),
                  onTapCancel: () => setState(() => _showOriginal = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'اضغط مطولاً للمقارنة مع الأصل',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsArea(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        color: isDark ? const Color(0xFF141416) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Preset Mode Selector
          const Text(
            'نوع التسطير أو شبكة الورقة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: NotebookPaperType.values.map((type) {
              final isSel = _selectedType == type;
              return ChoiceChip(
                label: Text(type.label),
                selected: isSel,
                onSelected: (val) {
                  if (val && !isSel) {
                    setState(() => _selectedType = type);
                    _processImage();
                  }
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

          const SizedBox(height: 14),

          // Sensitivity Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'حساسية التقاط الخطوط',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                '${(_sensitivity * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Color(0xFF007AFF),
                ),
              ),
            ],
          ),
          Slider(
            value: _sensitivity,
            min: 0.2,
            max: 0.9,
            activeColor: const Color(0xFF007AFF),
            onChanged: (val) => setState(() => _sensitivity = val),
            onChangeEnd: (_) => _processImage(),
          ),

          const Divider(height: 16),

          // Toggles
          SwitchListTile.adaptive(
            value: _whitenBackground,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تبييض الصفحة لتصبح نقية تماماً',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'تحويل خلفية الورقة إلى لون أبيض ناصع مثل ورق الطباعة',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            activeThumbColor: const Color(0xFF007AFF),
            onChanged: (val) {
              setState(() => _whitenBackground = val);
              _processImage();
            },
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _preserveColoredInk,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'الحفاظ على ألوان الأقلام والتظليل',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'حماية خطوط القلم الأحمر والأخضر وأقلام الهايلايتر من الحذف',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            activeThumbColor: const Color(0xFF007AFF),
            onChanged: (val) {
              setState(() => _preserveColoredInk = val);
              _processImage();
            },
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _enhanceHandwriting,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تعزيز سواد ووضوح الخط اليدوي',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'زيادة حدة الحبر ووضوح الكتابة بالقلم الرصاص أو الجاف',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            activeThumbColor: const Color(0xFF007AFF),
            onChanged: (val) {
              setState(() => _enhanceHandwriting = val);
              _processImage();
            },
          ),

          const SizedBox(height: 18),

          // Primary Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('تصدير PDF', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: _processedBytes != null && !_isProcessing ? _exportPdf : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('حفظ الصورة', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: _processedBytes != null && !_isProcessing ? _saveResult : null,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
