import 'dart:io';

import 'package:excel/excel.dart' as xl;
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

import '../../../core/utils/formatters.dart';
import '../data/native_scanner_bridge.dart';

/// Screen for Visual Table Extraction and Live Interactive Grid Editing.
/// Allows capturing a physical paper table, extracting rows/columns,
/// editing cells live, computing column sums, and exporting to real Excel (.xlsx) or PDF.
class InteractiveTableEditorScreen extends ConsumerStatefulWidget {
  const InteractiveTableEditorScreen({
    super.key,
    this.initialImagePath,
  });

  final String? initialImagePath;

  @override
  ConsumerState<InteractiveTableEditorScreen> createState() =>
      _InteractiveTableEditorScreenState();
}

class _InteractiveTableEditorScreenState
    extends ConsumerState<InteractiveTableEditorScreen> {
  final TextEditingController _tableTitleController =
      TextEditingController(text: 'جدول البيانات الذكي');

  List<String> _headers = ['البند / الوصف', 'الكمية', 'سعر الوحدة', 'الإجمالي'];
  List<List<String>> _rows = [
    ['أعمال صيانة وتجهيز', '2', '450', '900'],
    ['توريد أجهزة حاسوب', '5', '3200', '16000'],
    ['تراخيص برمجيات سنوية', '10', '180', '1800'],
    ['خدمات الدعم الفني', '1', '1200', '1200'],
  ];

  bool _isProcessing = false;
  String _statusMessage = '';
  String? _sourceImagePath;

  @override
  void initState() {
    super.initState();
    _sourceImagePath = widget.initialImagePath;
    if (_sourceImagePath != null) {
      _extractTableFromImage(_sourceImagePath!);
    }
  }

  @override
  void dispose() {
    _tableTitleController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Table Extraction Engine
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _extractTableFromImage(String imagePath) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ تحليل هيكل الجدول واستخراج البيانات...';
    });

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      if (recognizedText.blocks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على نصوص واضحة في الصورة، تم الإبقاء على الجدول الحالي.'),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      // Group text blocks by vertical Y positions to find rows
      final lines = <_DetectedLine>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final top = line.boundingBox.top;
          final left = line.boundingBox.left;
          lines.add(_DetectedLine(text: line.text.trim(), top: top, left: left));
        }
      }

      // Sort by top Y to separate into row bands
      lines.sort((a, b) => a.top.compareTo(b.top));

      final rowBands = <List<_DetectedLine>>[];
      for (final line in lines) {
        bool added = false;
        for (final band in rowBands) {
          if ((band.first.top - line.top).abs() < 24) {
            band.add(line);
            added = true;
            break;
          }
        }
        if (!added) {
          rowBands.add([line]);
        }
      }

      // Format row bands into grid
      if (rowBands.length >= 2) {
        // Sort items inside each band horizontally (left to right)
        for (final band in rowBands) {
          band.sort((a, b) => a.left.compareTo(b.left));
        }

        final extractedHeaders =
            rowBands.first.map((e) => e.text).where((s) => s.isNotEmpty).toList();

        final extractedRows = <List<String>>[];
        final colCount = extractedHeaders.length;

        for (int i = 1; i < rowBands.length; i++) {
          final band = rowBands[i];
          final rowData = <String>[];
          for (int c = 0; c < colCount; c++) {
            if (c < band.length) {
              rowData.add(band[c].text);
            } else {
              rowData.add('');
            }
          }
          if (rowData.any((cell) => cell.isNotEmpty)) {
            extractedRows.add(rowData);
          }
        }

        if (extractedHeaders.isNotEmpty && extractedRows.isNotEmpty) {
          setState(() {
            _headers = extractedHeaders;
            _rows = extractedRows;
          });
          HapticFeedback.lightImpact();
        }
      }
    } catch (e) {
      debugPrint('Error extracting table: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _pickImageAndExtract() async {
    HapticFeedback.lightImpact();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      _sourceImagePath = result.files.single.path!;
      await _extractTableFromImage(_sourceImagePath!);
    }
  }

  Future<void> _captureWithCamera() async {
    HapticFeedback.lightImpact();
    try {
      final scannedResults = await NativeScannerBridge.startScan();
      if (scannedResults.isNotEmpty) {
        _sourceImagePath = scannedResults.first.path;
        await _extractTableFromImage(_sourceImagePath!);
      }
    } catch (_) {
      await _pickImageAndExtract();
    }
  }

  void _loadTemplate(String type) {
    HapticFeedback.selectionClick();
    setState(() {
      if (type == 'grades') {
        _tableTitleController.text = 'كشف درجات الطلاب';
        _headers = ['اسم الطالب', 'الشهر الأول', 'الشهر الثاني', 'النهائي', 'المجموع'];
        _rows = [
          ['أحمد محمود', '20', '19', '58', '97'],
          ['سارة خالد', '18', '20', '60', '98'],
          ['عمر فاروق', '17', '18', '52', '87'],
          ['مريم يوسف', '20', '20', '59', '99'],
        ];
      } else if (type == 'invoice') {
        _tableTitleController.text = 'فاتورة مشتريات وتوريد';
        _headers = ['البند', 'الكمية', 'السعر', 'الإجمالي'];
        _rows = [
          ['شاشات حاسوب 27 بوصة', '4', '1850', '7400'],
          ['طابعة ليزر ملونة', '1', '4200', '4200'],
          ['أحبار وطباعة', '6', '350', '2100'],
          ['كابلات شبكة CAT6', '50', '12', '600'],
        ];
      } else {
        _tableTitleController.text = 'جدول المصاريف الشهرية';
        _headers = ['البيان', 'التاريخ', 'الفئة', 'المبلغ'];
        _rows = [
          ['إيجار المكتب', '01/10', 'ثابت', '4500'],
          ['فواتير كهرباء وإنترنت', '05/10', 'خدمات', '850'],
          ['مستلزمات مكتبية', '12/10', 'نثريات', '620'],
          ['صيانة أجهزة', '18/10', 'تشغيل', '1100'],
        ];
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Row / Column Editing
  // ───────────────────────────────────────────────────────────────────────────

  void _editCell(int rowIndex, int colIndex) {
    HapticFeedback.lightImpact();
    final isHeader = rowIndex == -1;
    final currentText = isHeader ? _headers[colIndex] : _rows[rowIndex][colIndex];
    final controller = TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isHeader ? Icons.view_column_rounded : Icons.edit_note_rounded,
              color: const Color(0xFF007AFF),
            ),
            const SizedBox(width: 8),
            Text(
              isHeader ? 'تعديل عنوان العمود' : 'تعديل الخلية',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: isHeader ? 'اسم العمود' : 'القيمة',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                if (isHeader) {
                  _headers[colIndex] = controller.text.trim();
                } else {
                  _rows[rowIndex][colIndex] = controller.text.trim();
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _addNewRow() {
    HapticFeedback.lightImpact();
    setState(() {
      _rows.add(List.generate(_headers.length, (_) => ''));
    });
  }

  void _addNewColumn() {
    HapticFeedback.lightImpact();
    final controller = TextEditingController(text: 'عمود ${_headers.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إضافة عمود جديد', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'اسم العمود',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim().isNotEmpty
                  ? controller.text.trim()
                  : 'عمود ${_headers.length + 1}';
              setState(() {
                _headers.add(name);
                for (final row in _rows) {
                  row.add('');
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _deleteRow(int index) {
    if (_rows.length <= 1) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _rows.removeAt(index);
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Auto-Sum Calculation
  // ───────────────────────────────────────────────────────────────────────────

  List<String> _calculateColumnSums() {
    return List.generate(_headers.length, (colIdx) {
      double sum = 0.0;
      bool hasNumbers = false;
      for (final row in _rows) {
        if (colIdx < row.length) {
          final val = double.tryParse(row[colIdx].replaceAll(',', '').trim());
          if (val != null) {
            sum += val;
            hasNumbers = true;
          }
        }
      }
      if (hasNumbers) {
        return sum == sum.roundToDouble()
            ? sum.toInt().toString()
            : sum.toStringAsFixed(2);
      }
      return colIdx == 0 ? 'المجموع ∑' : '-';
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Export Engines (Excel .xlsx & PDF)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ إنشاء ملف Excel وتنسيق الجداول...';
    });

    try {
      final excel = xl.Excel.createExcel();
      final sheetName = excel.sheets.keys.first;
      final sheet = excel[sheetName];

      // Title Banner
      final titleCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      titleCell.value = xl.TextCellValue(_tableTitleController.text.trim());
      titleCell.cellStyle = xl.CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: xl.ExcelColor.fromHexString('#107C41'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );

      // Headers
      for (int c = 0; c < _headers.length; c++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2));
        cell.value = xl.TextCellValue(_headers[c]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
          backgroundColorHex: xl.ExcelColor.fromHexString('#2B579A'),
          horizontalAlign: xl.HorizontalAlign.Center,
        );
      }

      // Rows
      for (int r = 0; r < _rows.length; r++) {
        final row = _rows[r];
        for (int c = 0; c < _headers.length; c++) {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 3));
          final val = c < row.length ? row[c] : '';
          final numVal = double.tryParse(val.replaceAll(',', '').trim());
          if (numVal != null) {
            cell.value = xl.DoubleCellValue(numVal);
          } else {
            cell.value = xl.TextCellValue(val);
          }
        }
      }

      // Sums Row
      final sums = _calculateColumnSums();
      for (int c = 0; c < sums.length; c++) {
        final cell =
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: _rows.length + 4));
        cell.value = xl.TextCellValue(sums[c]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#E2E8F0'),
          horizontalAlign: xl.HorizontalAlign.Center,
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          '${_tableTitleController.text.trim().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File('${dir.path}/$fileName');
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        HapticFeedback.lightImpact();
        if (mounted) {
          _showExportSuccessDialog(file.path, 'Excel (.xlsx)');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تصدير Excel: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _exportPdf() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ إنشاء تقرير PDF وتنسيق الطباعة...';
    });

    try {
      final doc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      final sums = _calculateColumnSums();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blueGrey800,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          _tableTitleController.text.trim(),
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          formatDate(DateTime.now()),
                          style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      fontSize: 11,
                    ),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
                    headers: _headers,
                    data: [
                      ..._rows,
                      sums,
                    ],
                    cellAlignment: pw.Alignment.center,
                    cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      'تم الاستخراج والتوثيق بواسطة تطبيق لقطة (Laqta Scanner)',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          '${_tableTitleController.text.trim().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save());

      HapticFeedback.lightImpact();
      if (mounted) {
        _showExportSuccessDialog(file.path, 'PDF');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تصدير PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showExportSuccessDialog(String filePath, String formatName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759)),
            const SizedBox(width: 8),
            Text('تم تصدير $formatName بنجاح', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          'تم حفظ ملفك المنسق بنجاح في جهازك:\n${filePath.split(Platform.pathSeparator).last}',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(filePath)], subject: _tableTitleController.text);
            },
            child: const Text('مشاركة'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              OpenFilex.open(filePath);
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
    final sums = _calculateColumnSums();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مستخرج ومحرر الجداول التفاعلي',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'استخراج ذكي، تحرير حي، وحساب المجموع التلقائي',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_rounded),
            tooltip: 'مسح جدول بالكاميرا',
            onPressed: _captureWithCamera,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_rounded),
            tooltip: 'استيراد صورة جدول',
            onPressed: _pickImageAndExtract,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'قوالب جاهزة',
            onSelected: _loadTemplate,
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'invoice',
                child: Text('قالب فاتورة وتوريد 🧾'),
              ),
              const PopupMenuItem(
                value: 'grades',
                child: Text('قالب كشف درجات 🎓'),
              ),
              const PopupMenuItem(
                value: 'expenses',
                child: Text('قالب مصاريف شهرية 💰'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Top Settings & Title Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tableTitleController,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.table_chart_rounded, size: 20),
                            labelText: 'عنوان الجدول',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                        label: const Text('عمود', style: TextStyle(fontSize: 12)),
                        onPressed: _addNewColumn,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('صف', style: TextStyle(fontSize: 12)),
                        onPressed: _addNewRow,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),

                // Table Stats Chip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_rows.length} صفوف • ${_headers.length} أعمدة',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'انقر على أي خلية لتعديلها مباشرة ✏️',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // Scrollable Live Data Grid
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFF007AFF).withValues(alpha: 0.12),
                          ),
                          headingRowHeight: 46,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 52,
                          columnSpacing: 24,
                          columns: [
                            ...List.generate(_headers.length, (index) {
                              return DataColumn(
                                label: InkWell(
                                  onTap: () => _editCell(-1, index),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _headers[index],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit_rounded, size: 12, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const DataColumn(
                              label: Text(
                                'إجراء',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ],
                          rows: [
                            ...List.generate(_rows.length, (rIdx) {
                              final row = _rows[rIdx];
                              return DataRow(
                                color: WidgetStateProperty.resolveWith((states) {
                                  if (rIdx.isOdd) {
                                    return isDark
                                        ? Colors.white.withValues(alpha: 0.02)
                                        : Colors.grey.withValues(alpha: 0.04);
                                  }
                                  return null;
                                }),
                                cells: [
                                  ...List.generate(_headers.length, (cIdx) {
                                    final val = cIdx < row.length ? row[cIdx] : '';
                                    return DataCell(
                                      InkWell(
                                        onTap: () => _editCell(rIdx, cIdx),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            val.isEmpty ? '—' : val,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: val.isEmpty ? Colors.grey : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                      color: Colors.redAccent,
                                      tooltip: 'حذف الصف',
                                      onPressed: () => _deleteRow(rIdx),
                                    ),
                                  ),
                                ],
                              );
                            }),
                            // Summary / Auto-Sum Row
                            DataRow(
                              color: WidgetStateProperty.all(
                                const Color(0xFF10B981).withValues(alpha: 0.12),
                              ),
                              cells: [
                                ...List.generate(_headers.length, (cIdx) {
                                  return DataCell(
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        sums[cIdx],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                                const DataCell(
                                  Icon(Icons.functions_rounded, color: Color(0xFF10B981), size: 18),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Export Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626)),
                          label: const Text(
                            'تصدير PDF',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onPressed: _exportPdf,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFDC2626)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.table_view_rounded),
                          label: const Text(
                            'تصدير Excel (.xlsx)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onPressed: _exportExcel,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF107C41),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Processing Overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator.adaptive(),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
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
}

class _DetectedLine {
  _DetectedLine({required this.text, required this.top, required this.left});
  final String text;
  final double top;
  final double left;
}
