import 'dart:io';

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

/// Phase 3.2: Free Offline PDF Tools Hub (Merge, Split, Compress to Target Size,
/// Reorder/Rotate/Extract Pages, and Import External PDF/Images).
class PdfToolsScreen extends ConsumerStatefulWidget {
  const PdfToolsScreen({super.key});

  @override
  ConsumerState<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends ConsumerState<PdfToolsScreen> {
  bool _isWorking = false;
  String _statusMessage = '';

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

  Future<void> _showMergeDocumentsSheet(List<PendingUpload> docs) async {
    if (docs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب توفر مستندين على الأقل في المكتبة لدمجهما.'),
        ),
      );
      return;
    }

    final selectedIds = <String>[docs[0].id, docs[1].id];
    final titleCtrl = TextEditingController(
      text: 'مستند_مدمج_${DateTime.now().millisecondsSinceEpoch % 10000}',
    );
    var compression = PdfCompressionPreset.none;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'دمج عدة مستندات في ملف PDF واحد',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستند المدمج',
                    prefixIcon: Icon(Icons.merge_type_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PdfCompressionPreset>(
                  initialValue: compression,
                  decoration: const InputDecoration(
                    labelText: 'ضغط الملف الناتج',
                    prefixIcon: Icon(Icons.compress_rounded),
                  ),
                  items: PdfCompressionPreset.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.labelAr),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModalState(() => compression = v);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'اختر المستندات المراد دمجها بالترتيب:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (_, idx) {
                      final d = docs[idx];
                      final isSel = selectedIds.contains(d.id);
                      final orderNum = selectedIds.indexOf(d.id) + 1;
                      return CheckboxListTile(
                        value: isSel,
                        title: Text(
                          stripFileExtension(d.fileName),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${formatPageCount(d.effectivePageCount)} ${isSel ? "• الترتيب: #$orderNum" : ""}',
                        ),
                        onChanged: (checked) {
                          setModalState(() {
                            if (checked == true) {
                              selectedIds.add(d.id);
                            } else {
                              selectedIds.remove(d.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: selectedIds.length < 2
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.call_merge_rounded),
                  label: Text('دمج (${selectedIds.length} مستندات) الآن'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ دمج المستندات المختارة...';
    });

    try {
      final mergedPages = <ScannedPage>[];
      for (final id in selectedIds) {
        final doc = docs.firstWhere((d) => d.id == id);
        mergedPages.addAll(doc.pages);
      }

      if (mergedPages.isEmpty) {
        throw Exception('لا توجد صفحات صالحة للدمج.');
      }

      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final pdfBytes = await pdfBuilder.buildPdf(
        imagePaths: mergedPages.map((p) => p.imagePath).toList(),
        paperSizes: mergedPages.map((p) => p.paperSize).toList(),
        options: PdfBuildOptions(compressionPreset: compression),
      );

      const storage = LocalMediaStorageService();
      final docsDir = await storage.documentsDirectory();
      final now = DateTime.now();
      final mergedId = 'mrg_${now.millisecondsSinceEpoch}';
      final cleanTitle = titleCtrl.text.trim().isEmpty
          ? 'مستند_مدمج'
          : titleCtrl.text.trim();
      final outPath = p.join(docsDir.path, '${mergedId}_$cleanTitle.pdf');
      await File(outPath).writeAsBytes(pdfBytes, flush: true);

      final mergedDoc = PendingUpload(
        id: mergedId,
        filePath: outPath,
        fileName: '$cleanTitle.pdf',
        fileType: 'pdf',
        createdAt: now,
        status: 'saved',
        pageCount: mergedPages.length,
        thumbnailPath: mergedPages.first.imagePath,
        pages: mergedPages,
      );

      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .addDocument(mergedDoc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إنشاء المستند المدمج "$cleanTitle" (${mergedPages.length} صفحة • ${formatFileSize(pdfBytes.length)}) بنجاح!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الدمج: $e')),
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

  Future<void> _showSplitDocumentDialog(PendingUpload doc) async {
    if (doc.pages.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا المستند يحتوي على صفحة واحدة فقط ولا يمكن تقسيمه.'),
        ),
      );
      return;
    }

    var splitEveryPage = false;
    final fromCtrl = TextEditingController(text: '1');
    final toCtrl = TextEditingController(text: '${doc.pages.length}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('تقسيم: ${stripFileExtension(doc.fileName)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('نطاق صفحات'),
                    icon: Icon(Icons.filter_none_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('فصل كل صفحة'),
                    icon: Icon(Icons.call_split_rounded),
                  ),
                ],
                selected: {splitEveryPage},
                onSelectionChanged: (s) =>
                    setDialogState(() => splitEveryPage = s.first),
              ),
              const SizedBox(height: 12),
              if (!splitEveryPage)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fromCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'من صفحة'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: toCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'إلى صفحة'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تقسيم الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ تقسيم المستند وإنشاء الملفات...';
    });

    try {
      const storage = LocalMediaStorageService();
      final docsDir = await storage.documentsDirectory();
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final baseName = stripFileExtension(doc.fileName);

      if (splitEveryPage) {
        for (var i = 0; i < doc.pages.length; i++) {
          final pg = doc.pages[i];
          final pdfBytes = await pdfBuilder.buildPdf(
            imagePaths: [pg.imagePath],
            paperSizes: [pg.paperSize],
          );
          final splitId = 'spl_${DateTime.now().millisecondsSinceEpoch}_$i';
          final title = '${baseName}_صفحة_${i + 1}';
          final outPath = p.join(docsDir.path, '${splitId}_$title.pdf');
          await File(outPath).writeAsBytes(pdfBytes, flush: true);

          await ref
              .read(pendingUploadsControllerProvider.notifier)
              .addDocument(
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
                'تم فصل ${doc.pages.length} صفحات في ملفات مستقلة بنجاح!',
              ),
            ),
          );
        }
      } else {
        final start =
            (int.tryParse(fromCtrl.text.trim()) ?? 1).clamp(1, doc.pages.length);
        final end = (int.tryParse(toCtrl.text.trim()) ?? doc.pages.length)
            .clamp(start, doc.pages.length);
        final subPages = doc.pages.sublist(start - 1, end);

        final pdfBytes = await pdfBuilder.buildPdf(
          imagePaths: subPages.map((e) => e.imagePath).toList(),
          paperSizes: subPages.map((e) => e.paperSize).toList(),
        );
        final splitId = 'spl_${DateTime.now().millisecondsSinceEpoch}';
        final title = '${baseName}_ص${start}_إلى_ص$end';
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
                pageCount: subPages.length,
                thumbnailPath: subPages.first.imagePath,
                pages: subPages,
              ),
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم استخراج "$title" بنجاح!')),
          );
        }
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

  Future<void> _showCompressDocumentDialog(PendingUpload doc) async {
    var preset = PdfCompressionPreset.under500kb;
    final originalSize = File(doc.filePath).existsSync()
        ? File(doc.filePath).lengthSync()
        : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('ضغط حجم: ${stripFileExtension(doc.fileName)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الحجم الحالي: ${formatFileSize(originalSize)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PdfCompressionPreset>(
                initialValue: preset,
                decoration: const InputDecoration(
                  labelText: 'اختر الحجم المستهدف',
                ),
                items: PdfCompressionPreset.values
                    .where((p) => p != PdfCompressionPreset.none)
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.labelAr),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => preset = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.compress_rounded),
              label: const Text('ضغط الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _statusMessage = 'جارٍ ضغط الملف للوصول إلى (${preset.labelAr})...';
    });

