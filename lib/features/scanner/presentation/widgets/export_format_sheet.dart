import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/pending_upload.dart';
import '../../../../shared/providers/providers.dart';
import '../../data/ocr_service.dart';
import '../../data/office_exporter_service.dart';
import '../../data/pdf_builder_service.dart';

class SaveAndExportChoice {
  const SaveAndExportChoice({
    required this.fileName,
    required this.format,
    this.applyEnhancement = false,
    this.languageMode = OcrLanguageMode.arabicEnglish,
    this.compressionPreset = PdfCompressionPreset.none,
    this.manualJpegQuality = 85,
    this.watermarkText,
    this.includeDateStamp = false,
  });

  final String fileName;
  final ExportFormat format;
  final bool applyEnhancement;
  final OcrLanguageMode languageMode;
  final PdfCompressionPreset compressionPreset;
  final int manualJpegQuality;
  final String? watermarkText;
  final bool includeDateStamp;
}

/// Shows a Bottom Sheet to choose the export format (Standard PDF, Searchable PDF, Word .docx, Excel .xlsx),
/// OCR language mode, PDF target-size compression, optional watermark/date stamp, and smart OCR document naming.
Future<SaveAndExportChoice?> showSaveAndExportBottomSheet({
  required BuildContext context,
  String? initialFileName,
  String? initialName,
  required int pageCount,
  String? title,
  bool showNameInput = true,
  List<String>? previewImagePaths,
}) {
  final effectiveName = initialFileName ?? initialName ?? '';
  return showModalBottomSheet<SaveAndExportChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SaveAndExportSheetContent(
      initialFileName: stripFileExtension(effectiveName),
      pageCount: pageCount,
      title: title,
      showNameInput: showNameInput,
      previewImagePaths: previewImagePaths,
    ),
  );
}

class _SaveAndExportSheetContent extends StatefulWidget {
  const _SaveAndExportSheetContent({
    required this.initialFileName,
    required this.pageCount,
    this.title,
    required this.showNameInput,
    this.previewImagePaths,
  });

  final String initialFileName;
  final int pageCount;
  final String? title;
  final bool showNameInput;
  final List<String>? previewImagePaths;

  @override
  State<_SaveAndExportSheetContent> createState() =>
      _SaveAndExportSheetContentState();
}

