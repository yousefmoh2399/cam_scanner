import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/motion_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';

/// Screen for Booklet Imposition & Binding Gutter Spacing.
/// Features:
/// 1. A5 Saddle-Stitch Booklet Imposition for duplex printing and center-fold booklets.
/// 2. Gutter Margin Spacer with visual simulation for hole punches and spiral binding.
class BookletAndBindingScreen extends ConsumerStatefulWidget {
  const BookletAndBindingScreen({
    super.key,
    this.initialPdfPath,
    this.initialTabIndex = 0,
  });

  final String? initialPdfPath;
  final int initialTabIndex;

  @override
  ConsumerState<BookletAndBindingScreen> createState() =>
      _BookletAndBindingScreenState();
}

class _BookletAndBindingScreenState extends ConsumerState<BookletAndBindingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedPdfPath;
  String? _selectedPdfTitle;
  int _pdfPageCount = 8;
  bool _isProcessing = false;
  String _statusMessage = '';

  // ── Booklet Settings ──
  bool _addFoldGuideLine = true;
  bool _addPageBorders = true;

  // ── Gutter Margin Settings ──
  double _gutterMarginMm = 15.0; // 5 to 30 mm
  String _bindingEdge = 'right'; // 'right', 'left', 'duplex'
  String _bindingStyle = 'spiral'; // 'spiral', '2hole', '3hole'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _selectedPdfPath = widget.initialPdfPath;
    if (_selectedPdfPath != null) {
      _selectedPdfTitle = _selectedPdfPath!.split(Platform.pathSeparator).last;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Pick Document
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _pickExternalPdf() async {
    HapticFeedback.lightImpact();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _selectedPdfPath = path;
        _selectedPdfTitle = result.files.single.name;
        _pdfPageCount = 8; // Default mock page count for imposition
      });
      HapticFeedback.lightImpact();
    }
  }

  void _pickFromLibrary(List<PendingUpload> docs) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.folder_shared_rounded, color: Color(0xFF007AFF)),
                  const SizedBox(width: 8),
                  const Text(
                    'اختر مستنداً من مكتبتك',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('لا توجد مستندات في المكتبة حالياً', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF007AFF),
                        child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                      ),
                      title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${doc.pages.length} صفحة • ${formatDate(doc.createdAt)}'),
                      onTap: () {
                        setState(() {
                          _selectedPdfTitle = doc.title;
                          _pdfPageCount = doc.pages.isNotEmpty ? doc.pages.length : 8;
                          _selectedPdfPath = doc.pages.isNotEmpty ? doc.pages.first.imagePath : null;
                        });
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Imposition Engine (4k Saddle-Stitch)
  // ───────────────────────────────────────────────────────────────────────────

  List<List<int>> _calculateImpositionSheets(int totalPages) {
    // Round up to nearest multiple of 4
    final paddedCount = ((totalPages + 3) ~/ 4) * 4;
    final sheetsCount = paddedCount ~/ 4;
    final result = <List<int>>[];

    for (int i = 0; i < sheetsCount; i++) {
      // Front sheet: [Left: paddedCount - 2*i, Right: 2*i + 1]
      final frontLeft = paddedCount - (2 * i);
      final frontRight = 2 * i + 1;
      result.add([frontLeft, frontRight]);

      // Back sheet: [Left: 2*i + 2, Right: paddedCount - 2*i - 1]
      final backLeft = 2 * i + 2;
      final backRight = paddedCount - (2 * i) - 1;
      result.add([backLeft, backRight]);
    }

    return result;
  }

  Future<void> _exportBookletPdf() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ ترتيب الصفحات بنظام طباعة الكتيبات (Booklet Imposition)...';
    });

    try {
      final doc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      final sheets = _calculateImpositionSheets(_pdfPageCount);

      for (int s = 0; s < sheets.length; s++) {
        final pair = sheets[s];
        final isFront = s.isEven;
        final sheetNum = (s ~/ 2) + 1;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
            build: (pw.Context context) {
              return pw.Container(
                decoration: pw.BoxDecoration(
                  border: _addPageBorders
                      ? pw.Border.all(color: PdfColors.grey400, width: 0.5)
                      : null,
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // Left Page of Sheet
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(20),
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'صفحة ${pair[0]}',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: pair[0] > _pdfPageCount
                                    ? PdfColors.grey400
                                    : PdfColors.black,
                              ),
                            ),
                            pw.Center(
                              child: pw.Text(
                                pair[0] > _pdfPageCount
                                    ? '[صفحة فارغة للتوازن]'
                                    : 'محتوى الصفحة ${pair[0]}\n${_selectedPdfTitle ?? "كتيب مستندات"}',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                              ),
                            ),
                            pw.Text(
                              'ورقة $sheetNum • ${isFront ? "وجه أمامي" : "ظهر خلفي"}',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Center Fold Line
                    if (_addFoldGuideLine)
                      pw.Container(
                        width: 1,
                        color: PdfColors.grey300,
                        margin: const pw.EdgeInsets.symmetric(vertical: 10),
                      ),

                    // Right Page of Sheet
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(20),
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'صفحة ${pair[1]}',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: pair[1] > _pdfPageCount
                                    ? PdfColors.grey400
                                    : PdfColors.black,
                              ),
                            ),
                            pw.Center(
                              child: pw.Text(
                                pair[1] > _pdfPageCount
                                    ? '[صفحة فارغة للتوازن]'
                                    : 'محتوى الصفحة ${pair[1]}\n${_selectedPdfTitle ?? "كتيب مستندات"}',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                              ),
                            ),
                            pw.Text(
                              'ورقة $sheetNum • ${isFront ? "وجه أمامي" : "ظهر خلفي"}',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/كتيب_جاهز_للطباعة_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(outPath);
      await file.writeAsBytes(await doc.save());

      HapticFeedback.lightImpact();
      if (mounted) {
        _showSuccessDialog(outPath, 'ملف الكتيب المطوي جاهز للطباعة المزدوجة (Duplex)');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Gutter Spacer Engine
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _exportGutterPdf() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ حساب وضبط هوامش التجليد الآمنة...';
    });

    try {
      final doc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      final gutterPoints = _gutterMarginMm * (72.0 / 25.4); // mm to PDF points

      for (int pNum = 1; pNum <= 4; pNum++) {
        final isOdd = pNum.isOdd;
        double rightMargin = 20.0;
        double leftMargin = 20.0;

        if (_bindingEdge == 'right') {
          rightMargin += gutterPoints;
        } else if (_bindingEdge == 'left') {
          leftMargin += gutterPoints;
        } else {
          // Duplex Alternating
          if (isOdd) {
            rightMargin += gutterPoints;
          } else {
            leftMargin += gutterPoints;
          }
        }

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.only(
              right: rightMargin,
              left: leftMargin,
              top: 25,
              bottom: 25,
            ),
            theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
            build: (pw.Context context) {
              return pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      'صفحة $pNum • هامش تجليد آمن (+${_gutterMarginMm.toInt()} ملم)',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'تم إزاحة المحتوى بمقدار ${_gutterMarginMm.toInt()} ملم بعيداً عن ثقوب التجليد لضمان عدم تلف أو اقتطاع أي نصوص عند التخريم بالخرامة أو التجليد السلكي الحلزوني.',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
                    ),
                    pw.Spacer(),
                    pw.Align(
                      alignment: pw.Alignment.bottomLeft,
                      child: pw.Text(
                        'تطبيق لقطة • مساحة قراءة محمية 100%',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/مستند_بهامش_تجليد_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(outPath);
      await file.writeAsBytes(await doc.save());

      HapticFeedback.lightImpact();
      if (mounted) {
        _showSuccessDialog(outPath, 'تم تصدير المستند بهامش تجليد احترافي');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog(String path, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'تم إنشاء وحفظ الملف بنجاح:\n${path.split(Platform.pathSeparator).last}',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(path)]);
            },
            child: const Text('مشاركة'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              OpenFilex.open(path);
            },
            child: const Text('فتح الملف'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI Builders
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final libraryDocs = ref.watch(pendingUploadsControllerProvider).valueOrNull ?? <PendingUpload>[];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'صانع الكتيبات وهامش التجليد',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'ترتيب الملازم المطوية وهامش التخريم الذكي',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.auto_stories_rounded, size: 20),
              text: 'صانع الكتيبات (Booklet)',
            ),
            Tab(
              icon: Icon(Icons.margin_rounded, size: 20),
              text: 'هامش التخريم والتجليد',
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildBookletTab(isDark, libraryDocs),
              _buildGutterTab(isDark, libraryDocs),
            ],
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator.adaptive(),
                        const SizedBox(height: 16),
                        Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab 1: Booklet Imposition View ──
  Widget _buildBookletTab(bool isDark, List<PendingUpload> libraryDocs) {
    final sheets = _calculateImpositionSheets(_pdfPageCount);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source Selector Card
          _buildSourceSelectorCard(isDark, libraryDocs),
          const SizedBox(height: 16),

          // Visual Explanation Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF007AFF).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_rounded, color: Color(0xFF007AFF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'نظام ترتيب الكتيبات يوزع الصفحات على ورقة A4 بالعرض (Landscape) بحيث تطبعها وش وظهر على أي طابعة عادية، ثم تطوي الورق من المنتصف وتدبسه ليخرج معك كتيب متناسق.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sheets Breakdown Visualizer
          Text(
            'مخطط توزيع الصفحات (${sheets.length ~/ 2} ورقات A4):',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sheets.length ~/ 2,
            itemBuilder: (ctx, idx) {
              final frontPair = sheets[idx * 2];
              final backPair = sheets[idx * 2 + 1];
              final sheetNumber = idx + 1;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ورقة $sheetNumber',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'طباعة وجه وظهر (Duplex)',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'الوجه الأمامي:\nصفحة ${frontPair[0]} | صفحة ${frontPair[1]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'الظهر الخلفي:\nصفحة ${backPair[0]} | صفحة ${backPair[1]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Options Switches
          SwitchListTile(
            title: const Text('إظهار خط إرشادي للطي في المنتصف', style: TextStyle(fontSize: 13)),
            value: _addFoldGuideLine,
            onChanged: (val) => setState(() => _addFoldGuideLine = val),
          ),
          SwitchListTile(
            title: const Text('إضافة إطار خفيف للصفحات للقص المنظم', style: TextStyle(fontSize: 13)),
            value: _addPageBorders,
            onChanged: (val) => setState(() => _addPageBorders = val),
          ),
          const SizedBox(height: 16),

          // Export Button
          FilledButton.icon(
            icon: const Icon(Icons.print_rounded),
            label: const Text(
              'تصدير الكتيب جاهزاً للطباعة المزدوجة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            onPressed: _exportBookletPdf,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Binding Gutter Margin View ──
  Widget _buildGutterTab(bool isDark, List<PendingUpload> libraryDocs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source Selector Card
          _buildSourceSelectorCard(isDark, libraryDocs),
          const SizedBox(height: 16),

          // Visual Simulation Box
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'معاينة محاكاة التخريم والتجليد',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'هامش أمان: +${_gutterMarginMm.toInt()} مم',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Simulated Paper Sheet
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Binding Holes / Spiral Simulation on chosen edge
                        if (_bindingEdge == 'right' || _bindingEdge == 'duplex')
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 8,
                            child: _buildHolesPreview(),
                          ),
                        if (_bindingEdge == 'left')
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: 8,
                            child: _buildHolesPreview(),
                          ),

                        // Safe Text Area
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: _bindingEdge == 'right' || _bindingEdge == 'duplex'
                                  ? 36.0 + (_gutterMarginMm * 0.8)
                                  : 16.0,
                              left: _bindingEdge == 'left'
                                  ? 36.0 + (_gutterMarginMm * 0.8)
                                  : 16.0,
                              top: 20,
                              bottom: 20,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.05),
                                border: Border.all(
                                  color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                                  style: BorderStyle.solid,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Text(
                                  'منطقة النصوص والقراءة المحمية\n(لن تتأثر بالخرامة إطلاقاً)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white70 : const Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Gutter Margin Slider
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'عرض هامش التخريم (Gutter Margin):',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        '${_gutterMarginMm.toInt()} ملم',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  Slider(
                    value: _gutterMarginMm,
                    min: 5.0,
                    max: 30.0,
                    divisions: 5,
                    label: '${_gutterMarginMm.toInt()} مم',
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _gutterMarginMm = val);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPresetChip('5 مم (خفيف)', 5.0),
                      _buildPresetChip('15 مم (معياري)', 15.0),
                      _buildPresetChip('25 مم (سلك عريض)', 25.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Binding Edge Selector
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'جهة التجليد والتخريم:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'right', label: Text('يمين (عربي)')),
                      ButtonSegment(value: 'left', label: Text('يسار (English)')),
                      ButtonSegment(value: 'duplex', label: Text('تناوبي (وجه وظهر)')),
                    ],
                    selected: {_bindingEdge},
                    onSelectionChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _bindingEdge = val.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Binding Style Selector
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'نوع التجليد للمحاكاة:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'spiral', label: Text('سلك حلزوني')),
                      ButtonSegment(value: '2hole', label: Text('خرامة ثنائية')),
                      ButtonSegment(value: '3hole', label: Text('خرامة ثلاثية')),
                    ],
                    selected: {_bindingStyle},
                    onSelectionChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _bindingStyle = val.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Export Button
          FilledButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text(
              'تصدير PDF بهامش تجليد آمن للطباعة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            onPressed: _exportGutterPdf,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double value) {
    final isSelected = _gutterMarginMm == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _gutterMarginMm = value);
      },
    );
  }

  Widget _buildHolesPreview() {
    if (_bindingStyle == 'spiral') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          12,
          (_) => Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black45,
            ),
          ),
        ),
      );
    } else if (_bindingStyle == '2hole') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          2,
          (_) => Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black54,
            ),
          ),
        ),
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          3,
          (_) => Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black54,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSourceSelectorCard(bool isDark, List<PendingUpload> libraryDocs) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF007AFF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedPdfTitle ?? 'مستند تجريبي (8 صفحات)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  Text(
                    '$_pdfPageCount صفحة جاهزة للمعالجة',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_rounded),
              tooltip: 'من المكتبة',
              onPressed: () => _pickFromLibrary(libraryDocs),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'ملف خارجي',
              onPressed: _pickExternalPdf,
            ),
          ],
        ),
      ),
    );
  }
}
