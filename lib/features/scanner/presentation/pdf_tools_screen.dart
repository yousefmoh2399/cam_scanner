import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../data/pdf_builder_service.dart';

/// Item representing a PDF or Image to be merged
class MergeItem {
  MergeItem({
    required this.id,
    required this.title,
    required this.path,
    required this.isPdf,
    required this.sizeBytes,
    this.pageCount,
    this.thumbnailPath,
    this.pages = const [],
  });

  final String id;
  final String title;
  final String path;
  final bool isPdf;
  final int sizeBytes;
  final int? pageCount;
  final String? thumbnailPath;
  final List<ScannedPage> pages;
}

/// Phase 3.2: Comprehensive Offline PDF Tools Hub
/// Featuring 4 Dedicated Workspaces:
/// 1. Merge PDFs & Images (External Storage + Library with drag-to-reorder)
/// 2. Split & Extract Pages (External PDF + Library docs)
/// 3. Target-Size PDF Compression (<200KB, <500KB, <1MB, <2MB, Custom KB)
/// 4. Import & OCR External Documents into Library
class PdfToolsScreen extends ConsumerStatefulWidget {
  const PdfToolsScreen({super.key});

  @override
  ConsumerState<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends ConsumerState<PdfToolsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isWorking = false;
  String _statusMessage = '';

  // ── Tab 1: Merge State ──
  final List<MergeItem> _mergeItems = [];
  final TextEditingController _mergeTitleCtrl = TextEditingController(
    text: 'مستند_مدمج',
  );
  PdfCompressionPreset _mergeCompression = PdfCompressionPreset.none;

  // ── Tab 2: Split State ──
  String? _splitPdfPath;
  String? _splitPdfTitle;
  int _splitTotalPages = 0;
  bool _splitEveryPage = false;
  final TextEditingController _splitFromCtrl = TextEditingController(text: '1');
  final TextEditingController _splitToCtrl = TextEditingController(text: '1');
  PendingUpload? _splitLibraryDoc;

