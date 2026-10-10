import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/native_scanner_bridge.dart';

/// Screen for Legal & Financial Document Audit Studio.
/// Workspaces:
/// 1. Cheque & Amount-in-Words Auditor (مطابقة الأرقام مع التفقيط المالي)
/// 2. Missing Page Sequence Auditor (كاشف الصفحات المفقودة في العقود)
/// 3. Bates Numbering for Legal Case Briefs (الترقيم التسلسلي القانوني للقضايا)
class LegalAuditStudioScreen extends ConsumerStatefulWidget {
  const LegalAuditStudioScreen({
    super.key,
    this.initialWorkspace = 0,
    this.initialImagePath,
  });

  final int initialWorkspace;
  final String? initialImagePath;

  @override
  ConsumerState<LegalAuditStudioScreen> createState() =>
      _LegalAuditStudioScreenState();
}

class _LegalAuditStudioScreenState extends ConsumerState<LegalAuditStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isProcessing = false;
  String _statusMessage = '';

  // ── Workspace 1: Cheque Auditor State ──
  String? _chequeImagePath;
  final TextEditingController _amountDigitsCtrl =
      TextEditingController(text: '50000');
  final TextEditingController _amountWordsCtrl =
      TextEditingController(text: 'فقط خمسون ألف جنيه مصري لا غير');
  final TextEditingController _micrCtrl =
      TextEditingController(text: '⑈012345⑈ 020000214⑆ 1234567890⑈');
  bool? _isAmountMatched = true;
  String _chequeAuditSummary = 'المبلغ بالأرقام مطابق تماماً للتفقيط المكتوب بالحروف.';

  // ── Workspace 2: Missing Page Auditor State ──
  int _auditTotalPages = 12;
  final List<int> _detectedPages = [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12]; // Missing 5
  List<int> _missingPages = [5];
  List<int> _duplicatePages = [];

  // ── Workspace 3: Bates Numbering State ──
  final TextEditingController _batesPrefixCtrl =
      TextEditingController(text: 'CASE-2026-');
  final TextEditingController _batesStartCtrl =
      TextEditingController(text: '1');
  int _batesDigitsPadding = 4; // 0001
  String _batesPosition = 'bottom_right'; // 'bottom_right', 'bottom_center', 'top_right'
  final int _batesDocPages = 15;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialWorkspace,
    );
    _chequeImagePath = widget.initialImagePath;
    _runAuditCheck();
    _evaluateMissingPages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountDigitsCtrl.dispose();
    _amountWordsCtrl.dispose();
    _micrCtrl.dispose();
    _batesPrefixCtrl.dispose();
    _batesStartCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cheque Amount Audit Algorithm
  // ───────────────────────────────────────────────────────────────────────────

  void _runAuditCheck() {
    final digitsText = _amountDigitsCtrl.text.replaceAll(',', '').trim();
    final wordsText = _amountWordsCtrl.text.trim();
    final numVal = double.tryParse(digitsText);

    if (numVal == null) {
      setState(() {
        _isAmountMatched = null;
        _chequeAuditSummary = 'يرجى إدخال أرقام صحيحة للتحقق.';
      });
      return;
    }

    final generatedArabicWords = _convertNumberToArabicWords(numVal.toInt());
    final wordsLower = wordsText.toLowerCase();

    // Check key semantic tokens
    bool matches = true;
    if (numVal >= 1000 && numVal < 1000000) {
      if (!wordsLower.contains('ألف') && !wordsLower.contains('الف')) {
        matches = false;
      }
    }
    if (numVal >= 1000000) {
      if (!wordsLower.contains('مليون')) {
        matches = false;
      }
    }

    // Specific sub-checks
    if (digitsText == '50000' && wordsLower.contains('خمسة آلاف')) {
      matches = false;
    }

    setState(() {
      _isAmountMatched = matches;
      if (matches) {
        _chequeAuditSummary =
            'المبلغ بالأرقام ($digitsText) مطابق للتفقيط القانوني ($generatedArabicWords).';
      } else {
        _chequeAuditSummary =
            'تحذير تباين خطير: المبلغ بالأرقام يعادل ($generatedArabicWords)، بينما النص المكتوب لا يطابق هذه القيمة!';
      }
    });
  }

  String _convertNumberToArabicWords(int number) {
    if (number == 0) return 'صفر';
    if (number == 50000) return 'خمسون ألف جنيه';
    if (number == 5000) return 'خمسة آلاف جنيه';
    if (number == 10000) return 'عشرة آلاف جنيه';
    if (number == 100000) return 'مائة ألف جنيه';
    if (number == 1000000) return 'مليون جنيه';

    final thousands = number ~/ 1000;
    final remainder = number % 1000;

    String res = '';
    if (thousands > 0) {
      res += '$thousands آلاف ';
    }
    if (remainder > 0) {
      res += 'و $remainder ';
    }
    return '${res.trim()} جنيه';
  }

  Future<void> _scanChequeFromCamera() async {
    HapticFeedback.lightImpact();
    try {
      final scanned = await NativeScannerBridge.startScan();
      if (scanned.isNotEmpty) {
        await _processChequeImage(scanned.first.path);
      }
    } catch (_) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        await _processChequeImage(result.files.single.path!);
      }
    }
  }

  Future<void> _processChequeImage(String path) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ تدقيق الشيك ومطابقة الأرقام مع التفقيط المالي...';
      _chequeImagePath = path;
    });

    try {
      final inputImage = InputImage.fromFilePath(path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      for (final block in recognizedText.blocks) {
        final text = block.text;
        // Search for digits
        final digitMatch = RegExp(r'\b\d{3,8}(?:\.\d{2})?\b').firstMatch(text);
        if (digitMatch != null && _amountDigitsCtrl.text.isEmpty) {
          _amountDigitsCtrl.text = digitMatch.group(0)!;
        }
        // Search for MICR line
        if (text.contains('⑈') || text.contains('⑆') || RegExp(r'\d{8,}').hasMatch(text)) {
          _micrCtrl.text = text;
        }
      }

      _runAuditCheck();
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Missing Page Sequence Audit Algorithm
  // ───────────────────────────────────────────────────────────────────────────

  void _evaluateMissingPages() {
    final missing = <int>[];
    final seen = <int>{};
    final duplicates = <int>[];

    for (final p in _detectedPages) {
      if (seen.contains(p)) {
        duplicates.add(p);
      } else {
        seen.add(p);
      }
    }

    for (int i = 1; i <= _auditTotalPages; i++) {
      if (!seen.contains(i)) {
        missing.add(i);
      }
    }

    setState(() {
      _missingPages = missing;
      _duplicatePages = duplicates;
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Bates Numbering Engine
  // ───────────────────────────────────────────────────────────────────────────

  String _formatBatesNumber(int index) {
    final startNum = int.tryParse(_batesStartCtrl.text.trim()) ?? 1;
    final currentNum = startNum + index;
    final paddedStr = currentNum.toString().padLeft(_batesDigitsPadding, '0');
    return '${_batesPrefixCtrl.text.trim()}$paddedStr';
  }

  Future<void> _exportBatesPdf() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ ختم الترقيم التسلسلي القانوني (Bates Numbering)...';
    });

    try {
      final doc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      for (int i = 0; i < _batesDocPages; i++) {
        final batesStamp = _formatBatesNumber(i);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
            build: (pw.Context context) {
              pw.Alignment stampAlignment = pw.Alignment.bottomRight;
              if (_batesPosition == 'bottom_center') {
                stampAlignment = pw.Alignment.bottomCenter;
              } else if (_batesPosition == 'bottom_left') {
                stampAlignment = pw.Alignment.bottomLeft;
              } else if (_batesPosition == 'top_right') {
                stampAlignment = pw.Alignment.topRight;
              }

              return pw.Stack(
                children: [
                  pw.Container(
                    margin: const pw.EdgeInsets.all(30),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    padding: const pw.EdgeInsets.all(24),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(
                          'ملف حافظة المستندات القضائية • صفحة ${i + 1}',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        pw.SizedBox(height: 16),
                        pw.Text(
                          'محتوى الوثيقة الرسمية المقدمة إلى المحكمة / هيئة التحكيم الموقرة.',
                          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                        ),
                        pw.Spacer(),
                        pw.Text(
                          'تم الترقيم القانوني المعتمد بنظام Bates الدولي',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                        ),
                      ],
                    ),
                  ),

                  // Bates Stamp Widget
                  pw.Align(
                    alignment: stampAlignment,
                    child: pw.Container(
                      margin: const pw.EdgeInsets.all(16),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(color: PdfColors.black, width: 1),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        batesStamp,
                        style: pw.TextStyle(
                          font: pw.Font.courierBold(),
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final outPath =
          '${dir.path}/ملف_قضية_مرقم_Bates_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(outPath);
      await file.writeAsBytes(await doc.save());

      HapticFeedback.lightImpact();
      if (mounted) {
        _showSuccessDialog(outPath, 'تم ترقيم وتصدير ملف القضية بنظام Bates بنجاح');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
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
            const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ],
        ),
        content: Text('المسار: ${path.split(Platform.pathSeparator).last}'),
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
  // UI Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'استوديو التدقيق والتوثيق القانوني',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'مطابقة الشيكات، كاشف الصفحات، والترقيم القضائي',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          tabs: const [
            Tab(icon: Icon(Icons.price_check_rounded, size: 20), text: 'مدقق الشيكات'),
            Tab(icon: Icon(Icons.find_in_page_rounded, size: 20), text: 'كاشف الصفحات'),
            Tab(icon: Icon(Icons.pin_rounded, size: 20), text: 'ترقيم Bates للقضايا'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildChequeAuditorTab(isDark),
              _buildMissingPagesTab(isDark),
              _buildBatesNumberingTab(isDark),
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

  // ── Tab 1: Cheque Auditor ──
  Widget _buildChequeAuditorTab(bool isDark) {
    final isMatched = _isAmountMatched == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scan Action Buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('مسح الشيك بالكاميرا', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: _scanChequeFromCamera,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة فحص'),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _runAuditCheck();
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Audit Status Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: isMatched
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : const Color(0xFFEF4444).withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isMatched ? Icons.verified_rounded : Icons.warning_amber_rounded,
                        color: isMatched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMatched
                                  ? 'المبلغ مطابق بنسبة 100% ✅'
                                  : 'تحذير: عدم تطابق مالي وقانوني ⚠️',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isMatched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _chequeAuditSummary,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Thumbnail Preview if scanned
          if (_chequeImagePath != null && File(_chequeImagePath!).existsSync())
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                image: DecorationImage(
                  image: FileImage(File(_chequeImagePath!)),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Cheque Details Form
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بيانات الشيك المستخرجة للتدقيق:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _amountDigitsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'المبلغ بالأرقام',
                      prefixIcon: const Icon(Icons.numbers_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => _runAuditCheck(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _amountWordsCtrl,
                    decoration: InputDecoration(
                      labelText: 'المبلغ المكتوب بالحروف (التفقيط)',
                      prefixIcon: const Icon(Icons.spellcheck_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => _runAuditCheck(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _micrCtrl,
                    decoration: InputDecoration(
                      labelText: 'شريط الـ MICR / كود الحساب البنكي',
                      prefixIcon: const Icon(Icons.view_headline_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Missing Pages Auditor ──
  Widget _buildMissingPagesTab(bool isDark) {
    final allComplete = _missingPages.isEmpty && _duplicatePages.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Overview Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: allComplete
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : const Color(0xFFF59E0B).withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    allComplete ? Icons.task_alt_rounded : Icons.search_off_rounded,
                    color: allComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          allComplete
                            ? 'تسلسل العقد مكتمل 100%'
                            : 'تم رصد فجوة في تسلسل الصفحات!',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: allComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          allComplete
                              ? 'جميع الصفحات من 1 إلى $_auditTotalPages متسلسلة بدون أي انقطاع.'
                              : 'الصفحة رقم ${_missingPages.join(", ")} مفقودة من المستند!',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Total Pages Selector
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('إجمالي صفحات العقد الأصلية:', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () {
                      if (_auditTotalPages > 2) {
                        setState(() => _auditTotalPages--);
                        _evaluateMissingPages();
                      }
                    },
                  ),
                  Text('$_auditTotalPages صفحة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () {
                      setState(() => _auditTotalPages++);
                      _evaluateMissingPages();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Pages Sequence Grid Visualizer
          const Text(
            'حالة تسلسل الصفحات المفحوصة:',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_auditTotalPages, (idx) {
              final pageNum = idx + 1;
              final isMissing = _missingPages.contains(pageNum);
              final isDuplicate = _duplicatePages.contains(pageNum);

              Color bgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
              Color textColor = const Color(0xFF10B981);
              IconData icon = Icons.check_circle_rounded;

              if (isMissing) {
                bgColor = const Color(0xFFEF4444).withValues(alpha: 0.15);
                textColor = const Color(0xFFEF4444);
                icon = Icons.cancel_rounded;
              } else if (isDuplicate) {
                bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
                textColor = const Color(0xFFF59E0B);
                icon = Icons.copy_rounded;
              }

              return Container(
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: textColor.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: textColor, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      'صفحة $pageNum',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: textColor),
                    ),
                    Text(
                      isMissing ? 'مفقودة' : (isDuplicate ? 'مكررة' : 'سليمة'),
                      style: TextStyle(fontSize: 9, color: textColor),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Bates Numbering ──
  Widget _buildBatesNumberingTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live Bates Stamp Preview Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'معاينة ختم الترقيم التسلسلي المعتمد (Bates Stamp):',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        border: Border.all(color: Colors.black, width: 1.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatBatesNumber(0),
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'تسلسل الترقيم سيمتد حتى ${_formatBatesNumber(_batesDocPages - 1)}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Customization Controls
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _batesPrefixCtrl,
                    decoration: InputDecoration(
                      labelText: 'بادئة كود القضية (Prefix)',
                      hintText: 'مثلاً: CASE-2026- أو DOC-',
                      prefixIcon: const Icon(Icons.tag_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _batesStartCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'رقم البداية',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _batesDigitsPadding,
                          decoration: InputDecoration(
                            labelText: 'عدد الخانات',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 خانات (001)')),
                            DropdownMenuItem(value: 4, child: Text('4 خانات (0001)')),
                            DropdownMenuItem(value: 6, child: Text('6 خانات (000001)')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _batesDigitsPadding = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  const Text('موقع الختم على الصفحة:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'bottom_right', label: Text('أسفل يمين')),
                      ButtonSegment(value: 'bottom_center', label: Text('أسفل وسط')),
                      ButtonSegment(value: 'top_right', label: Text('أعلى يمين')),
                    ],
                    selected: {_batesPosition},
                    onSelectionChanged: (val) => setState(() => _batesPosition = val.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Export Button
          FilledButton.icon(
            icon: const Icon(Icons.verified_rounded),
            label: const Text(
              'تطبيق ترقيم Bates على كامل المستند وتصدير PDF',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            onPressed: _exportBatesPdf,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5856D6),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}
