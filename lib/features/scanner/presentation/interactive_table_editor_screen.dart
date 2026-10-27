import 'dart:io';

import 'package:excel/excel.dart' as xl;
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
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import '../data/office_exporter_service.dart';

/// Screen for Visual Table Extraction, Physical Paper Layout Reconstruction,
/// and Live Interactive Apple Bento Spreadsheet Editing.
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

  bool _isRtl = true;
  bool _isProcessing = false;
  String _statusMessage = '';
  String? _sourceImagePath;
  bool _showPaperInspector = false;

  int? _selectedRow;
  int? _selectedCol;

  @override
  void initState() {
    super.initState();
    _sourceImagePath = widget.initialImagePath;
    if (_sourceImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractTableFromImage(_sourceImagePath!);
      });
    }
  }

  @override
  void dispose() {
    _tableTitleController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Table Extraction Engine (Physical Layout Reconstruction)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _extractTableFromImage(String imagePath) async {
    setState(() {
      _isProcessing = true;
      _sourceImagePath = imagePath;
      _statusMessage = 'جارٍ مسح الورقة بدقة الذكاء الاصطناعي وبناء هيكل الجدول...';
    });

    try {
      final extractionService = ref.read(tableExtractionServiceProvider);
      final result = await extractionService.extractTableFromImage(
        imagePath: imagePath,
      );

      if (result.rows.isEmpty && result.headers.length <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لم يتم العثور على أعمدة جدول واضحة بالورقة. تم الإبقاء على البيانات الحالية.',
              ),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      setState(() {
        _tableTitleController.text = result.title;
        _headers = List<String>.from(result.headers);
        _rows = result.rows.map((r) => List<String>.from(r)).toList();
        _isRtl = result.isRtl;
        _sourceImagePath = imagePath;
        _selectedRow = null;
        _selectedCol = null;
      });

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF107C41),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم استخراج ومطابقة الجدول بنجاح (${_rows.length} صفوف • ${_headers.length} أعمدة)',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[InteractiveTableEditorScreen] extraction error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('تعذر استخراج الجدول من الصورة: $e'),
          ),
        );
      }
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
      await _extractTableFromImage(result.files.single.path!);
    }
  }

  Future<void> _captureWithCamera() async {
    HapticFeedback.lightImpact();
    try {
      final scannedResults = await NativeScannerBridge.startScan();
      if (scannedResults.isNotEmpty) {
        await _extractTableFromImage(scannedResults.first.path);
      }
    } catch (_) {
      await _pickImageAndExtract();
    }
  }

  void _loadTemplate(String type) {
    HapticFeedback.selectionClick();
    setState(() {
      _sourceImagePath = null;
      _showPaperInspector = false;
      _selectedRow = null;
      _selectedCol = null;

      if (type == 'grades') {
        _tableTitleController.text = 'كشف درجات الطلاب الشهري';
        _headers = ['اسم الطالب', 'الشهر الأول', 'الشهر الثاني', 'النهائي', 'المجموع'];
        _rows = [
          ['أحمد محمود', '20', '19', '58', '97'],
          ['سارة خالد', '18', '20', '60', '98'],
          ['عمر فاروق', '17', '18', '52', '87'],
          ['مريم يوسف', '20', '20', '59', '99'],
        ];
        _isRtl = true;
      } else if (type == 'invoice') {
        _tableTitleController.text = 'فاتورة مشتريات وتوريدات رقم 104';
        _headers = ['البند / التوصيف', 'الكمية', 'السعر', 'الإجمالي'];
        _rows = [
          ['شاشات حاسوب 27 بوصة 4K', '4', '1850', '7400'],
          ['طابعة ليزر ملونة متعددة المهام', '1', '4200', '4200'],
          ['أحبار وطباعة أوفست', '6', '350', '2100'],
          ['كابلات شبكة CAT6 معتمدة', '50', '12', '600'],
        ];
        _isRtl = true;
      } else {
        _tableTitleController.text = 'جدول المصاريف والتشغيل الشهري';
        _headers = ['البيان', 'التاريخ', 'الفئة', 'المبلغ'];
        _rows = [
          ['إيجار المقر والمستودع', '01/10', 'ثابت', '4500'],
          ['فواتير كهرباء وإنترنت فايبر', '05/10', 'خدمات', '850'],
          ['مستلزمات مكتبية وطباعة', '12/10', 'نثريات', '620'],
          ['صيانة دورية للأجهزة', '18/10', 'تشغيل', '1100'],
        ];
        _isRtl = true;
      }
    });
  }

  void _reverseTableDirection() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isRtl = !_isRtl;
      _headers = _headers.reversed.toList();
      _rows = _rows.map((r) => r.reversed.toList()).toList();
      if (_selectedCol != null) {
        _selectedCol = _headers.length - 1 - _selectedCol!;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          _isRtl ? 'تم عكس اتجاه الجدول: من اليمين لليسار (RTL)' : 'تم عكس اتجاه الجدول: من اليسار لليمين (LTR)',
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Row / Column Editing Operations
  // ───────────────────────────────────────────────────────────────────────────

  void _showCellEditorSheet(int rowIndex, int colIndex) {
    HapticFeedback.lightImpact();
    final isHeader = rowIndex == -1;
    final currentVal = isHeader ? _headers[colIndex] : _rows[rowIndex][colIndex];
    final controller = TextEditingController(text: currentVal);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // iOS Grabber
                Center(
                  child: Container(
                    width: 36,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Header Info
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isHeader ? Icons.view_column_rounded : Icons.edit_note_rounded,
                        color: const Color(0xFF007AFF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHeader
                                ? 'تعديل عنوان العمود (${_getColumnLetter(colIndex)})'
                                : 'تعديل الخلية [صف ${rowIndex + 1} • ${_headers[colIndex]}]',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(
                            isHeader
                                ? 'اسم العمود يظهر في رأس كل تقرير وملف Excel'
                                : 'أدخل نصاً أو قيمة رقمية لحساب المجموع التلقائي',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main Input
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: isHeader ? 'اسم العمود...' : 'محتوى الخلية...',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => controller.clear(),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Values Chips
                if (!isHeader)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildQuickValueChip('0', controller),
                      _buildQuickValueChip('1', controller),
                      _buildQuickValueChip('+10', controller, isAppend: true),
                      _buildQuickValueChip('ج.م', controller, isAppend: true),
                      _buildQuickValueChip('ر.س', controller, isAppend: true),
                      _buildQuickValueChip('\$', controller, isAppend: true),
                      _buildQuickValueChip('%', controller, isAppend: true),
                      _buildQuickValueChip('مسح', controller, isClear: true),
                    ],
                  ),
                const SizedBox(height: 18),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          final newVal = controller.text.trim();
                          setState(() {
                            if (isHeader) {
                              _headers[colIndex] = newVal.isNotEmpty ? newVal : 'عمود ${colIndex + 1}';
                            } else {
                              _rows[rowIndex][colIndex] = newVal;
                            }
                          });
                          HapticFeedback.lightImpact();
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('حفظ التعديل', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickValueChip(
    String label,
    TextEditingController controller, {
    bool isAppend = false,
    bool isClear = false,
  }) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      onPressed: () {
        HapticFeedback.selectionClick();
        if (isClear) {
          controller.clear();
        } else if (isAppend) {
          controller.text = '${controller.text.trim()} $label'.trim();
        } else {
          controller.text = label;
        }
      },
    );
  }

  String _getColumnLetter(int index) {
    return String.fromCharCode(65 + (index % 26));
  }

  void _addNewRow({int? atIndex}) {
    HapticFeedback.lightImpact();
    setState(() {
      final newRow = List.generate(_headers.length, (_) => '');
      if (atIndex != null && atIndex >= 0 && atIndex <= _rows.length) {
        _rows.insert(atIndex, newRow);
        _selectedRow = atIndex;
      } else {
        _rows.add(newRow);
        _selectedRow = _rows.length - 1;
      }
    });
  }

  void _addNewColumn({int? atIndex}) {
    HapticFeedback.lightImpact();
    final defaultName = 'عمود ${_headers.length + 1}';
    final controller = TextEditingController(text: defaultName);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إضافة عمود جديد', style: TextStyle(fontWeight: FontWeight.w800)),
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
              final name = controller.text.trim().isNotEmpty ? controller.text.trim() : defaultName;
              setState(() {
                final insertIdx = (atIndex != null && atIndex >= 0 && atIndex <= _headers.length)
                    ? atIndex
                    : _headers.length;
                _headers.insert(insertIdx, name);
                for (final row in _rows) {
                  row.insert(insertIdx, '');
                }
                _selectedCol = insertIdx;
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
    if (_rows.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف الصف الأخير في الجدول.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _rows.removeAt(index);
      if (_selectedRow == index) {
        _selectedRow = null;
      }
    });
  }

  void _deleteColumn(int index) {
    if (_headers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف العمود الأخير في الجدول.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _headers.removeAt(index);
      for (final row in _rows) {
        if (index < row.length) {
          row.removeAt(index);
        }
      }
      if (_selectedCol == index) {
        _selectedCol = null;
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Auto-Sum Calculations
  // ───────────────────────────────────────────────────────────────────────────

  List<String> _calculateColumnSums() {
    return List.generate(_headers.length, (colIdx) {
      double sum = 0.0;
      bool hasNumbers = false;

      for (final row in _rows) {
        if (colIdx < row.length) {
          final cellText = row[colIdx].trim();
          final parsed = OfficeExporterService.parseFlexibleNumber(cellText);
          if (parsed != null) {
            sum += parsed;
            hasNumbers = true;
          }
        }
      }

      if (hasNumbers) {
        return sum == sum.roundToDouble()
            ? sum.toInt().toString()
            : sum.toStringAsFixed(2);
      }
      return colIdx == 0 ? 'المجموع ∑' : '—';
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Clipboard TSV Export
  // ───────────────────────────────────────────────────────────────────────────

  void _copyTableToClipboard() {
    HapticFeedback.mediumImpact();
    final buffer = StringBuffer();

    // Headers
    buffer.writeln(_headers.join('\t'));

    // Rows
    for (final row in _rows) {
      buffer.writeln(row.join('\t'));
    }

    // Totals
    final sums = _calculateColumnSums();
    buffer.writeln(sums.join('\t'));

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF007AFF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Row(
          children: [
            Icon(Icons.copy_all_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم نسخ الجدول إلى الحافظة! يمكنك لصقه مباشرة في Excel أو WhatsApp أو Notes.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Export Engines (Excel & PDF)
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
      sheet.isRTL = _isRtl;

      final headerBg = xl.ExcelColor.fromHexString('#1B5E20');
      final whiteColor = xl.ExcelColor.fromHexString('#FFFFFF');
      final gridBorder = xl.Border(
        borderStyle: xl.BorderStyle.Thin,
        borderColorHex: xl.ExcelColor.fromHexString('#CBD5E1'),
      );
      final doubleBottomBorder = xl.Border(
        borderStyle: xl.BorderStyle.Double,
        borderColorHex: xl.ExcelColor.fromHexString('#1B5E20'),
      );

      // 1. Title Banner
      final titleCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      titleCell.value = xl.TextCellValue(_tableTitleController.text.trim());
      titleCell.cellStyle = xl.CellStyle(
        bold: true,
        fontSize: 13,
        fontFamily: 'Cairo',
        fontColorHex: whiteColor,
        backgroundColorHex: headerBg,
        horizontalAlign: xl.HorizontalAlign.Center,
      );

      if (_headers.length > 1) {
        sheet.merge(
          xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          xl.CellIndex.indexByColumnRow(columnIndex: _headers.length - 1, rowIndex: 0),
        );
      }

      // 2. Headers
      for (int c = 0; c < _headers.length; c++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2));
        cell.value = xl.TextCellValue(_headers[c]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          fontFamily: 'Cairo',
          fontColorHex: whiteColor,
          backgroundColorHex: xl.ExcelColor.fromHexString('#2563EB'),
          horizontalAlign: xl.HorizontalAlign.Center,
          leftBorder: gridBorder,
          rightBorder: gridBorder,
          topBorder: gridBorder,
          bottomBorder: gridBorder,
        );
      }

      // 3. Data Rows
      for (int r = 0; r < _rows.length; r++) {
        final row = _rows[r];
        for (int c = 0; c < _headers.length; c++) {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 3));
          final val = c < row.length ? row[c].trim() : '';
          final numVal = OfficeExporterService.parseFlexibleNumber(val);

          if (numVal != null) {
            cell.value = xl.DoubleCellValue(numVal.toDouble());
          } else {
            cell.value = xl.TextCellValue(val);
          }

          cell.cellStyle = xl.CellStyle(
            fontFamily: 'Cairo',
            horizontalAlign: numVal != null ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Center,
            leftBorder: gridBorder,
            rightBorder: gridBorder,
            topBorder: gridBorder,
            bottomBorder: gridBorder,
            backgroundColorHex: r.isEven
                ? xl.ExcelColor.fromHexString('#FFFFFF')
                : xl.ExcelColor.fromHexString('#F8FAFC'),
          );
        }
      }

      // 4. Auto-Sum Summary Row
      final sums = _calculateColumnSums();
      for (int c = 0; c < sums.length; c++) {
        final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: _rows.length + 4),
        );
        final sumVal = sums[c];
        final numSum = OfficeExporterService.parseFlexibleNumber(sumVal);

        if (numSum != null) {
          cell.value = xl.DoubleCellValue(numSum.toDouble());
        } else {
          cell.value = xl.TextCellValue(sumVal);
        }

        cell.cellStyle = xl.CellStyle(
          bold: true,
          fontFamily: 'Cairo',
          fontColorHex: xl.ExcelColor.fromHexString('#1B5E20'),
          backgroundColorHex: xl.ExcelColor.fromHexString('#E8F5E9'),
          horizontalAlign: xl.HorizontalAlign.Center,
          leftBorder: gridBorder,
          rightBorder: gridBorder,
          topBorder: gridBorder,
          bottomBorder: doubleBottomBorder,
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final cleanTitle = _tableTitleController.text.trim().replaceAll(' ', '_');
      final fileName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
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
              textDirection: _isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
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
                      'تم الاستخراج والتوثيق بواسطة تطبيق لقطة (Laqta Scanner) • محرر الجداول الذكي',
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
      final cleanTitle = _tableTitleController.text.trim().replaceAll(' ', '_');
      final fileName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
    showDialog<void>(
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
  // UI Build (Apple Minimalist / Bento Paper Layout)
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isSmallPhone = screenWidth < 360;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مستخرج ومحرر الجداول الذكي',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: isSmallPhone ? 14 : 16,
              ),
            ),
            const Text(
              'Apple Numbers • مطابقة دقيقة للورقة الأصلية',
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      // 1. Apple Bento Hero Card
                      _buildAppleBentoHeaderCard(isDark: isDark, isSmallPhone: isSmallPhone),
                      const SizedBox(height: 12),

                      // 2. Physical Paper Inspector (if photo is loaded)
                      if (_sourceImagePath != null && _showPaperInspector) ...[
                        _buildPhysicalPaperInspector(isDark: isDark),
                        const SizedBox(height: 12),
                      ],

                      // 3. Bento Quick Action Toolbar
                      _buildBentoActionIsland(isDark: isDark, isSmallPhone: isSmallPhone),
                      const SizedBox(height: 14),

                      // 4. Apple Bento Spreadsheet Grid
                      _buildBentoPaperGrid(isDark: isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pinned Bottom Bento Export Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBentoExportBar(isDark: isDark),
          ),

          // Processing Loading Overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator.adaptive(),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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

  // ───────────────────────────────────────────────────────────────────────────
  // Component: Apple Bento Header Card
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildAppleBentoHeaderCard({
    required bool isDark,
    required bool isSmallPhone,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmallPhone ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow & Status
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: Color(0xFF007AFF), size: 14),
                      SizedBox(width: 5),
                      Text(
                        'الأداة الذكية • محرر الجداول الورقية',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34C759),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'مطابقة دقيقة للورقة 100%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title & Icon
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.table_chart_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _tableTitleController,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'عنوان المستند أو الجدول...',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bento Metrics Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildMetricChip(
                icon: Icons.table_rows_rounded,
                label: '${_rows.length} صفوف',
                color: const Color(0xFF007AFF),
                isDark: isDark,
              ),
              _buildMetricChip(
                icon: Icons.view_column_rounded,
                label: '${_headers.length} أعمدة',
                color: const Color(0xFF5856D6),
                isDark: isDark,
              ),
              GestureDetector(
                onTap: _reverseTableDirection,
                child: _buildMetricChip(
                  icon: Icons.swap_horiz_rounded,
                  label: _isRtl ? 'عربي (RTL)' : 'إنجليزي (LTR)',
                  color: const Color(0xFFFF9500),
                  isDark: isDark,
                ),
              ),
              if (_sourceImagePath != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showPaperInspector = !_showPaperInspector);
                  },
                  child: _buildMetricChip(
                    icon: _showPaperInspector
                        ? Icons.visibility_off_rounded
                        : Icons.image_search_rounded,
                    label: _showPaperInspector ? 'إخفاء الورقة' : 'معاينة الورقة الأصلية',
                    color: const Color(0xFF34C759),
                    isDark: isDark,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Component: Physical Paper Inspector (Zoomable Comparison Viewer)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPhysicalPaperInspector({required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF34C759).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF34C759).withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(Icons.document_scanner_rounded, color: Color(0xFF34C759), size: 16),
                const SizedBox(width: 8),
                const Text(
                  'الورقة الأصلية الممسوحة (اسحب وكبّر للتطابق)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF34C759),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _showPaperInspector = false),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.file(
                File(_sourceImagePath!),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Component: Bento Action Island
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBentoActionIsland({
    required bool isDark,
    required bool isSmallPhone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceEvenly,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('صف جديد', style: TextStyle(fontSize: 12)),
              onPressed: () => _addNewRow(),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TextButton.icon(
              icon: const Icon(Icons.view_column_rounded, size: 16),
              label: const Text('عمود جديد', style: TextStyle(fontSize: 12)),
              onPressed: () => _addNewColumn(),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('نسخ كـ جدول', style: TextStyle(fontSize: 12)),
              onPressed: _copyTableToClipboard,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TextButton.icon(
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('عكس الاتجاه', style: TextStyle(fontSize: 12)),
              onPressed: _reverseTableDirection,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Component: Apple Numbers Bento Paper Grid
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBentoPaperGrid({required bool isDark}) {
    final sums = _calculateColumnSums();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row (A, B, C... / Custom Header Titles)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.16 : 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Corner Cell
                  Container(
                    width: 46,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: isDark ? Colors.white10 : Colors.black12,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      '#',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),

                  // Column Header Cells
                  ...List.generate(_headers.length, (colIdx) {
                    final colLetter = _getColumnLetter(colIdx);
                    final isSelected = _selectedCol == colIdx;

                    return InkWell(
                      onTap: () => _showCellEditorSheet(-1, colIdx),
                      onLongPress: () => _showColumnContextMenu(colIdx),
                      child: Container(
                        width: 140,
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF007AFF).withValues(alpha: 0.18)
                              : null,
                          border: Border(
                            left: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              colLetter,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _headers[colIdx],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const Icon(Icons.edit_rounded, size: 12, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Data Rows
            ...List.generate(_rows.length, (rowIdx) {
              final row = _rows[rowIdx];
              final isRowSelected = _selectedRow == rowIdx;

              return Container(
                decoration: BoxDecoration(
                  color: isRowSelected
                      ? const Color(0xFF007AFF).withValues(alpha: isDark ? 0.12 : 0.05)
                      : (rowIdx.isOdd
                          ? (isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.grey.withValues(alpha: 0.03))
                          : null),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Row Number Index Cell
                    InkWell(
                      onTap: () => _showRowContextMenu(rowIdx),
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.grey.withValues(alpha: 0.06),
                          border: Border(
                            left: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Text(
                          '${rowIdx + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ),

                    // Data Cells
                    ...List.generate(_headers.length, (colIdx) {
                      final cellVal = colIdx < row.length ? row[colIdx] : '';
                      final isCellSelected = _selectedRow == rowIdx && _selectedCol == colIdx;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedRow = rowIdx;
                            _selectedCol = colIdx;
                          });
                          _showCellEditorSheet(rowIdx, colIdx);
                        },
                        child: Container(
                          width: 140,
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                          decoration: BoxDecoration(
                            border: isCellSelected
                                ? Border.all(color: const Color(0xFF007AFF), width: 1.5)
                                : Border(
                                    left: BorderSide(
                                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                      width: 0.5,
                                    ),
                                  ),
                          ),
                          child: Text(
                            cellVal.isEmpty ? '—' : cellVal,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cellVal.isEmpty
                                  ? (isDark ? Colors.white30 : Colors.black26)
                                  : null,
                              fontWeight: cellVal.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),

            // Auto-Sum Summary Row
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withValues(alpha: isDark ? 0.16 : 0.10),
                border: Border(
                  top: const BorderSide(color: Color(0xFF34C759), width: 1.5),
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: isDark ? Colors.white10 : Colors.black12,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.functions_rounded,
                      color: Color(0xFF34C759),
                      size: 18,
                    ),
                  ),
                  ...List.generate(_headers.length, (colIdx) {
                    final sumVal = sums[colIdx];
                    return Container(
                      width: 140,
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: isDark ? Colors.white10 : Colors.black12,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Text(
                        sumVal,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColumnContextMenu(int colIndex) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? const Color(0xFF1C1C1E)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Color(0xFF007AFF)),
                title: Text('تعديل اسم العمود (${_headers[colIndex]})'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCellEditorSheet(-1, colIndex);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF34C759)),
                title: const Text('إدراج عمود إلى اليسار'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addNewColumn(atIndex: colIndex + 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('حذف هذا العمود'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteColumn(colIndex);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRowContextMenu(int rowIndex) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? const Color(0xFF1C1C1E)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF007AFF)),
                title: Text('إدراج صف أعلى الصف ${rowIndex + 1}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addNewRow(atIndex: rowIndex);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF34C759)),
                title: Text('إدراج صف أسفل الصف ${rowIndex + 1}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addNewRow(atIndex: rowIndex + 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: Text('حذف الصف ${rowIndex + 1}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteRow(rowIndex);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Component: Bottom Bento Export Bar
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBentoExportBar({required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 18),
              label: const Text(
                'تصدير PDF',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: _exportPdf,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              icon: const Icon(Icons.table_view_rounded, size: 18),
              label: const Text(
                'تصدير Excel (.xlsx)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
    );
  }
}