class _SaveAndExportSheetContentState
    extends State<_SaveAndExportSheetContent> {
  late final TextEditingController _nameController;
  late final TextEditingController _watermarkController;
  ExportFormat _selectedFormat = ExportFormat.pdf;
  OcrLanguageMode _languageMode = OcrLanguageMode.arabicEnglish;
  PdfCompressionPreset _compressionPreset = PdfCompressionPreset.none;
  double _manualQuality = 85;
  bool _enableWatermark = false;
  bool _includeDateStamp = false;
  bool _isSuggestingTitle = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialFileName);
    _watermarkController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _watermarkController.dispose();
    super.dispose();
  }

  Future<void> _suggestSmartTitleFromFirstPage() async {
    final paths = widget.previewImagePaths;
    if (paths == null || paths.isEmpty || _isSuggestingTitle) return;

    setState(() => _isSuggestingTitle = true);
    try {
      final ocrService = OcrService();
      final docData = await ocrService.recognizeDocument(
        documentId: 'smart_title_preview',
        imagePaths: [paths.first],
        languageMode: _languageMode,
      );
      final suggested = docData.suggestedTitle;
      if (mounted && suggested != null && suggested.trim().isNotEmpty) {
        _nameController.text = suggested.trim();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم اقتراح الاسم: ${suggested.trim()}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم العثور على عنوان نصي واضح في الصفحة الأولى.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استخراج العنوان الذكي: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSuggestingTitle = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPdfFormat = _selectedFormat == ExportFormat.pdf ||
        _selectedFormat == ExportFormat.searchablePdf;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.ios_share_rounded,
                    color: palette.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.showNameInput
                            ? 'حفظ وتصدير المستند'
                            : 'تحويل وتصدير الصيغة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${formatPageCount(widget.pageCount)} • يعمل بدون إنترنت 100%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.showNameInput) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        labelText: 'اسم المستند',
                        hintText: 'مثال: عقد_عمل_2026',
                        prefixIcon: Icon(
                          Icons.description_outlined,
                          color: palette.accent,
                        ),
                        suffixIcon: _nameController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _nameController.clear();
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                  ),
                  if (widget.previewImagePaths != null &&
                      widget.previewImagePaths!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'اقتراح اسم ذكي من أول سطر نصي (OCR)',
                      child: FilledButton.tonalIcon(
                        onPressed: _isSuggestingTitle
                            ? null
                            : _suggestSmartTitleFromFirstPage,
                        icon: _isSuggestingTitle
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('اسم ذكي'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'اختر صيغة الحفظ والتصدير:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _buildFormatCard(
              context: context,
              format: ExportFormat.pdf,
              icon: Icons.picture_as_pdf_rounded,
              badgeText: 'الأسرع (0ms)',
              color: const Color(0xFFE11D48),
            ),
            const SizedBox(height: 8),
            _buildFormatCard(
              context: context,
              format: ExportFormat.searchablePdf,
              icon: Icons.manage_search_rounded,
              badgeText: 'PDF قابل للبحث والنسخ',
              color: const Color(0xFF9333EA),
            ),
            const SizedBox(height: 8),
            _buildFormatCard(
              context: context,
              format: ExportFormat.docx,
              icon: Icons.article_rounded,
              badgeText: 'Word OCR + صور',
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(height: 8),
            _buildFormatCard(
              context: context,
              format: ExportFormat.xlsx,
              icon: Icons.table_chart_rounded,
              badgeText: 'Excel جداول RTL',
              color: const Color(0xFF059669),
            ),

            // OCR Language Mode selector when an OCR format is chosen
            if (_selectedFormat.usesOcr) ...[
              const SizedBox(height: 14),
              Text(
                'لغة التعرف الضوئي على النصوص (Tesseract OCR Offline):',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: OcrLanguageMode.values.map((mode) {
                  final selected = _languageMode == mode;
                  return ChoiceChip(
                    label: Text(
                      mode.labelAr,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _languageMode = mode),
                  );
                }).toList(),
              ),
            ],

            // Target-Size Compression & Optional Watermark/Date Stamp for PDF formats
            if (isPdfFormat) ...[
              const SizedBox(height: 14),
              Text(
                'ضغط حجم ملف الـ PDF (للبوابات الحكومية والإيميل):',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PdfCompressionPreset>(
                initialValue: _compressionPreset,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.compress_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                items: PdfCompressionPreset.values
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(
                          preset.labelAr,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _compressionPreset = val);
                  }
                },
              ),
              if (_compressionPreset == PdfCompressionPreset.manual) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('جودة الصور:', style: TextStyle(fontSize: 12.5)),
                    Expanded(
                      child: Slider(
                        value: _manualQuality,
                        min: 20,
                        max: 95,
                        divisions: 15,
                        label: '${_manualQuality.round()}%',
                        onChanged: (v) => setState(() => _manualQuality = v),
                      ),
                    ),
                    Text(
                      '${_manualQuality.round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'خيارات إضافية (علامة مائية مخصصة / ختم التاريخ)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'إضافة علامة مائية نصية مخصصة (اختياري)',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: _enableWatermark,
                    onChanged: (v) => setState(() => _enableWatermark = v),
                  ),
                  if (_enableWatermark)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _watermarkController,
                        decoration: const InputDecoration(
                          labelText: 'نص العلامة المائية',
                          hintText: 'مثال: سري للغاية / نسخة طبق الأصل',
                        ),
                      ),
                    ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'إضافة ختم التاريخ أسفل الصفحات',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: _includeDateStamp,
                    onChanged: (v) => setState(() => _includeDateStamp = v),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: (widget.showNameInput &&
                            _nameController.text.trim().isEmpty)
                        ? null
                        : () {
                            final effectiveName =
                                _nameController.text.trim().isEmpty
                                    ? widget.initialFileName
                                    : _nameController.text.trim();
                            Navigator.of(context).pop(
                              SaveAndExportChoice(
                                fileName: effectiveName,
                                format: _selectedFormat,
                                languageMode: _languageMode,
                                compressionPreset: _compressionPreset,
                                manualJpegQuality: _manualQuality.round(),
                                watermarkText: _enableWatermark
                                    ? _watermarkController.text.trim()
                                    : null,
                                includeDateStamp: _includeDateStamp,
                              ),
                            );
                          },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(
                      'تصدير كـ ${_selectedFormat.extension.toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard({
    required BuildContext context,
    required ExportFormat format,
    required IconData icon,
    required String badgeText,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedFormat == format;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _selectedFormat = format),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark
                  ? theme.colorScheme.surfaceContainerHigh
                  : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          format.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    format.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? color : theme.colorScheme.outline,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the export for [document] to [format] (or [selection]) with a cancellable progress dialog,
/// updates the stored document metadata, and shows Open / Share / Print options.
Future<String?> executeDocumentExportWithUi({
  required BuildContext context,
  required WidgetRef ref,
  required PendingUpload document,
  ExportFormat? format,
  SaveAndExportChoice? selection,
}) async {
  final effectiveFormat = format ?? selection?.format ?? ExportFormat.pdf;
  final progressNotifier = ValueNotifier<String>(
    'جارٍ تحضير الصفحات للتصدير إلى ${effectiveFormat.extension.toUpperCase()}...',
  );
  final cancellationToken = OcrCancellationToken();
  var isCancelled = false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: progressNotifier,
          builder: (_, status, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  isCancelled = true;
                  cancellationToken.cancel();
                  Navigator.of(dialogCtx).pop();
                },
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('إلغاء العملية'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String? exportedPath;
  try {
    final exporter = ref.read(officeExporterServiceProvider);
    exportedPath = await exporter.exportDocument(
      document: document,
      format: effectiveFormat,
      languageMode: selection?.languageMode ?? OcrLanguageMode.arabicEnglish,
      compressionPreset:
          selection?.compressionPreset ?? PdfCompressionPreset.none,
      manualJpegQuality: selection?.manualJpegQuality ?? 85,
      watermarkText: selection?.watermarkText,
      includeDateStamp: selection?.includeDateStamp ?? false,
      cancellationToken: cancellationToken,
      onProgress: (msg) {
        if (!isCancelled) {
          progressNotifier.value = msg;
        }
      },
    );

    if (isCancelled) return null;

    // Persist exported file path on the document record
    final updatedDoc = switch (effectiveFormat) {
      ExportFormat.pdf => document.copyWith(filePath: exportedPath),
      ExportFormat.searchablePdf => document.copyWith(filePath: exportedPath),
      ExportFormat.docx => document.copyWith(docxPath: exportedPath),
      ExportFormat.xlsx => document.copyWith(xlsxPath: exportedPath),
    };
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .updateDocument(updatedDoc);
  } catch (e) {
    if (!isCancelled && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير الملف: $e')),
      );
    }
    return null;
  }

  if (!isCancelled && context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    await showPostExportActionsSheet(
      context: context,
      filePath: exportedPath,
      pdfPathForPrint: document.filePath,
      format: effectiveFormat,
      documentTitle: stripFileExtension(document.fileName),
    );
  }

  return exportedPath;
}

/// Shows post-export actions: Open (`OpenFilex.open`), Share (`Share.shareXFiles`), and Print (`Printing.layoutPdf`).
Future<void> showPostExportActionsSheet({
  required BuildContext context,
  required String filePath,
  required String pdfPathForPrint,
  required ExportFormat format,
  required String documentTitle,
}) {
  final palette = context.appThemePalette;
  final theme = Theme.of(context);
  final fileSize =
      File(filePath).existsSync() ? File(filePath).lengthSync() : 0;

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: palette.success,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'تم تجهيز ملف ${format.extension.toUpperCase()} بنجاح!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$documentTitle.${format.extension} • ${formatFileSize(fileSize)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(sheetCtx).pop();
              await OpenFilex.open(filePath);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('فتح الملف الآن'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await Share.shareXFiles(
                      [XFile(filePath, mimeType: format.mimeType)],
                      subject: documentTitle,
                    );
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    final targetPdf = File(pdfPathForPrint).existsSync()
                        ? pdfPathForPrint
                        : filePath;
                    if (File(targetPdf).existsSync()) {
                      final bytes = await File(targetPdf).readAsBytes();
                      await Printing.layoutPdf(
                        name: documentTitle,
                        onLayout: (_) async => bytes,
                      );
                    }
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('طباعة'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