  // ── Tab 3: Compress State ──
  String? _compressPdfPath;
  String? _compressPdfTitle;
  int _compressOriginalSize = 0;
  PendingUpload? _compressLibraryDoc;
  PdfCompressionPreset _compressPreset = PdfCompressionPreset.under500kb;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mergeTitleCtrl.dispose();
    _splitFromCtrl.dispose();
    _splitToCtrl.dispose();
    super.dispose();
  }

  void _showResultDialog({
    required String filePath,
    required String title,
    String? subtitle,
  }) {
    final palette = context.appThemePalette;
    final file = File(filePath);
    final sizeStr = file.existsSync() ? formatFileSize(file.lengthSync()) : '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Text(subtitle, style: const TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 12),
            ],
            if (sizeStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: palette.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'حجم الملف النهائي: $sizeStr',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة'),
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(filePath)]);
            },
          ),
          if (filePath.endsWith('.pdf'))
            TextButton.icon(
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('طباعة'),
              onPressed: () async {
                Navigator.pop(ctx);
                final bytes = await File(filePath).readAsBytes();
                await Printing.layoutPdf(onLayout: (_) => bytes);
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('فتح الملف'),
            onPressed: () {
              Navigator.pop(ctx);
              OpenFilex.open(filePath);
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: MERGE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _addExternalFilesToMerge() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;

    for (final f in result.files) {
      if (f.path == null) continue;
      final file = File(f.path!);
      final isPdf = p.extension(f.path!).toLowerCase() == '.pdf';
      _mergeItems.add(
        MergeItem(
          id: 'ext_${DateTime.now().microsecondsSinceEpoch}',
          title: stripFileExtension(f.name),
          path: f.path!,
          isPdf: isPdf,
          sizeBytes: file.existsSync() ? file.lengthSync() : 0,
        ),
      );
    }
    setState(() {});
  }

  Future<void> _addLibraryDocToMerge() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<PendingUpload>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مستنداً لإضافته لقائمة الدمج:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (_, idx) {
                    final d = docs[idx];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_rounded,
                          color: Color(0xFF9333EA)),
                      title: Text(
                        stripFileExtension(d.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(formatPageCount(d.effectivePageCount)),
                      onTap: () => Navigator.pop(ctx, d),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null) {
      final file = File(chosen.filePath);
      _mergeItems.add(
        MergeItem(
          id: chosen.id,
          title: stripFileExtension(chosen.fileName),
          path: chosen.filePath,
          isPdf: true,
          sizeBytes: file.existsSync() ? file.lengthSync() : 0,
          pageCount: chosen.effectivePageCount,
          thumbnailPath: chosen.thumbnailPath,
          pages: chosen.pages,
        ),
      );
      setState(() {});
    }
  }

  Future<void> _executeMerge() async {
    if (_mergeItems.length < 2) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ استخراج الصفحات ودمج المستندات بالترتيب المختار...';
    });

    try {
      const storage = LocalMediaStorageService();
      final pagesDir = await storage.pagesDirectory();
      final docsDir = await storage.documentsDirectory();
      final allScannedPages = <ScannedPage>[];
      final now = DateTime.now();

      for (var i = 0; i < _mergeItems.length; i++) {
        final item = _mergeItems[i];
        if (item.pages.isNotEmpty) {
          // Already have scanned pages from library
          allScannedPages.addAll(item.pages);
        } else if (item.isPdf) {
          // Rasterize external PDF
          final pdfBytes = await File(item.path).readAsBytes();
          var pIdx = 0;
          await for (final raster in Printing.raster(pdfBytes, dpi: 150)) {
            final pngBytes = await raster.toPng();
            final decoded = img.decodePng(pngBytes);
            if (decoded != null) {
              final jpgBytes = img.encodeJpg(decoded, quality: 88);
              final pagePath = p.join(
                pagesDir.path,
                'mrg_${now.millisecondsSinceEpoch}_p${i}_$pIdx.jpg',
              );
              await File(pagePath).writeAsBytes(jpgBytes, flush: true);
              allScannedPages.add(
                ScannedPage(
                  imagePath: pagePath,
                  originalImagePath: pagePath,
                  filterName: 'original',
                  paperSize: DocumentPaperSize.a4,
                ),
              );
              pIdx++;
            }
          }
        } else {
          // Standalone external image
          final rawBytes = await File(item.path).readAsBytes();
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            final jpgBytes = img.encodeJpg(decoded, quality: 88);
            final pagePath = p.join(
              pagesDir.path,
              'mrg_${now.millisecondsSinceEpoch}_img_$i.jpg',
            );
            await File(pagePath).writeAsBytes(jpgBytes, flush: true);
            allScannedPages.add(
              ScannedPage(
                imagePath: pagePath,
                originalImagePath: pagePath,
                filterName: 'original',
                paperSize: DocumentPaperSize.a4,
              ),
            );
          }
        }
      }

      if (allScannedPages.isEmpty) {
        throw Exception('لم يتم العثور على صفحات صالحة للدمج.');
      }

      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final pdfBytes = await pdfBuilder.buildPdf(
        imagePaths: allScannedPages.map((e) => e.imagePath).toList(),
        paperSizes: allScannedPages.map((e) => e.paperSize).toList(),
        options: PdfBuildOptions(compressionPreset: _mergeCompression),
      );

      final cleanTitle = _mergeTitleCtrl.text.trim().isEmpty
          ? 'مستند_مدمج_${now.millisecondsSinceEpoch % 10000}'
          : _mergeTitleCtrl.text.trim();
      final docId = 'mrg_${now.millisecondsSinceEpoch}';
      final outPath = p.join(docsDir.path, '${docId}_$cleanTitle.pdf');
      await File(outPath).writeAsBytes(pdfBytes, flush: true);

      final mergedDoc = PendingUpload(
        id: docId,
        filePath: outPath,
        fileName: '$cleanTitle.pdf',
        fileType: 'pdf',
        createdAt: now,
        status: 'saved',
        pageCount: allScannedPages.length,
        thumbnailPath: allScannedPages.first.imagePath,
        pages: allScannedPages,
      );

      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .addDocument(mergedDoc);

      if (!mounted) return;
      _mergeItems.clear();
      setState(() {});

      _showResultDialog(
        filePath: outPath,
        title: 'تم دمج الملفات بنجاح',
        subtitle:
            'تم إنشاء المستند المدمج "$cleanTitle" (${allScannedPages.length} صفحة) وحفظه في مكتبتك.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الدمج: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: SPLIT LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickExternalPdfForSplit() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }

    final pth = result.files.first.path!;
    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ قراءة صفحات ملف الـ PDF...';
    });

    try {
      final bytes = await File(pth).readAsBytes();
      var count = 0;
      await for (final _ in Printing.raster(bytes, dpi: 72)) {
        count++;
      }

      setState(() {
        _splitPdfPath = pth;
        _splitPdfTitle = stripFileExtension(result.files.first.name);
        _splitTotalPages = count;
        _splitLibraryDoc = null;
        _splitFromCtrl.text = '1';
        _splitToCtrl.text = '$count';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قراءة الـ PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _pickLibraryDocForSplit() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<PendingUpload>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مستنداً من المكتبة لتقسيمه:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (_, idx) {
                    final d = docs[idx];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_rounded,
                          color: Color(0xFF0D9488)),
                      title: Text(
                        stripFileExtension(d.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(formatPageCount(d.effectivePageCount)),
                      onTap: () => Navigator.pop(ctx, d),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null) {
      setState(() {
        _splitLibraryDoc = chosen;
        _splitPdfPath = chosen.filePath;
        _splitPdfTitle = stripFileExtension(chosen.fileName);
        _splitTotalPages = chosen.effectivePageCount;
        _splitFromCtrl.text = '1';
        _splitToCtrl.text = '${chosen.effectivePageCount}';
      });
    }
  }

  Future<void> _executeSplit() async {
    if (_splitPdfPath == null || _splitTotalPages < 2) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ استخراج الصفحات وتقسيم الملف...';
    });

    try {
      const storage = LocalMediaStorageService();
      final docsDir = await storage.documentsDirectory();
      final pagesDir = await storage.pagesDirectory();
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final baseTitle = _splitPdfTitle ?? 'مستند';

      // Load all pages as ScannedPages
      List<ScannedPage> pagesToSplit = [];
      if (_splitLibraryDoc != null && _splitLibraryDoc!.pages.isNotEmpty) {
        pagesToSplit = _splitLibraryDoc!.pages;
      } else {
        // Rasterize external PDF
        final bytes = await File(_splitPdfPath!).readAsBytes();
        var pIdx = 0;
        await for (final raster in Printing.raster(bytes, dpi: 160)) {
          final png = await raster.toPng();
          final decoded = img.decodePng(png);
          if (decoded != null) {
            final jpg = img.encodeJpg(decoded, quality: 90);
            final pth = p.join(
              pagesDir.path,
              'spl_${DateTime.now().millisecondsSinceEpoch}_$pIdx.jpg',
            );
            await File(pth).writeAsBytes(jpg, flush: true);
            pagesToSplit.add(
              ScannedPage(
                imagePath: pth,
                originalImagePath: pth,
                filterName: 'original',
                paperSize: DocumentPaperSize.a4,
              ),
            );
            pIdx++;
          }
        }
      }

      if (_splitEveryPage) {
        // Split every page
        for (var i = 0; i < pagesToSplit.length; i++) {
          final pg = pagesToSplit[i];
          final pdfBytes = await pdfBuilder.buildPdf(
            imagePaths: [pg.imagePath],
            paperSizes: [pg.paperSize],
          );
          final splitId = 'spl_${DateTime.now().millisecondsSinceEpoch}_$i';
          final title = '${baseTitle}_صفحة_${i + 1}';
          final outPath = p.join(docsDir.path, '${splitId}_$title.pdf');
          await File(outPath).writeAsBytes(pdfBytes, flush: true);

          await ref.read(pendingUploadsControllerProvider.notifier).addDocument(
                PendingUpload(
                  id: splitId,
                  filePath: outPath,
                  fileName: '$title.pdf',
                  fileType: 'pdf',
                  createdAt: DateTime.now(),
                  status: 'saved',
                  pageCount: 1,
                  thumbnailPath: pg.imagePath,
                  pages: [pg],
                ),
              );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم فصل ${pagesToSplit.length} صفحات كملفات مستقلة في المكتبة بنجاح!',
              ),
            ),
          );
        }
      } else {
        // Range extraction
        final start = (int.tryParse(_splitFromCtrl.text.trim()) ?? 1)
            .clamp(1, pagesToSplit.length);
        final end = (int.tryParse(_splitToCtrl.text.trim()) ?? pagesToSplit.length)
            .clamp(start, pagesToSplit.length);
        final subPages = pagesToSplit.sublist(start - 1, end);

        final pdfBytes = await pdfBuilder.buildPdf(
          imagePaths: subPages.map((e) => e.imagePath).toList(),
          paperSizes: subPages.map((e) => e.paperSize).toList(),
        );
        final splitId = 'spl_${DateTime.now().millisecondsSinceEpoch}';
        final title = '${baseTitle}_ص${start}_إلى_ص$end';
        final outPath = p.join(docsDir.path, '${splitId}_$title.pdf');
        await File(outPath).writeAsBytes(pdfBytes, flush: true);

        final newDoc = PendingUpload(
          id: splitId,
          filePath: outPath,
          fileName: '$title.pdf',
          fileType: 'pdf',
          createdAt: DateTime.now(),
          status: 'saved',
          pageCount: subPages.length,
          thumbnailPath: subPages.first.imagePath,
          pages: subPages,
        );

        await ref
            .read(pendingUploadsControllerProvider.notifier)
            .addDocument(newDoc);

        if (!mounted) return;
        _showResultDialog(
          filePath: outPath,
          title: 'تم استخراج الصفحات بنجاح',
          subtitle: 'تم إنشاء مستند "$title" (${subPages.length} صفحة) وحفظه في المكتبة.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التقسيم: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: COMPRESS LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickExternalPdfForCompress() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }

    final pth = result.files.first.path!;
    final file = File(pth);
    setState(() {
      _compressPdfPath = pth;
      _compressPdfTitle = stripFileExtension(result.files.first.name);
      _compressOriginalSize = file.existsSync() ? file.lengthSync() : 0;
      _compressLibraryDoc = null;
    });
  }

  Future<void> _pickLibraryDocForCompress() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة حالياً.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<PendingUpload>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مستنداً من المكتبة لضغط حجمه:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (_, idx) {
                    final d = docs[idx];
                    final sz = File(d.filePath).existsSync()
                        ? File(d.filePath).lengthSync()
                        : 0;
                    return ListTile(
                      leading: const Icon(Icons.compress_rounded,
                          color: Color(0xFF4F46E5)),
                      title: Text(
                        stripFileExtension(d.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatPageCount(d.effectivePageCount)} • ${formatFileSize(sz)}',
                      ),
                      onTap: () => Navigator.pop(ctx, d),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null) {
      final file = File(chosen.filePath);
      setState(() {
        _compressLibraryDoc = chosen;
        _compressPdfPath = chosen.filePath;
        _compressPdfTitle = stripFileExtension(chosen.fileName);
        _compressOriginalSize = file.existsSync() ? file.lengthSync() : 0;
      });
    }
  }

  Future<void> _executeCompress() async {
    if (_compressPdfPath == null) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ ضغط ملف الـ PDF ليصل لأقل من (${_compressPreset.labelAr})...';
    });

    try {
      const storage = LocalMediaStorageService();
      final pagesDir = await storage.pagesDirectory();
      final exportsDir = await storage.exportsDirectory();
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final baseTitle = _compressPdfTitle ?? 'مستند';

      List<ScannedPage> pagesToCompress = [];
      if (_compressLibraryDoc != null && _compressLibraryDoc!.pages.isNotEmpty) {
        pagesToCompress = _compressLibraryDoc!.pages;
      } else {
        // Rasterize external PDF
        final bytes = await File(_compressPdfPath!).readAsBytes();
        var pIdx = 0;
        await for (final raster in Printing.raster(bytes, dpi: 150)) {
          final png = await raster.toPng();
          final decoded = img.decodePng(png);
          if (decoded != null) {
            final jpg = img.encodeJpg(decoded, quality: 85);
            final pth = p.join(
              pagesDir.path,
              'cmp_${DateTime.now().millisecondsSinceEpoch}_$pIdx.jpg',
            );
            await File(pth).writeAsBytes(jpg, flush: true);
            pagesToCompress.add(
              ScannedPage(
                imagePath: pth,
                originalImagePath: pth,
                filterName: 'original',
                paperSize: DocumentPaperSize.a4,
              ),
            );
            pIdx++;
          }
        }
      }

      final compressedBytes = await pdfBuilder.buildPdf(
        imagePaths: pagesToCompress.map((p) => p.imagePath).toList(),
        paperSizes: pagesToCompress.map((p) => p.paperSize).toList(),
        options: PdfBuildOptions(compressionPreset: _compressPreset),
      );

      final outPath = p.join(
        exportsDir.path,
        'compressed_${DateTime.now().millisecondsSinceEpoch}_$baseTitle.pdf',
      );
      await File(outPath).writeAsBytes(compressedBytes, flush: true);

      if (!mounted) return;
      final newSize = compressedBytes.length;
      final diff = _compressOriginalSize > 0
          ? (((_compressOriginalSize - newSize) / _compressOriginalSize) * 100).round()
          : 0;

      _showResultDialog(
        filePath: outPath,
        title: 'تم ضغط الـ PDF بنجاح',
        subtitle:
            'الحجم قبل الضغط: ${formatFileSize(_compressOriginalSize)}\nالحجم بعد الضغط: ${formatFileSize(newSize)} (وفرت $diff%)\nالملف جاهز للإرسال والمشاركة.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الضغط: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: IMPORT LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _importExternalPdfOrImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ استيراد الملفات المختارة وتحويل الصفحات...';
    });

    try {
      const storage = LocalMediaStorageService();
      final pagesDir = await storage.pagesDirectory();
      final docsDir = await storage.documentsDirectory();
      final now = DateTime.now();
      final docId = 'imp_${now.millisecondsSinceEpoch}';
      final importedPages = <ScannedPage>[];

      for (final pf in result.files) {
        final filePath = pf.path;
        if (filePath == null) continue;
        final ext = p.extension(filePath).toLowerCase();

        if (ext == '.pdf') {
          final pdfBytes = await File(filePath).readAsBytes();
          var pageIdx = 0;
          await for (final raster in Printing.raster(pdfBytes, dpi: 180)) {
            final pngBytes = await raster.toPng();
            final decoded = img.decodePng(pngBytes);
            if (decoded != null) {
              final jpgBytes = img.encodeJpg(decoded, quality: 90);
              final pagePath = p.join(
                pagesDir.path,
                '${docId}_pdfp_${pageIdx}_${DateTime.now().microsecondsSinceEpoch}.jpg',
              );
              await File(pagePath).writeAsBytes(jpgBytes, flush: true);
              importedPages.add(
                ScannedPage(
                  imagePath: pagePath,
                  originalImagePath: pagePath,
                  filterName: 'original',
                  paperSize: DocumentPaperSize.a4,
                ),
              );
              pageIdx++;
            }
          }
        } else {
          final rawBytes = await File(filePath).readAsBytes();
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            final jpgBytes = img.encodeJpg(decoded, quality: 90);
            final pagePath = p.join(
              pagesDir.path,
              '${docId}_img_${importedPages.length}_${DateTime.now().microsecondsSinceEpoch}.jpg',
            );
            await File(pagePath).writeAsBytes(jpgBytes, flush: true);
            importedPages.add(
              ScannedPage(
                imagePath: pagePath,
                originalImagePath: pagePath,
                filterName: 'original',
                paperSize: DocumentPaperSize.a4,
              ),
            );
          }
        }
      }

      if (importedPages.isEmpty) {
        throw Exception('لم يتم العثور على صفحات صالحة للاستيراد.');
      }

      final baseTitle = stripFileExtension(result.files.first.name);
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final pdfBytes = await pdfBuilder.buildPdf(
        imagePaths: importedPages.map((e) => e.imagePath).toList(),
        paperSizes: importedPages.map((e) => e.paperSize).toList(),
      );
      final outPdfPath = p.join(docsDir.path, '${docId}_$baseTitle.pdf');
      await File(outPdfPath).writeAsBytes(pdfBytes, flush: true);

      final newDoc = PendingUpload(
        id: docId,
        filePath: outPdfPath,
        fileName: '$baseTitle.pdf',
        fileType: 'pdf',
        createdAt: now,
        status: 'saved',
        pageCount: importedPages.length,
        thumbnailPath: importedPages.first.imagePath,
        pages: importedPages,
      );

      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .addDocument(newDoc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم استيراد "$baseTitle" (${importedPages.length} صفحة) وإضافته للمكتبة بنجاح!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الاستيراد: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD METHOD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'أدوات PDF',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                labelColor: isDark ? Colors.white : Colors.black,
                unselectedLabelColor: const Color(0xFF8E8E93),
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                tabs: const [
                  Tab(text: 'دمج'),
                  Tab(text: 'تقسيم'),
                  Tab(text: 'ضغط'),
                  Tab(text: 'استيراد'),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMergeTab(palette),
                    _buildSplitTab(palette),
                    _buildCompressTab(palette),
                    _buildImportTab(palette),
                  ],
                ),
                if (_isWorking)
                  Container(
                    color: Colors.black45,
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? const Color(0xFF1C1C1E)
                                    : Colors.white)
                                .withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.black.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(palette.accent),
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _statusMessage.isNotEmpty
                                    ? _statusMessage
                                    : 'جارٍ المعالجة...',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
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
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 1 VIEW: MERGE
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMergeTab(AppThemePalette palette) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Source selection buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.file_upload_rounded),
                label: const Text('إضافة ملفات من الهاتف'),
                onPressed: _addExternalFilesToMerge,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.folder_special_rounded),
                label: const Text('إضافة من المكتبة'),
                onPressed: _addLibraryDocToMerge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_mergeItems.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.call_merge_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'لم تختر أي ملفات للدمج بعد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 4),
                Text(
                  'اختر ملفين أو أكثر من ذاكرة الهاتف أو مستندات المكتبة لدمجهم في ملف PDF واحد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الملفات المختارة (${_mergeItems.length}) - يمكنك السحب لإعادة الترتيب:',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              TextButton(
                onPressed: () => setState(() => _mergeItems.clear()),
                child: const Text('مسح الكل', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _mergeItems.length,
            onReorderItem: (oldIdx, newIdx) {
              setState(() {
                final item = _mergeItems.removeAt(oldIdx);
                _mergeItems.insert(newIdx, item);
              });
            },
            itemBuilder: (_, idx) {
              final it = _mergeItems[idx];
              return Card(
                key: ValueKey(it.id),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF9333EA).withValues(alpha: 0.12),
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9333EA),
                      ),
                    ),
                  ),
                  title: Text(
                    it.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${it.isPdf ? "ملف PDF" : "صورة"} • ${formatFileSize(it.sizeBytes)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.red),
                        onPressed: () => setState(() => _mergeItems.removeAt(idx)),
                      ),
                      const Icon(Icons.drag_handle_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Output Title
          TextField(
            controller: _mergeTitleCtrl,
            decoration: InputDecoration(
              labelText: 'اسم ملف الـ PDF المدمج الناتج',
              prefixIcon: const Icon(Icons.edit_note_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          // Compression Selector
          DropdownButtonFormField<PdfCompressionPreset>(
            initialValue: _mergeCompression,
            decoration: InputDecoration(
              labelText: 'ضغط حجم الملف المدمج',
              prefixIcon: const Icon(Icons.compress_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: PdfCompressionPreset.values
                .map((p) => DropdownMenuItem(value: p, child: Text(p.labelAr)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _mergeCompression = v);
            },
          ),
          const SizedBox(height: 20),

          // Merge Action Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF9333EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.call_merge_rounded),
            label: Text(
              'دمج (${_mergeItems.length}) ملفات وتوليد PDF جديد',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            onPressed: _mergeItems.length >= 2 ? _executeMerge : null,
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 2 VIEW: SPLIT & EXTRACT
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSplitTab(AppThemePalette palette) {
    final hasDoc = _splitPdfPath != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Select source
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.file_open_rounded),
                label: const Text('اختيار PDF من الهاتف'),
                onPressed: _pickExternalPdfForSplit,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.folder_shared_rounded),
                label: const Text('اختيار من المكتبة'),
                onPressed: _pickLibraryDocForSplit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (hasDoc) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF0D9488),
                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _splitPdfTitle ?? 'مستند PDF',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'إجمالي الصفحات: $_splitTotalPages صفحة',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                  onPressed: () => setState(() => _splitPdfPath = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            'طريقة التقسيم والاستخراج:',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),

          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('استخراج نطاق صفحات'),
                icon: Icon(Icons.filter_none_rounded),
              ),
              ButtonSegment(
                value: true,
                label: Text('فصل كل صفحة كملف مستقل'),
                icon: Icon(Icons.call_split_rounded),
              ),
            ],
            selected: {_splitEveryPage},
            onSelectionChanged: (s) => setState(() => _splitEveryPage = s.first),
          ),
          const SizedBox(height: 16),

          if (!_splitEveryPage) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _splitFromCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'من صفحة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _splitToCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'إلى صفحة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'الحد الأقصى المتاح: $_splitTotalPages صفحة',
              style: const TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 24),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF0D9488),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.call_split_rounded),
            label: Text(
              _splitEveryPage
                  ? 'فصل جميع الصفحات ($_splitTotalPages ملف) وحفظهم في المكتبة'
                  : 'استخراج النطاق المحدد وحفظه في المكتبة',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            onPressed: _executeSplit,
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.call_split_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'لم تختر ملف PDF بعد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 4),
                Text(
                  'اختر ملف PDF من ذاكرة الهاتف أو من مكتبة التطبيق لاستخراج صفحات محددة منه أو فصل كل صفحة على حدة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 3 VIEW: TARGET-SIZE COMPRESSOR
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildCompressTab(AppThemePalette palette) {
    final hasDoc = _compressPdfPath != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.file_open_rounded),
                label: const Text('اختيار PDF من الهاتف'),
                onPressed: _pickExternalPdfForCompress,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.folder_shared_rounded),
                label: const Text('اختيار من المكتبة'),
                onPressed: _pickLibraryDocForCompress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (hasDoc) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF4F46E5),
                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _compressPdfTitle ?? 'مستند PDF',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'الحجم الحالي: ${formatFileSize(_compressOriginalSize)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                  onPressed: () => setState(() => _compressPdfPath = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            'اختر الحجم المستهدف المطلوب:',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),

          Column(
            children: <PdfCompressionPreset>[
              PdfCompressionPreset.under200kb,
              PdfCompressionPreset.under500kb,
              PdfCompressionPreset.under1mb,
              PdfCompressionPreset.under2mb,
              PdfCompressionPreset.manual,
            ].map((p) {
              final isSel = _compressPreset == p;
              return Card(
                elevation: isSel ? 2 : 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSel
                        ? const Color(0xFF4F46E5)
                        : Colors.grey.withValues(alpha: 0.2),
                    width: isSel ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSel
                        ? const Color(0xFF4F46E5)
                        : Colors.grey.withValues(alpha: 0.15),
                    foregroundColor: isSel ? Colors.white : Colors.blueGrey,
                    child: const Icon(Icons.compress_rounded, size: 20),
                  ),
                  title: Text(
                    p.labelAr,
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  trailing: isSel
                      ? const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF4F46E5))
                      : null,
                  onTap: () => setState(() => _compressPreset = p),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.compress_rounded),
            label: Text(
              'ضغط الـ PDF ليصل إلى (${_compressPreset.labelAr})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            onPressed: _executeCompress,
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.compress_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'لم تختر ملف PDF للضغط بعد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 4),
                Text(
                  'اختر ملف PDF من ذاكرة الهاتف أو من مكتبة التطبيق لتقليص حجمه مع الحفاظ على وضوح الخطوط وجودة القراءة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 4 VIEW: IMPORT & OCR
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildImportTab(AppThemePalette palette) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.file_download_rounded, color: Color(0xFF059669), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'استيراد ملفات PDF خارجية أو صور من WhatsApp أو التنزيلات وتحويلها إلى مستندات ممسوحة ضوئياً قابلة للبحث والـ OCR والتحرير.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const Icon(Icons.drive_folder_upload_rounded,
                  size: 56, color: Color(0xFF059669)),
              const SizedBox(height: 14),
              const Text(
                'استيراد مستند خارجي جديد',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'يدعم ملفات PDF المتعددة، أو صور JPG/PNG/WebP',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF059669),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.file_open_rounded),
                label: const Text(
                  'اختيار الملفات من ذاكرة الجهاز',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: _importExternalPdfOrImages,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
