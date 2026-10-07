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

import '../data/anti_moire_whiteboard_service.dart';

/// Screen allowing the user to photograph computer monitors, laptop displays, TVs,
/// or shiny school/conference whiteboards and eliminate moiré interference and glare.
class AntiMoireWhiteboardScreen extends ConsumerStatefulWidget {
  const AntiMoireWhiteboardScreen({
    super.key,
    this.initialImagePath,
  });

  final String? initialImagePath;

  @override
  ConsumerState<AntiMoireWhiteboardScreen> createState() =>
      _AntiMoireWhiteboardScreenState();
}

class _AntiMoireWhiteboardScreenState
    extends ConsumerState<AntiMoireWhiteboardScreen> {
  final AntiMoireWhiteboardService _service =
      const AntiMoireWhiteboardService();

  Uint8List? _originalBytes;
  Uint8List? _processedBytes;

  AntiGlareFilterMode _selectedMode = AntiGlareFilterMode.screenAntiMoire;
  double _strength = 0.65;
  bool _sharpenText = true;
  bool _digitalTone = true;

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
      final config = AntiGlareConfig(
        mode: _selectedMode,
        strength: _strength,
        sharpenText: _sharpenText,
        digitalScreenshotTone: _digitalTone,
      );

      final out = await _service.applyFilter(
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
        SnackBar(content: Text('حدث خطأ أثناء تنقية الصورة: $e')),
      );
    }
  }

  Future<void> _saveResult() async {
    if (_processedBytes == null) return;
    HapticFeedback.mediumImpact();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(dir.path, 'clean_display_$ts.png');
      await File(filePath).writeAsBytes(_processedBytes!, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الصورة النقية:\n${p.basename(filePath)}'),
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
      final filePath = p.join(dir.path, 'clean_display_$ts.pdf');
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
    final tempPath = p.join(dir.path, 'clean_display_share.png');
    await File(tempPath).writeAsBytes(_processedBytes!, flush: true);

    await Share.shareXFiles(
      [XFile(tempPath)],
      text: 'صورة منقّاة من تموجات الشاشة واللمعان • تطبيق لقطة',
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
        title: const Text(
          'مزيل تموجات الشاشات والسبورة',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
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
                // Interactive Preview
                Expanded(
                  flex: 5,
                  child: _buildPreviewArea(isDark),
                ),

                // Controls
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
                color: const Color(0xFF5856D6).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.tv_rounded,
                size: 46,
                color: Color(0xFF5856D6),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'مزيل تموجات الشاشات والسبورة 🖥️',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'عند تصوير شاشة كمبيوتر أو سبورة محاضرات، تظهر خطوط التموج (Moiré) ولمعان الإضاءة. يقوم الفلتر بإزالتها فوراً لتخرج الصورة كأنها لقطة شاشة رقمية أصلية.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5856D6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: const Text(
                  'اختيار صورة شاشة أو سبورة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _pickImage();
                },
              ),
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
                        'جارٍ إزالة التموجات واللمعان أوفلاين...',
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
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showOriginal
                          ? Icons.blur_linear_rounded
                          : Icons.screenshot_monitor_rounded,
                      size: 13,
                      color: _showOriginal ? Colors.amber : Colors.cyanAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showOriginal ? 'الأصل (مع التموج)' : 'لقطة شاشة رقمية',
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
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
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

          const Text(
            'نمط التصفية ومعالجة الانعكاس',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AntiGlareFilterMode.values.map((mode) {
              final isSel = _selectedMode == mode;
              return ChoiceChip(
                label: Text(mode.label.split('(').first.trim()),
                selected: isSel,
                onSelected: (val) {
                  if (val && !isSel) {
                    setState(() => _selectedMode = mode);
                    _processImage();
                  }
                },
                selectedColor: const Color(0xFF5856D6).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? const Color(0xFF5856D6) : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Strength Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'شدة إزالة التموجات واللمعان',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                '${(_strength * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Color(0xFF5856D6),
                ),
              ),
            ],
          ),
          Slider(
            value: _strength,
            min: 0.2,
            max: 0.95,
            activeColor: const Color(0xFF5856D6),
            onChanged: (val) => setState(() => _strength = val),
            onChangeEnd: (_) => _processImage(),
          ),

          const Divider(height: 16),

          SwitchListTile.adaptive(
            value: _digitalTone,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'مظهر لقطة الشاشة الرقمية (Digital Screenshot)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'إعادة ضبط ألوان الإضاءة لتخرج الشاشة مطابقة للسكرين شوت الأصلي',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            activeThumbColor: const Color(0xFF5856D6),
            onChanged: (val) {
              setState(() => _digitalTone = val);
              _processImage();
            },
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _sharpenText,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تحسين حدة نصوص الشاشة والسبورة',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'إبراز حواف الحروف وتفاصيل العرض التقديمي بدقة عالية',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            activeThumbColor: const Color(0xFF5856D6),
            onChanged: (val) {
              setState(() => _sharpenText = val);
              _processImage();
            },
          ),

          const SizedBox(height: 18),

          // Action Buttons: Apple Balanced 50% / 50% Tactile Cards
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black12,
                          width: 0.8,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('تصدير PDF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    onPressed: _processedBytes != null && !_isProcessing
                        ? () {
                            HapticFeedback.lightImpact();
                            _exportPdf();
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5856D6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: const Text('حفظ الصورة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    onPressed: _processedBytes != null && !_isProcessing
                        ? () {
                            HapticFeedback.mediumImpact();
                            _saveResult();
                          }
                        : null,
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
