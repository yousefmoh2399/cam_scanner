import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPdfFormat = _selectedFormat == ExportFormat.pdf ||
        _selectedFormat == ExportFormat.searchablePdf;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.showNameInput
                            ? 'تصدير وحفظ المستند'
                            : 'تحويل وتصدير الصيغة',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${formatPageCount(widget.pageCount)} • معالجة أوفلاين 100%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (widget.showNameInput) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: 'اسم المستند...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    fillColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    filled: true,
                    prefixIcon: const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: Color(0xFF8E8E93),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_nameController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () {
                              _nameController.clear();
                              setState(() {});
                            },
                          ),
                        if (widget.previewImagePaths != null &&
                            widget.previewImagePaths!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, right: 2),
                            child: InkWell(
                              onTap: _isSuggestingTitle
                                  ? null
                                  : _suggestSmartTitleFromFirstPage,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: _isSuggestingTitle
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 13,
                                            color: palette.accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'اسم ذكي',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: palette.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: palette.accent,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            Text(
              'اختر صيغة التصدير:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),

            // ── Apple 2x2 Compact Format Cards Grid ──
            Row(
              children: [
                Expanded(
                  child: _buildCompactFormatCard(
                    format: ExportFormat.pdf,
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'PDF قياسي',
                    badge: 'فوري (0ms)',
                    color: const Color(0xFFFF3B30),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactFormatCard(
                    format: ExportFormat.searchablePdf,
                    icon: Icons.manage_search_rounded,
                    title: 'PDF للبحث',
                    badge: 'OCR نصوص',
                    color: const Color(0xFFAF52DE),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildCompactFormatCard(
                    format: ExportFormat.docx,
                    icon: Icons.article_rounded,
                    title: 'Word مستند',
                    badge: '.docx وصور',
                    color: const Color(0xFF007AFF),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactFormatCard(
                    format: ExportFormat.xlsx,
                    icon: Icons.table_chart_rounded,
                    title: 'Excel جداول',
                    badge: '.xlsx و RTL',
                    color: const Color(0xFF34C759),
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            // OCR Language Mode selector (Segmented pill bar)
            if (_selectedFormat.usesOcr) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, size: 16, color: Color(0xFF8E8E93)),
                    const SizedBox(width: 6),
                    const Text('لغة OCR:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    ...OcrLanguageMode.values.map((mode) {
                      final isSelected = _languageMode == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _languageMode = mode);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              mode.labelAr,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? (isDark ? Colors.white : Colors.black)
                                    : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            // Target-Size Compression for PDF formats
            if (isPdfFormat) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, size: 16, color: Color(0xFF8E8E93)),
                        const SizedBox(width: 6),
                        const Text(
                          'ضغط الحجم:',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<PdfCompressionPreset>(
                                value: _compressionPreset,
                                isDense: true,
                                isExpanded: true,
                                alignment: AlignmentDirectional.centerEnd,
                                borderRadius: BorderRadius.circular(12),
                                items: PdfCompressionPreset.values
                                    .map(
                                      (preset) => DropdownMenuItem(
                                        value: preset,
                                        alignment: AlignmentDirectional.centerEnd,
                                        child: Text(
                                          preset.labelAr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _compressionPreset = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_compressionPreset == PdfCompressionPreset.manual) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('جودة الصور:', style: TextStyle(fontSize: 11)),
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
                          Text('${_manualQuality.round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    const Divider(height: 12, thickness: 0.5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _enableWatermark = !_enableWatermark);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _enableWatermark
                                  ? palette.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _enableWatermark ? Icons.check_circle_rounded : Icons.water_drop_outlined,
                                  size: 13,
                                  color: _enableWatermark ? palette.accent : const Color(0xFF8E8E93),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'علامة مائية',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _enableWatermark ? FontWeight.w700 : FontWeight.w500,
                                    color: _enableWatermark ? palette.accent : const Color(0xFF8E8E93),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _includeDateStamp = !_includeDateStamp);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _includeDateStamp
                                  ? palette.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _includeDateStamp ? Icons.check_circle_rounded : Icons.calendar_today_outlined,
                                  size: 13,
                                  color: _includeDateStamp ? palette.accent : const Color(0xFF8E8E93),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ختم التاريخ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _includeDateStamp ? FontWeight.w700 : FontWeight.w500,
                                    color: _includeDateStamp ? palette.accent : const Color(0xFF8E8E93),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_enableWatermark) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _watermarkController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'نص العلامة المائية...',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            fillColor: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Apple Primary Export Button
            FilledButton.icon(
              onPressed: (widget.showNameInput &&
                      _nameController.text.trim().isEmpty)
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      final effectiveName = _nameController.text.trim().isEmpty
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
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded, size: 19),
              label: Text(
                'تصدير كـ ${_selectedFormat.extension.toUpperCase()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactFormatCard({
    required ExportFormat format,
    required IconData icon,
    required String title,
    required String badge,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _selectedFormat == format;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFormat = format);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.16 : 0.08)
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    badge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? color
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: color,
                size: 17,
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