    try {
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final compressedBytes = await pdfBuilder.buildPdf(
        imagePaths: doc.pages.map((p) => p.imagePath).toList(),
        paperSizes: doc.pages.map((p) => p.paperSize).toList(),
        options: PdfBuildOptions(compressionPreset: preset),
      );

      final exportsDir =
          await const LocalMediaStorageService().exportsDirectory();
      final baseName = stripFileExtension(doc.fileName);
      final outPath = p.join(
        exportsDir.path,
        '${doc.id}_${baseName}_${preset.name}.pdf',
      );
      await File(outPath).writeAsBytes(compressedBytes, flush: true);

      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تم ضغط الـ PDF بنجاح!'),
            content: Text(
              'الحجم قبل الضغط: ${formatFileSize(originalSize)}\n'
              'الحجم بعد الضغط: ${formatFileSize(compressedBytes.length)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  OpenFilex.open(outPath);
                },
                child: const Text('فتح الملف'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Share.shareXFiles([XFile(outPath)]);
                },
                icon: const Icon(Icons.share_rounded),
                label: const Text('مشاركة'),
              ),
            ],
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final docs =
        ref.watch(pendingUploadsControllerProvider).valueOrNull ?? const [];
    final palette = context.appThemePalette;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'أدوات PDF الاحترافية المجانية',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Top Action Cards
              Row(
                children: [
                  Expanded(
                    child: _buildToolActionCard(
                      icon: Icons.file_open_rounded,
                      title: 'استيراد PDF / صور',
                      subtitle: 'من ذاكرة الهاتف للتحرير أو الـ OCR',
                      color: const Color(0xFF2563EB),
                      onTap: _importExternalPdfOrImages,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildToolActionCard(
                      icon: Icons.call_merge_rounded,
                      title: 'دمج ملفات PDF',
                      subtitle: 'دمج عدة مستندات في ملف واحد',
                      color: const Color(0xFF9333EA),
                      onTap: () => _showMergeDocumentsSheet(docs),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'اختر مستنداً من مكتبتك لتقسيمه أو ضغط حجمه:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  alignment: Alignment.center,
                  child: const Text(
                    'لا توجد مستندات في المكتبة حالياً. يمكنك استيراد ملف PDF خارجي من الزر أعلاه.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...docs.map((doc) {
                  final sizeBytes = File(doc.filePath).existsSync()
                      ? File(doc.filePath).lengthSync()
                      : 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: palette.accent.withValues(alpha: 0.14),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: palette.accent,
                        ),
                      ),
                      title: Text(
                        stripFileExtension(doc.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${formatPageCount(doc.effectivePageCount)} • ${formatFileSize(sizeBytes)}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.compress_rounded, size: 16),
                            label: const Text('ضغط الحجم'),
                            onPressed: () => _showCompressDocumentDialog(doc),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.call_split_rounded, size: 16),
                            label: const Text('تقسيم'),
                            onPressed: () => _showSplitDocumentDialog(doc),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
          if (_isWorking)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Card(
                margin: const EdgeInsets.all(32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
