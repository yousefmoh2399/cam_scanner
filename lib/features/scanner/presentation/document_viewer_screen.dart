import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

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
import 'document_diff_screen.dart';
import 'magic_clean_screen.dart';
import 'stamp_studio_screen.dart';
import 'web_drop_screen.dart';
import 'widgets/pdf_security_sheet.dart';

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

  Future<void> _magicCleanCurrentPage() async {
    if (_doc.pages.isEmpty || _isRebuildingPdf) return;
    final page = _doc.pages[_currentPageIndex];

    final resultBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => MagicCleanScreen(imagePath: page.imagePath),
      ),
    );

    if (resultBytes != null && mounted) {
      await File(page.imagePath).writeAsBytes(resultBytes, flush: true);
      await FileImage(File(page.imagePath)).evict();
      await _rebuildSavedPdf(List<ScanPage>.from(_doc.pages));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تنظيف الورقة وتحديث المستند بنجاح')),
        );
      }
    }
  }

  Future<void> _stampCurrentPage() async {
    if (_doc.pages.isEmpty || _isRebuildingPdf) return;
    final page = _doc.pages[_currentPageIndex];

    final stampBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => StampStudioScreen(targetPageImagePath: page.imagePath),
      ),
    );

    if (stampBytes == null || !mounted) return;

    final compositedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => SignaturePlacementScreen(
          pageImagePath: page.imagePath,
          signatureBytes: stampBytes,
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
        const SnackBar(content: Text('✅ تم وضع الختم وتحديث المستند بنجاح')),
      );
    }
  }

  Future<void> _lockCurrentDocument() async {
    final result = await showModalBottomSheet<PdfSecurityOptions>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PdfSecuritySheet(document: _doc),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔒 تم قفل وتأمين المستند بنجاح'),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
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
          return Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
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
                            child: PendingUpload.isImageFilePath(p.imagePath) &&
                                    File(p.imagePath).existsSync()
                                ? Image.file(
                                    File(p.imagePath),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.picture_as_pdf_rounded),
                                  )
                                : const Icon(Icons.picture_as_pdf_rounded),
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

  Future<void> _renameDocumentDialog() async {
    final currentName = stripFileExtension(_doc.fileName);
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded, size: 22),
            SizedBox(width: 8),
            Text(
              'إعادة تسمية المستند',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'اسم المستند',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'يرجى إدخال اسم المستند';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        final updated = await ref
            .read(pendingUploadsControllerProvider.notifier)
            .renameDocument(_doc.id, newName);
        if (mounted) {
          setState(() {
            _doc = updated;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تمت إعادة تسمية المستند بنجاح'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر إعادة التسمية: $e')),
          );
        }
      }
    }
  }

  Future<void> _printDocument() async {
    if (File(_doc.filePath).existsSync()) {
      final bytes = await File(_doc.filePath).readAsBytes();
      await Printing.layoutPdf(
        name: stripFileExtension(_doc.fileName),
        onLayout: (_) async => bytes,
      );
    }
  }

  void _showPrivacyInfoDialog() {
    final palette = context.appThemePalette;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.shield_rounded, color: palette.success, size: 26),
            const SizedBox(width: 10),
            const Text(
              'تقرير أمان المستند',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المستند محفوظ بالكامل على جهازك داخل الذاكرة الآمنة، بدون مشاركة أي بيانات أو رفع لسيرفرات سحابية خارجية.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: palette.success),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'خالٍ تماماً من إحداثيات وموقع التصوير (GPS)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: palette.success),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'خالٍ من بيانات الكاميرا الوصفية (EXIF)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: palette.success),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'معالجة المسح والـ OCR محلياً على الهاتف',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddPageSheet() async {
    if (_isRebuildingPdf) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Material(
            color: isDark ? const Color(0xFF1E1E24) : Colors.white,
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            elevation: 12,
            shadowColor: Colors.black38,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 14),
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const Text(
                      'إلحاق صفحة جديدة بالمستند',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModalSourceCard(
                            icon: Icons.camera_alt_rounded,
                            color: const Color(0xFF007AFF),
                            title: 'كاميرا الهاتف',
                            subtitle: 'التقاط فوري مباشر',
                            onTap: () => Navigator.pop(ctx, 'camera'),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildModalSourceCard(
                            icon: Icons.photo_library_rounded,
                            color: const Color(0xFF5856D6),
                            title: 'ألبوم الصور',
                            subtitle: 'اختيار من المعرض',
                            onTap: () => Navigator.pop(ctx, 'gallery'),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (choice == null || !mounted) return;

    if (choice == 'camera') {
      try {
        final scanned = await NativeScannerBridge.startScan(batch: true);
        if (scanned.isNotEmpty && mounted) {
          final newPages = List<ScanPage>.from(_doc.pages);
          for (int i = 0; i < scanned.length; i++) {
            if (!mounted) break;
            final r = scanned[i];
            final reviewResult = await Navigator.of(context).push<dynamic>(
              MaterialPageRoute(
                builder: (_) => ScanReviewScreen(
                  rawImagePath: r.path,
                  sessionId: _doc.id,
                  initialCorners: r.corners,
                  imageWidth: r.width,
                  imageHeight: r.height,
                  pageIndex: i + 1,
                  totalPages: scanned.length,
                ),
              ),
            );
            if (reviewResult is ScanPage) {
              newPages.add(reviewResult);
            } else if (reviewResult is ScanReviewResult) {
              newPages.add(reviewResult.page);
            }
          }
          if (newPages.length > _doc.pages.length && mounted) {
            await _rebuildSavedPdf(newPages);
            setState(() => _currentPageIndex = newPages.length - 1);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPageIndex);
            }
          }
        }
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) {
          await showScannerPermissionDialog(context, e);
        }
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
        return;
      }
    } else if (choice == 'gallery') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty && mounted) {
        final newPages = List<ScanPage>.from(_doc.pages);
        for (final p in result.paths) {
          if (p != null && File(p).existsSync()) {
            newPages.add(ScanPage(
              id: const Uuid().v4(),
              imagePath: p,
              createdAt: DateTime.now(),
            ));
          }
        }
        await _rebuildSavedPdf(newPages);
        setState(() => _currentPageIndex = newPages.length - 1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentPageIndex);
        }
      }
    }
  }

  Widget _buildModalSourceCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppleViewerActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    Color? customColor,
  }) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = customColor ??
        (isPrimary ? palette.accent : (isDark ? Colors.white70 : Colors.black87));

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: isPrimary
                    ? palette.accent.withValues(alpha: 0.16)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isPrimary ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pages = _doc.pages
        .where((p) =>
            PendingUpload.isImageFilePath(p.imagePath) &&
            File(p.imagePath).existsSync())
        .toList();
    final title = stripFileExtension(_doc.fileName);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: InkWell(
          onTap: _renameDocumentDialog,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: palette.accent,
                    ),
                  ],
                ),
                Text(
                  '${formatPageCount(_doc.pageCount)} • ${formatFileSize(_doc.fileSize)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'مشاركة المستند',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () {
              Share.shareXFiles([XFile(_doc.filePath)], subject: title);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'خيارات المستند',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onSelected: (val) {
              switch (val) {
                case 'rename':
                  _renameDocumentDialog();
                  break;
                case 'reorder':
                  _showPageReorderSheet();
                  break;
                case 'excel':
                  _exportToExcelDirectly();
                  break;
                case 'print':
                  _printDocument();
                  break;
                case 'open_external':
                  OpenFilex.open(_doc.filePath);
                  break;
                case 'privacy':
                  _showPrivacyInfoDialog();
                  break;
                case 'magic_clean':
                  _magicCleanCurrentPage();
                  break;
                case 'stamp':
                  _stampCurrentPage();
                  break;
                case 'diff':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentDiffScreen(initialDocA: _doc),
                    ),
                  );
                  break;
                case 'web_drop':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebDropScreen(),
                    ),
                  );
                  break;
                case 'lock':
                  _lockCurrentDocument();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('إعادة تسمية'),
                  ],
                ),
              ),
              if (pages.length > 1)
                const PopupMenuItem(
                  value: 'reorder',
                  child: Row(
                    children: [
                      Icon(Icons.reorder_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('إعادة ترتيب الصفحات'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded, size: 20, color: Color(0xFF059669)),
                    SizedBox(width: 10),
                    Text('تحويل إلى Excel (.xlsx)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('طباعة المستند'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open_external',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('فتح بعارض خارجي'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'magic_clean',
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high_rounded, size: 20, color: Color(0xFFFF2D55)),
                    SizedBox(width: 10),
                    Text('الممحاة الذكية وتنظيف الورق'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'stamp',
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, size: 20, color: Color(0xFFD62B2B)),
                    SizedBox(width: 10),
                    Text('ختم رسمي للوثيقة'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'diff',
                child: Row(
                  children: [
                    Icon(Icons.splitscreen_rounded, size: 20, color: Color(0xFF8B5CF6)),
                    SizedBox(width: 10),
                    Text('مقارنة مع وثيقة أخرى'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'web_drop',
                child: Row(
                  children: [
                    Icon(Icons.wifi_tethering_rounded, size: 20, color: Color(0xFF007AFF)),
                    SizedBox(width: 10),
                    Text('إرسال للكمبيوتر (Web Drop)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'lock',
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 20, color: Color(0xFF059669)),
                    SizedBox(width: 10),
                    Text('قفل وتشفير بكلمة سر'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'privacy',
                child: Row(
                  children: [
                    Icon(Icons.shield_rounded, size: 20, color: palette.success),
                    const SizedBox(width: 10),
                    const Text('فحص الأمان ونظافة EXIF'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── Floating Clean Status Capsule ──
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.25 : 0.04,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'صفحة ${_currentPageIndex + 1} من ${pages.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3.5,
                          height: 3.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.shield_rounded, size: 13, color: palette.success),
                        const SizedBox(width: 4),
                        Text(
                          'خالٍ من بيانات EXIF و GPS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: palette.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Document Page Display Area ──
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
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.45 : 0.12,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
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
                                      cacheWidth: 1440,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.picture_as_pdf_rounded,
                                              size: 64,
                                              color: palette.accent,
                                            ),
                                            const SizedBox(height: 12),
                                            FilledButton.icon(
                                              onPressed: () =>
                                                  OpenFilex.open(_doc.filePath),
                                              icon: const Icon(
                                                  Icons.open_in_new_rounded),
                                              label:
                                                  const Text('فتح ملف الـ PDF'),
                                            ),
                                          ],
                                        ),
                                      ),
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
                              final scale = (1.0 - (diff.abs() * 0.10)).clamp(0.90, 1.0);
                              final rotationY = (-diff * 0.20).clamp(-0.35, 0.35);
                              final opacity = (1.0 - (diff.abs() * 0.30)).clamp(0.55, 1.0);

                              return Transform(
                                alignment: diff > 0
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
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

              // ── Apple Frosted Action Toolbar ──
              if (pages.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      decoration: BoxDecoration(
                        color: (isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white)
                            .withValues(alpha: 0.92),
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: isDark ? 0.35 : 0.6,
                            ),
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.08,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Interactive Mini Thumbnail Filmstrip
                            if (pages.length > 1) ...[
                              SizedBox(
                                height: 48,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                          cacheWidth: 100,
                                          errorBuilder: (_, __, ___) =>
                                              const Center(
                                            child: Icon(
                                              Icons.picture_as_pdf_rounded,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],

                            // Apple Action Dock
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildAppleViewerActionItem(
                                  icon: Icons.crop_rotate_rounded,
                                  label: 'قص وفلاتر',
                                  onTap: _editCurrentPage,
                                ),
                                _buildAppleViewerActionItem(
                                  icon: Icons.draw_rounded,
                                  label: 'توقيع',
                                  customColor: const Color(0xFF34C759),
                                  onTap: _signCurrentPage,
                                ),
                                _buildAppleViewerActionItem(
                                  icon: Icons.rotate_right_rounded,
                                  label: 'تدوير',
                                  customColor: const Color(0xFFFF9500),
                                  onTap: _rotateCurrentPage,
                                ),
                                _buildAppleViewerActionItem(
                                  icon: Icons.psychology_rounded,
                                  label: 'OCR ذكي',
                                  customColor: palette.accent,
                                  onTap: _showSmartExtraction,
                                ),
                                _buildAppleViewerActionItem(
                                  icon: Icons.add_photo_alternate_rounded,
                                  label: 'إضافة صفحة',
                                  customColor: const Color(0xFF5856D6),
                                  onTap: _showAddPageSheet,
                                ),
                                _buildAppleViewerActionItem(
                                  icon: Icons.file_download_rounded,
                                  label: 'تصدير',
                                  isPrimary: true,
                                  onTap: _chooseExportFormat,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
