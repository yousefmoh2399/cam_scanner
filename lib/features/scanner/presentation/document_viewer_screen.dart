import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/native_scanner_bridge.dart';
import '../data/office_exporter_service.dart';
import 'scan_review_screen.dart';
import 'signature_bottom_sheet.dart';
import 'signature_placement_screen.dart';
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';

/// Screen for viewing a saved document's pages with Hero animation,
/// allowing non-destructive re-cropping/filtering, adding signatures,
/// rotating pages, printing, sharing, or exporting to PDF/Word/Excel at any time.
class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.document,
  });

  final PendingUpload document;

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  late PendingUpload _doc;
  int _currentPageIndex = 0;
  bool _isRebuildingPdf = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _rebuildSavedPdf(List<ScanPage> updatedPages) async {
    setState(() => _isRebuildingPdf = true);
    try {
      final pdfBytes = await ref.read(pdfBuilderServiceProvider).buildPdf(
            imagePaths: updatedPages.map((p) => p.imagePath).toList(),
            paperSizes: updatedPages.map((p) => p.paperSize).toList(),
          );
      final pdfFile = File(_doc.filePath);
      await pdfFile.parent.create(recursive: true);
      await pdfFile.writeAsBytes(pdfBytes, flush: true);

      final updatedDoc = _doc.copyWith(
        pages: updatedPages,
        pageCount: updatedPages.length,
        fileSize: await pdfFile.length(),
        thumbnailPath:
            updatedPages.isNotEmpty ? updatedPages.first.imagePath : null,
      );
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .updateDocument(updatedDoc);
      if (mounted) {
        setState(() {
          _doc = updatedDoc;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تحديث المستند: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRebuildingPdf = false);
      }
    }
  }

  Future<void> _editCurrentPage() async {
    if (_doc.pages.isEmpty || _isRebuildingPdf) return;
    final page = _doc.pages[_currentPageIndex];
    final sourcePath = page.originalPath ?? page.imagePath;

    final updatedPage = await Navigator.of(context).push<ScanPage>(
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          rawImagePath: sourcePath,
          sessionId: _doc.id,
          pageId: page.id,
          initialCorners: page.corners ?? const [],
          initialFilter: page.filter.nativeKey,
          initialQuarterRotations: page.quarterTurns,
        ),
      ),
    );

    if (updatedPage != null && mounted) {
      final nextPages = List<ScanPage>.from(_doc.pages);
      nextPages[_currentPageIndex] = updatedPage;
      await _rebuildSavedPdf(nextPages);
    }
  }

  Future<void> _signCurrentPage() async {
    if (_doc.pages.isEmpty || _isRebuildingPdf) return;
    final page = _doc.pages[_currentPageIndex];

    final storageService = ref.read(signatureStorageServiceProvider);
    final sigResult = await showSignatureBottomSheet(
      context: context,
      storageService: storageService,
    );
    if (sigResult == null || !mounted) return;

    final compositedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => SignaturePlacementScreen(
          pageImagePath: page.imagePath,
          signatureBytes: sigResult.pngBytes,
        ),
        fullscreenDialog: true,
      ),
    );
    if (compositedBytes == null || !mounted) return;

    await File(page.imagePath).writeAsBytes(compositedBytes, flush: true);
    await FileImage(File(page.imagePath)).evict();
    await _rebuildSavedPdf(List<ScanPage>.from(_doc.pages));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم دمج التوقيع وتحديث المستند بنجاح')),
      );
    }
  }

  Future<void> _rotateCurrentPage() async {
    if (_doc.pages.isEmpty || _isRebuildingPdf) return;
    final page = _doc.pages[_currentPageIndex];
    final tempRotated = '${page.imagePath}.rot.jpg';
    await NativeScannerBridge.rotateLeft(
      path: page.imagePath,
      outPath: tempRotated,
    );
    final f = File(tempRotated);
    if (await f.exists()) {
      await f.rename(page.imagePath);
    }
    await FileImage(File(page.imagePath)).evict();
    final nextPages = List<ScanPage>.from(_doc.pages);
    nextPages[_currentPageIndex] = page.copyWith(
      quarterTurns: (page.quarterTurns + 1) % 4,
    );
    await _rebuildSavedPdf(nextPages);
  }

  Future<void> _chooseExportFormat() async {
    final choice = await showSaveAndExportBottomSheet(
      context: context,
      initialFileName: _doc.fileName,
      pageCount: _doc.pageCount,
      showNameInput: false,
    );
    if (choice == null || !mounted) return;
    await executeDocumentExportWithUi(
      context: context,
      ref: ref,
      document: _doc,
      format: choice.format,
    );
  }

  Future<void> _exportToExcelDirectly() async {
    await executeDocumentExportWithUi(
      context: context,
      ref: ref,
      document: _doc,
      format: ExportFormat.xlsx,
    );
  }

  Future<void> _showPageReorderSheet() async {
    if (_doc.pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المستند يحتوي على صفحة واحدة فقط')),
      );
      return;
    }

    final reordered = List<ScanPage>.from(_doc.pages);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.reorder_rounded),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'إعادة ترتيب الصفحات بالسحب',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حفظ الترتيب'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: reordered.length,
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      setSheetState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (ctx, i) {
                      final p = reordered[i];
                      return ListTile(
                        key: ValueKey(p.id),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: File(p.imagePath).existsSync()
                                ? Image.file(File(p.imagePath), fit: BoxFit.cover)
                                : const Icon(Icons.image),
                          ),
                        ),
                        title: Text('صفحة ${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: const Icon(Icons.drag_handle_rounded),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      await _rebuildSavedPdf(reordered);
      setState(() => _currentPageIndex = 0);
    }
  }

  Future<void> _showSmartExtraction() async {
    if (_doc.pages.isEmpty) return;
    setState(() => _isRebuildingPdf = true);
    try {
      final ocr = ref.read(ocrServiceProvider);
      final page = _doc.pages[_currentPageIndex];
      final text = await ocr.extractTextFromFile(page.imagePath);
      if (!mounted) return;
      setState(() => _isRebuildingPdf = false);
      await SmartDataExtractionSheet.show(
        context: context,
        text: text,
        document: _doc,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isRebuildingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استخراج النص: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);
    final pages = _doc.pages;
    final title = stripFileExtension(_doc.fileName);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              '${formatPageCount(_doc.pageCount)} • ${formatFileSize(_doc.fileSize)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        actions: [
          if (pages.length > 1)
            IconButton(
              tooltip: 'إعادة ترتيب الصفحات بالسحب',
              icon: const Icon(Icons.reorder_rounded),
              onPressed: _showPageReorderSheet,
            ),
          IconButton(
            tooltip: 'استخراج ذكي OCR وقراءة صوتية',
            icon: Icon(Icons.psychology_rounded, color: palette.accent),
            onPressed: _showSmartExtraction,
          ),
          IconButton(
            tooltip: 'تحويل الجداول إلى Excel (.xlsx)',
            icon: const Icon(
              Icons.table_chart_rounded,
              color: Color(0xFF059669),
            ),
            onPressed: _exportToExcelDirectly,
          ),
          IconButton(
            tooltip: 'تصدير / تحويل الصيغة (PDF, Word, Excel)',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _chooseExportFormat,
          ),
          IconButton(
            tooltip: 'طباعة المستند',
            icon: const Icon(Icons.print_rounded),
            onPressed: () async {
              if (File(_doc.filePath).existsSync()) {
                final bytes = await File(_doc.filePath).readAsBytes();
                await Printing.layoutPdf(
                  name: title,
                  onLayout: (_) async => bytes,
                );
              }
            },
          ),
          IconButton(
            tooltip: 'فتح بعارض خارجي',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => OpenFilex.open(_doc.filePath),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Privacy Clean Indicator Badge
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.success.withValues(alpha: 0.08),
                  border: Border(
                    bottom: BorderSide(
                      color: palette.success.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_rounded, color: palette.success, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ملفك نظيف وخصوصيتك محفوظة • خالي تماماً من بيانات الموقع وEXIF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: pages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 64,
                              color: palette.accent,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _doc.fileName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => OpenFilex.open(_doc.filePath),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('فتح ملف الـ PDF'),
                            ),
                          ],
                        ),
                      )
                    : PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: pages.length,
                        onPageChanged: (idx) {
                          HapticFeedback.selectionClick();
                          setState(() => _currentPageIndex = idx);
                        },
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          final imageWidget = InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: theme.brightness == Brightness.dark
                                              ? 0.45
                                              : 0.15,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.file(
                                      File(page.imagePath),
                                      key: ValueKey(
                                        File(page.imagePath).existsSync()
                                            ? File(page.imagePath)
                                                .lastModifiedSync()
                                                .millisecondsSinceEpoch
                                            : index,
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                          final baseWidget = index == 0
                              ? Hero(
                                  tag: 'doc_thumb_${_doc.id}',
                                  child: imageWidget,
                                )
                              : imageWidget;

                          return AnimatedBuilder(
                            animation: _pageController,
                            builder: (context, child) {
                              double pagePos = index.toDouble();
                              if (_pageController.position.haveDimensions) {
                                pagePos = _pageController.page ?? index.toDouble();
                              }
                              final diff = pagePos - index;
                              // Subtle Apple Depth & 3D perspective
                              final scale = (1.0 - (diff.abs() * 0.10)).clamp(0.90, 1.0);
                              final rotationY = (-diff * 0.20).clamp(-0.35, 0.35);
                              final opacity = (1.0 - (diff.abs() * 0.30)).clamp(0.55, 1.0);

                              return Transform(
                                alignment: diff > 0 ? Alignment.centerRight : Alignment.centerLeft,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(rotationY)
                                  ..scaleByDouble(scale, scale, 1.0, 1.0),
                                child: Opacity(
                                  opacity: opacity,
                                  child: child,
                                ),
                              );
                            },
                            child: baseWidget,
                          );
                        },
                      ),
              ),
              if (pages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'صفحة ${_currentPageIndex + 1} من ${pages.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Interactive Mini Thumbnail Filmstrip
                        if (pages.length > 1) ...[
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: pages.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (ctx, idx) {
                                final isCur = idx == _currentPageIndex;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _pageController.animateToPage(
                                      idx,
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                    );
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 34,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCur ? palette.accent : Colors.black12,
                                        width: isCur ? 2.5 : 1,
                                      ),
                                      boxShadow: isCur
                                          ? [
                                              BoxShadow(
                                                color: palette.accent.withValues(alpha: 0.35),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.file(
                                      File(pages[idx].imagePath),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _editCurrentPage,
                                icon: const Icon(Icons.crop_rotate_rounded, size: 18),
                                label: const Text('قص وفلاتر'),
                              ),
                              const SizedBox(width: 8),
                              if (pages.length > 1) ...[
                                FilledButton.tonalIcon(
                                  onPressed: _showPageReorderSheet,
                                  icon: const Icon(Icons.reorder_rounded, size: 18),
                                  label: const Text('ترتيب الصفحات'),
                                ),
                                const SizedBox(width: 8),
                              ],
                              FilledButton.tonalIcon(
                                onPressed: _showSmartExtraction,
                                icon: Icon(Icons.psychology_rounded, size: 18, color: palette.accent),
                                label: const Text('استخراج ذكي'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _signCurrentPage,
                                icon: const Icon(Icons.draw_rounded, size: 18),
                                label: const Text('توقيع'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _rotateCurrentPage,
                                icon: const Icon(Icons.rotate_left_rounded, size: 18),
                                label: const Text('تدوير'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _exportToExcelDirectly,
                                icon: const Icon(
                                  Icons.table_chart_rounded,
                                  size: 18,
                                  color: Color(0xFF059669),
                                ),
                                label: const Text('تحويل لـ Excel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: _chooseExportFormat,
                                icon: const Icon(Icons.file_download_rounded, size: 18),
                                label: const Text('تصدير (PDF/Word/Excel)'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Share.shareXFiles(
                                    [XFile(_doc.filePath)],
                                    subject: title,
                                  );
                                },
                                icon: const Icon(Icons.share_rounded, size: 18),
                                label: const Text('مشاركة'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_isRebuildingPdf)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
