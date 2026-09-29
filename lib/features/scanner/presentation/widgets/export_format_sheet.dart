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
import '../../data/office_exporter_service.dart';

class SaveAndExportChoice {
  const SaveAndExportChoice({
    required this.fileName,
    required this.format,
    this.applyEnhancement = false,
  });

  final String fileName;
  final ExportFormat format;
  final bool applyEnhancement;
}

/// Shows a Bottom Sheet to choose the export format (PDF, Word .docx, Excel .xlsx)
/// and optionally enter/confirm the document name.
Future<SaveAndExportChoice?> showSaveAndExportBottomSheet({
  required BuildContext context,
  String? initialFileName,
  String? initialName,
  required int pageCount,
  String? title,
  bool showNameInput = true,
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
    ),
  );
}

class _SaveAndExportSheetContent extends StatefulWidget {
  const _SaveAndExportSheetContent({
    required this.initialFileName,
    required this.pageCount,
    this.title,
    required this.showNameInput,
  });

  final String initialFileName;
  final int pageCount;
  final String? title;
  final bool showNameInput;

  @override
  State<_SaveAndExportSheetContent> createState() =>
      _SaveAndExportSheetContentState();
}

class _SaveAndExportSheetContentState
    extends State<_SaveAndExportSheetContent> {
  late final TextEditingController _nameController;
  ExportFormat _selectedFormat = ExportFormat.pdf;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialFileName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appThemePalette;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
              TextField(
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
              badgeText: 'الأسرع',
              color: const Color(0xFFE11D48),
            ),
            const SizedBox(height: 10),
            _buildFormatCard(
              context: context,
              format: ExportFormat.docx,
              icon: Icons.article_rounded,
              badgeText: 'OCR + صور',
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(height: 10),
            _buildFormatCard(
              context: context,
              format: ExportFormat.xlsx,
              icon: Icons.table_chart_rounded,
              badgeText: 'OCR جداول',
              color: const Color(0xFF059669),
            ),
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
                    onPressed: _nameController.text.trim().isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop(
                              SaveAndExportChoice(
                                fileName: _nameController.text.trim(),
                                format: _selectedFormat,
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
        padding: const EdgeInsets.all(14),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
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
  final fileSize = File(filePath).existsSync() ? File(filePath).lengthSync() : 0;

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
