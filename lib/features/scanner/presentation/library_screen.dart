import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/document_folder.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../data/document_search_service.dart';
import '../data/ocr_service.dart';
import '../data/office_exporter_service.dart';
import 'document_viewer_screen.dart';
import 'pdf_tools_screen.dart';
import 'scanner_session_screen.dart';
import 'signature_bottom_sheet.dart';
import 'vault_screen.dart';
import 'widgets/export_format_sheet.dart';

enum LibrarySortOption {
  newest('الأحدث أولاً', Icons.schedule_rounded),
  name('الاسم (أ - ي)', Icons.sort_by_alpha_rounded),
  size('الحجم (الأكبر)', Icons.data_usage_rounded);

  const LibrarySortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, DocumentSearchHit> _ocrSearchHits = const {};
  bool _isGridView = true;
  LibrarySortOption _sortOption = LibrarySortOption.newest;
  String? _activeFolderId;
  DateTime? _backgroundedAt;
  bool _isAppLockedOverlay = false;

  List<DocumentFolder> _folders = const [];
  bool _isLoadingFolders = true;

  final Set<String> _selectedDocIds = <String>{};
  bool get _isMultiSelectMode => _selectedDocIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFolders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialSecurityAndIntents();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _checkInitialSecurityAndIntents() async {
    final sec = ref.read(vaultSecurityServiceProvider);
    final settings = await sec.loadSettings();
    if (settings.appLockEnabled && settings.hasPinConfigured) {
      await _promptAppUnlock();
    }
    await _consumeSharedIncomingFiles();
  }

  Future<void> _onAppResumed() async {
    await _consumeSharedIncomingFiles();
    final bgTime = _backgroundedAt;
    if (bgTime == null) return;
    _backgroundedAt = null;

    final sec = ref.read(vaultSecurityServiceProvider);
    final settings = await sec.loadSettings();
    if (!settings.appLockEnabled || !settings.hasPinConfigured) return;

    final elapsed = DateTime.now().difference(bgTime);
    if (elapsed >= settings.autoLockTimeout.duration) {
      await _promptAppUnlock();
    }
  }

  Future<void> _promptAppUnlock() async {
    if (_isAppLockedOverlay || !mounted) return;
    setState(() => _isAppLockedOverlay = true);

    final sec = ref.read(vaultSecurityServiceProvider);
    final settings = await sec.loadSettings();
    if (settings.biometricsEnabled) {
      final ok = await sec.authenticateWithBiometrics(
        reason: 'الرجاء تأكيد هويتك لفتح التطبيق',
      );
      if (ok && mounted) {
        setState(() => _isAppLockedOverlay = false);
        return;
      }
    }

    if (!mounted) return;
    final pinCtrl = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('التطبيق مقفل للحماية'),
            content: TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'أدخل الرمز السري',
                errorText: err,
              ),
            ),
            actions: [
              if (settings.biometricsEnabled)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await sec.authenticateWithBiometrics();
                    if (ok && ctx.mounted) Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('البصمة'),
                ),
              FilledButton(
                onPressed: () async {
                  final ok = await sec.verifyPin(pinCtrl.text.trim());
                  if (ok && ctx.mounted) {
                    Navigator.of(ctx).pop();
                  } else {
                    setDialogState(() => err = 'الرمز غير صحيح');
                  }
                },
                child: const Text('فتح'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => _isAppLockedOverlay = false);
    }
  }

  Future<void> _consumeSharedIncomingFiles() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.yourname.docscanner/scanner');
      final rawList =
          await channel.invokeMethod<List<dynamic>>('consumeIncomingFiles');
      if (rawList == null || rawList.isEmpty) return;

      const storage = LocalMediaStorageService();
      final pagesDir = await storage.pagesDirectory();
      final docsDir = await storage.documentsDirectory();
      final now = DateTime.now();
      final docId = 'sh_${now.millisecondsSinceEpoch}';
      final importedPages = <ScannedPage>[];

      for (final item in rawList.whereType<String>()) {
        final f = File(item);
        if (!await f.exists()) continue;
        final ext = p.extension(item).toLowerCase();
        if (ext == '.pdf') {
          final pdfBytes = await f.readAsBytes();
          var idx = 0;
          await for (final raster in Printing.raster(pdfBytes, dpi: 180)) {
            final png = await raster.toPng();
            final decoded = img.decodePng(png);
            if (decoded != null) {
              final jpg = img.encodeJpg(decoded, quality: 90);
              final pagePath = p.join(pagesDir.path, '${docId}_p$idx.jpg');
              await File(pagePath).writeAsBytes(jpg, flush: true);
              importedPages.add(ScannedPage(imagePath: pagePath, originalImagePath: pagePath));
              idx++;
            }
          }
        } else {
          final decoded = img.decodeImage(await f.readAsBytes());
          if (decoded != null) {
            final jpg = img.encodeJpg(decoded, quality: 90);
            final pagePath =
                p.join(pagesDir.path, '${docId}_img${importedPages.length}.jpg');
            await File(pagePath).writeAsBytes(jpg, flush: true);
            importedPages.add(ScannedPage(imagePath: pagePath, originalImagePath: pagePath));
          }
        }
      }

      if (importedPages.isEmpty) return;
      final title = 'ملف_مستورد_${now.millisecondsSinceEpoch % 10000}';
      final pdfBytes = await ref.read(pdfBuilderServiceProvider).buildPdf(
            imagePaths: importedPages.map((e) => e.imagePath).toList(),
            paperSizes: importedPages.map((e) => e.paperSize).toList(),
          );
      final pdfPath = p.join(docsDir.path, '${docId}_$title.pdf');
      await File(pdfPath).writeAsBytes(pdfBytes, flush: true);

      await ref.read(pendingUploadsControllerProvider.notifier).addDocument(
            PendingUpload(
              id: docId,
              filePath: pdfPath,
              fileName: '$title.pdf',
              fileType: 'pdf',
              createdAt: now,
              status: 'saved',
              pageCount: importedPages.length,
              thumbnailPath: importedPages.first.imagePath,
              pages: importedPages,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم استيراد "$title" (${importedPages.length} صفحة) تلقائياً!')),
        );
      }
    } catch (_) {}
  }

  Future<void> _onSearchQueryChanged(String val) async {
    setState(() => _searchQuery = val);
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() => _ocrSearchHits = const {});
      return;
    }
    final hits = await ref.read(documentSearchServiceProvider).search(trimmed);
    if (mounted && _searchQuery.trim() == trimmed) {
      setState(() => _ocrSearchHits = hits);
    }
  }

  Future<void> _loadFolders() async {
    final service = ref.read(documentFolderServiceProvider);
    final loaded = await service.loadFolders();
    if (!mounted) return;
    setState(() {
      _folders = loaded;
      _isLoadingFolders = false;
    });
  }

  DocumentFolder? get _activeFolder {
    if (_activeFolderId == null) return null;
    return _findFolderById(_activeFolderId);
  }

  DocumentFolder? _findFolderById(String? folderId) {
    if (folderId == null || folderId.isEmpty) return null;
    for (final f in _folders) {
      if (f.id == folderId) return f;
    }
    return null;
  }

  Future<void> _startNewScanSession() async {
    await ref.read(scanSessionControllerProvider.notifier).startNewEmptySession();
    if (!mounted) return;
    final savedDoc = await Navigator.of(context).push<PendingUpload>(
      MaterialPageRoute(
        builder: (_) => ScannerSessionScreen(
          initialTargetFolderId: _activeFolderId,
        ),
      ),
    );
    if (!mounted) return;
    await ref.read(pendingUploadsControllerProvider.notifier).refresh();
    await _loadFolders();
    if (savedDoc != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ "${savedDoc.title}" في المكتبة بنجاح'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();
    final palette = context.appThemePalette;
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إنشاء مجلد جديد',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'اسم المجلد',
            hintText: 'مثال: عقود العمل، الفواتير، الهويات...',
            prefixIcon: Icon(Icons.create_new_folder_rounded, color: palette.accent),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text('إنشاء المجلد'),
          ),
        ],
      ),
    );

    if (createdName == null || createdName.isEmpty || !mounted) return;
    try {
      await ref.read(documentFolderServiceProvider).createFolder(createdName);
      await _loadFolders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _renameFolderDialog(DocumentFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إعادة تسمية المجلد',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'الاسم الجديد',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      await ref
          .read(documentFolderServiceProvider)
          .renameFolder(folder.id, newName);
      await _loadFolders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteFolderDialog(DocumentFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'حذف المجلد؟',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'سيتم حذف المجلد "${folder.name}" وإرجاع المستندات التي بداخله إلى المكتبة الرئيسية (لن يتم حذف المستندات).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appThemePalette.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف المجلد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final docs =
        ref.read(pendingUploadsControllerProvider).valueOrNull ?? const [];
    for (final doc in docs) {
      if (doc.folderId == folder.id) {
        await ref
            .read(pendingUploadsControllerProvider.notifier)
            .assignToFolder(doc.id, null);
      }
    }
    await ref.read(documentFolderServiceProvider).deleteFolder(folder.id);
    if (_activeFolderId == folder.id) {
      _activeFolderId = null;
    }
    await _loadFolders();
  }

  Future<void> _reorderFolders(
    DocumentFolder dragged,
    DocumentFolder target,
  ) async {
    if (dragged.id == target.id) return;
    final list = [..._folders];
    final oldIdx = list.indexWhere((f) => f.id == dragged.id);
    final newIdx = list.indexWhere((f) => f.id == target.id);
    if (oldIdx == -1 || newIdx == -1) return;
    final item = list.removeAt(oldIdx);
    list.insert(newIdx, item);
    setState(() => _folders = list);
    await ref.read(documentFolderServiceProvider).saveFoldersOrder(list);
  }

  Future<void> _moveDocToFolder(
    PendingUpload doc,
    DocumentFolder? folder,
  ) async {
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .assignToFolder(doc.id, folder?.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          folder == null
              ? 'تم إخراج "${doc.title}" إلى المكتبة الرئيسية'
              : 'تم نقل "${doc.title}" إلى مجلد "${folder.name}"',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showMoveToFolderSheet(List<PendingUpload> docs) async {
    final palette = context.appThemePalette;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                docs.length == 1
                    ? 'نقل "${docs.first.title}" إلى مجلد'
                    : 'نقل ${docs.length} مستندات إلى مجلد',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Icon(Icons.home_rounded, color: palette.accent),
                title: const Text(
                  'المكتبة الرئيسية (بدون مجلد)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  for (final d in docs) {
                    await _moveDocToFolder(d, null);
                  }
                  setState(() => _selectedDocIds.clear());
                },
              ),
              const Divider(height: 1),
              if (_folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'لا توجد مجلدات بعد. أنشئ مجلداً جديداً لتنظيم مستنداتك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _folders.length,
                    itemBuilder: (_, idx) {
                      final folder = _folders[idx];
                      return ListTile(
                        leading: Icon(
                          Icons.folder_rounded,
                          color: palette.warning,
                        ),
                        title: Text(
                          folder.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          for (final d in docs) {
                            await _moveDocToFolder(d, folder);
                          }
                          setState(() => _selectedDocIds.clear());
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _createFolderDialog();
                },
                icon: const Icon(Icons.create_new_folder_rounded),
                label: const Text('إنشاء مجلد جديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameDocumentDialog(PendingUpload doc) async {
    final controller = TextEditingController(text: doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إعادة تسمية المستند',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'اسم المستند',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) Navigator.pop(ctx, val);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || !mounted) return;
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .renameDocument(doc.id, newTitle);
  }

  Future<void> _exportDocumentSheet(PendingUpload doc) async {
    final selection = await showSaveAndExportBottomSheet(
      context: context,
      initialName: doc.title,
      pageCount: doc.pageCount,
      title: 'تصدير وتحويل المستند',
    );
    if (selection == null || !mounted) return;
    await executeDocumentExportWithUi(
      context: context,
      ref: ref,
      document: doc,
      selection: selection,
    );
  }

  Future<void> _exportToExcelDirectly(PendingUpload doc) async {
    await executeDocumentExportWithUi(
      context: context,
      ref: ref,
      document: doc,
      format: ExportFormat.xlsx,
    );
  }

  Future<void> _reopenDocumentForEditing(PendingUpload doc) async {
    if (doc.pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا المستند يحتوي على ملف PDF النهائي الجاهز للعرض.'),
        ),
      );
      return;
    }
    await ref
        .read(scanSessionControllerProvider.notifier)
        .loadSavedDocumentIntoSession(doc);
    if (!mounted) return;
    await Navigator.of(context).push<PendingUpload>(
      MaterialPageRoute(
        builder: (_) => ScannerSessionScreen(
          initialTargetFolderId: doc.folderId,
        ),
      ),
    );
    if (!mounted) return;
    await ref.read(pendingUploadsControllerProvider.notifier).refresh();
  }

  Future<void> _showDocumentOptionsMenu(PendingUpload doc) async {
    final palette = context.appThemePalette;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Text(
                doc.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPageCount(doc.pageCount)} • ${formatFileSize(doc.fileSizeBytes)} • ${formatDate(doc.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.visibility_rounded, color: palette.accent),
                title: const Text(
                  'معاينة وعرض المستند',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerScreen(document: doc),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.transform_rounded,
                  color: Color(0xFF2B579A),
                ),
                title: const Text(
                  'حفظ / تحويل (PDF • Word .docx • Excel .xlsx)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'تحويل بالذكاء الاصطناعي وتعرف النصوص OCR بدون إنترنت',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportDocumentSheet(doc);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.table_chart_rounded,
                  color: Color(0xFF059669),
                ),
                title: const Text(
                  'تحويل الجداول إلى Excel احترافي (.xlsx)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'إعادة بناء شبكة الجداول والخلايا وتنسيق الأرقام والعربي RTL',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportToExcelDirectly(doc);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.document_scanner_rounded,
                  color: Color(0xFF9333EA),
                ),
                title: const Text(
                  'استخراج النص وتسمية ذكية (Tesseract OCR)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'نسخ النص العربي/الإنجليزي، اقتراح عنوان ذكي، وفهرسة للبحث الفوري',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showOcrAndSmartRenameDialog(doc);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.enhanced_encryption_rounded,
                  color: Color(0xFF059669),
                ),
                title: const Text(
                  'نقل إلى الخزنة السرية المشفرة (AES-256-GCM)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'تشفير الملف فعلياً على القرص وإخفاؤه من المكتبة والبحث',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveSingleDocToSecretVault(doc);
                },
              ),
              if (doc.pages.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.edit_document,
                    color: palette.success,
                  ),
                  title: const Text(
                    'تعديل الصفحات / إضافة صفحة / توقيع',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _reopenDocumentForEditing(doc);
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.drive_file_rename_outline_rounded,
                  color: palette.accent,
                ),
                title: const Text(
                  'إعادة تسمية المستند',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameDocumentDialog(doc);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.drive_file_move_rounded,
                  color: palette.warning,
                ),
                title: const Text(
                  'نقل إلى مجلد...',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoveToFolderSheet([doc]);
                },
              ),
              ListTile(
                leading: Icon(Icons.share_rounded, color: palette.accent),
                title: const Text(
                  'مشاركة الملف',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Share.shareXFiles(
                    [XFile(doc.filePath)],
                    subject: doc.title,
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.print_rounded, color: palette.accent),
                title: const Text(
                  'طباعة مباشرة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = File(doc.filePath);
                  if (await file.exists()) {
                    final bytes = await file.readAsBytes();
                    await Printing.layoutPdf(
                      onLayout: (_) async => bytes,
                      name: doc.fileName,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: palette.danger,
                ),
                title: Text(
                  'حذف المستند',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.danger,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(pendingUploadsControllerProvider.notifier)
                      .removeById(doc.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOcrAndSmartRenameDialog(PendingUpload doc) async {
    final imagePaths = doc.pages
        .map((p) => p.imagePath)
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();
    if (imagePaths.isEmpty &&
        doc.effectiveThumbnailPath != null &&
        File(doc.effectiveThumbnailPath!).existsSync()) {
      imagePaths.add(doc.effectiveThumbnailPath!);
    }
    if (imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد صور صفحات لاستخراج النص منها.')),
      );
      return;
    }

    final statusNotifier = ValueNotifier<String>(
      'جارٍ تشغيل محرك Tesseract OCR (عربي + إنجليزي)...',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: statusNotifier,
          builder: (_, msg, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final ocrService = ref.read(ocrServiceProvider);
      final ocrResult = await ocrService.recognizeDocument(
        documentId: doc.id,
        imagePaths: imagePaths,
        languageMode: OcrLanguageMode.arabicEnglish,
        onProgress: (m) => statusNotifier.value = m,
      );

      await ref.read(documentSearchServiceProvider).indexDocumentOcr(
            documentId: doc.id,
            title: doc.title,
            fullText: ocrResult.fullText,
            smartTitle: ocrResult.suggestedTitle,
          );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final suggested = ocrResult.suggestedTitle;
      final fullText = ocrResult.fullText.trim().isEmpty
          ? 'لم يتم العثور على نص مقروء واضح في هذه الصفحة.'
          : ocrResult.fullText.trim();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetCtx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'النص المستخرج بـ OCR (${doc.title})',
                style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (suggested != null && suggested.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF9333EA),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'العنوان الذكي المقترح: $suggested',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () async {
                          await ref
                              .read(pendingUploadsControllerProvider.notifier)
                              .renameDocument(doc.id, suggested.trim());
                          if (sheetCtx.mounted) {
                            Navigator.of(sheetCtx).pop();
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تمت إعادة تسمية المستند إلى "$suggested"!',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('اعتماد الاسم'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(sheetCtx).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      fullText,
                      style: const TextStyle(height: 1.6, fontSize: 13.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ النص إلى الحافظة!'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('نسخ النص'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Text('إغلاق'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استخراج النص: $e')),
        );
      }
    }
  }

  Future<void> _moveSingleDocToSecretVault(PendingUpload doc) async {
    final sec = ref.read(vaultSecurityServiceProvider);
    final settings = await sec.loadSettings();
    if (!settings.hasPinConfigured) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
      );
      return;
    }

    try {
      await sec.moveDocumentToVault(doc);
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .deleteDocument(doc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تشفير "${doc.title}" بمعيار AES-256-GCM ونقله للخزنة السرية!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر النقل للخزنة: $e')),
        );
      }
    }
  }

  Future<void> _showBackupRestoreDialog(List<PendingUpload> allDocs) async {
    final passwordCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'النسخ الاحتياطي والاستعادة الشاملة (.ZIP)',
                style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'تصدير كل المستندات والمجلدات وفهرس البحث في ملف .zip محلي أو استعادتها ودمجها بدون تكرار.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور لتشفير النسخة الاحتياطية (اختياري AES-256)',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  Navigator.of(sheetCtx).pop();
                  try {
                    final backupSvc = ref.read(backupRestoreServiceProvider);
                    final zipPath = await backupSvc.createBackupZip(
                      documents: allDocs,
                      folders: _folders,
                      password: pwd.isEmpty ? null : pwd,
                    );
                    if (mounted) {
                      await Share.shareXFiles(
                        [XFile(zipPath)],
                        subject: 'نسخة احتياطية للمستندات',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل إنشاء النسخة الاحتياطية: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.archive_rounded),
                label: Text('تصدير ومشاركة نسخة احتياطية (${allDocs.length} مستند)'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  Navigator.of(sheetCtx).pop();
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['zip'],
                  );
                  final path = picked?.files.firstOrNull?.path;
                  if (path == null) return;

                  try {
                    final backupSvc = ref.read(backupRestoreServiceProvider);
                    final res = await backupSvc.restoreFromBackupFile(
                      zipFilePath: path,
                      currentDocuments: allDocs,
                      currentFolders: _folders,
                      password: pwd.isEmpty ? null : pwd,
                    );
                    await ref
                        .read(documentFolderServiceProvider)
                        .saveFolders(res.mergedFolders);
                    await ref
                        .read(pendingUploadsControllerProvider.notifier)
                        .replaceAllDocuments(res.mergedDocuments);
                    await _loadFolders();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تمت الاستعادة بنجاح! (${res.stats.restoredDocuments} مستند جديد، ${res.stats.restoredFolders} مجلد، تم تخطي ${res.stats.skippedDuplicates} مكرر)',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل استعادة النسخة: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.restore_page_rounded),
                label: const Text('استعادة ودمج من ملف .ZIP'),
              ),
            ],
          ),
        );
      },
    );
  }

  List<PendingUpload> _filterAndSortDocuments(List<PendingUpload> allDocs) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = allDocs.where((doc) {
      if (_activeFolderId != null) {
        if (doc.folderId != _activeFolderId) return false;
      } else {
        // In root view: only show unfiled documents unless an active search query matches
        if (query.isEmpty) {
          if (doc.folderId != null && doc.folderId!.isNotEmpty) {
            return false;
          }
        }
      }
      if (query.isNotEmpty) {
        final matchesMeta = doc.title.toLowerCase().contains(query) ||
            doc.fileName.toLowerCase().contains(query);
        final matchesOcr = _ocrSearchHits.containsKey(doc.id);
        return matchesMeta || matchesOcr;
      }
      return true;
    }).toList();

    switch (_sortOption) {
      case LibrarySortOption.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LibrarySortOption.name:
        filtered.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case LibrarySortOption.size:
        filtered.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
    }
    return filtered;
  }

  Future<void> _deleteSelectedDocuments() async {
    if (_selectedDocIds.isEmpty) return;
    final count = _selectedDocIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'حذف المستندات المحددة؟',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text('هل تريد حذف $count مستندات نهائياً من الجهاز؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appThemePalette.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ids = _selectedDocIds.toList();
    setState(() => _selectedDocIds.clear());
    await ref.read(pendingUploadsControllerProvider.notifier).removeMultiple(ids);
  }

  Future<void> _shareSelectedDocuments(List<PendingUpload> allDocs) async {
    final selected = allDocs
        .where((d) => _selectedDocIds.contains(d.id))
        .map((d) => XFile(d.filePath))
        .toList();
    if (selected.isEmpty) return;
    setState(() => _selectedDocIds.clear());
    await Share.shareXFiles(selected);
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(pendingUploadsControllerProvider);
    final allDocs = docsAsync.valueOrNull ?? const <PendingUpload>[];
    final visibleDocs = _filterAndSortDocuments(allDocs);
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFolder = _activeFolder;

    return Scaffold(
      appBar: _isMultiSelectMode
          ? AppBar(
              leading: IconButton(
                onPressed: () => setState(() => _selectedDocIds.clear()),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إلغاء التحديد',
              ),
              title: Text('تم تحديد ${_selectedDocIds.length}'),
              actions: [
                IconButton(
                  tooltip: 'نقل إلى مجلد',
                  onPressed: () {
                    final selected = allDocs
                        .where((d) => _selectedDocIds.contains(d.id))
                        .toList();
                    _showMoveToFolderSheet(selected);
                  },
                  icon: const Icon(Icons.drive_file_move_rounded),
                ),
                IconButton(
                  tooltip: 'مشاركة المحدد',
                  onPressed: () => _shareSelectedDocuments(allDocs),
                  icon: const Icon(Icons.share_rounded),
                ),
                IconButton(
                  tooltip: 'حذف المحدد',
                  onPressed: _deleteSelectedDocuments,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.danger,
                  ),
                ),
              ],
            )
          : AppBar(
              leading: activeFolder != null
                  ? IconButton(
                      onPressed: () => setState(() => _activeFolderId = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'العودة للمكتبة الرئيسية',
                    )
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.document_scanner_rounded,
                            color: palette.accent,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeFolder != null
                        ? activeFolder.name
                        : 'الماسح الضوئي الذكي',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    activeFolder != null
                        ? '${visibleDocs.length} مستند داخل المجلد'
                        : '${allDocs.length} مستند محفوظ محلياً • بدون إنترنت 100%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: _isGridView ? 'عرض كقائمة' : 'عرض كشبكة',
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  icon: Icon(
                    _isGridView
                        ? Icons.view_agenda_rounded
                        : Icons.grid_view_rounded,
                  ),
                ),
                PopupMenuButton<LibrarySortOption>(
                  tooltip: 'ترتيب المستندات',
                  initialValue: _sortOption,
                  onSelected: (opt) => setState(() => _sortOption = opt),
                  icon: const Icon(Icons.sort_rounded),
                  itemBuilder: (_) => LibrarySortOption.values
                      .map(
                        (opt) => PopupMenuItem(
                          value: opt,
                          child: Row(
                            children: [
                              Icon(
                                opt.icon,
                                size: 18,
                                color: opt == _sortOption
                                    ? palette.accent
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                opt.label,
                                style: TextStyle(
                                  fontWeight: opt == _sortOption
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                IconButton(
                  tooltip: 'تبديل الوضع الليلي/النهاري',
                  onPressed: () => ref
                      .read(userPreferencesControllerProvider.notifier)
                      .toggleDarkMode(),
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 68,
        height: 68,
        child: FloatingActionButton(
          onPressed: _startNewScanSession,
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          elevation: 6,
          shape: const CircleBorder(),
          tooltip: 'مسح مستند جديد',
          child: const Icon(Icons.camera_alt_rounded, size: 30),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _BottomBarActionButton(
                  icon: Icons.library_books_rounded,
                  label: 'المكتبة',
                  isActive: _activeFolderId == null,
                  onTap: () => setState(() => _activeFolderId = null),
                ),
                const SizedBox(width: 8),
                _BottomBarActionButton(
                  icon: Icons.create_new_folder_rounded,
                  label: 'مجلد جديد',
                  isActive: false,
                  onTap: _createFolderDialog,
                ),
              ],
            ),
            Row(
              children: [
                _BottomBarActionButton(
                  icon: Icons.draw_rounded,
                  label: 'التوقيعات',
                  isActive: false,
                  onTap: () async {
                    final storage = ref.read(signatureStorageServiceProvider);
                    await showSignatureBottomSheet(
                      context: context,
                      storageService: storage,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _BottomBarActionButton(
                  icon: Icons.transform_rounded,
                  label: 'تصدير سريع',
                  isActive: false,
                  onTap: () {
                    if (visibleDocs.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('امسح مستنداً أولاً لتصديره إلى PDF أو Word أو Excel'),
                        ),
                      );
                      return;
                    }
                    _exportDocumentSheet(visibleDocs.first);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsControllerProvider.notifier).refresh();
          await _loadFolders();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Search Bar (Title + Full-Text SQLite FTS4 OCR Search) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المستند أو داخل نصوص الصفحات (OCR)...',
                    prefixIcon: Icon(Icons.search_rounded, color: palette.accent),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _onSearchQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF1C1C1E)
                        : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Highlighted OCR Snippets when searching inside pages ──
            if (_searchQuery.trim().isNotEmpty && _ocrSearchHits.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تطابقات داخل نصوص الصفحات (OCR FTS):',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._ocrSearchHits.values.take(3).map(
                            (hit) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${hit.title}: "${hit.snippet}"',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),

            // ── Quick Feature Pills: PDF Tools, Secret Vault, ZIP Backup ──
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(
                        Icons.handyman_rounded,
                        size: 17,
                        color: Color(0xFF2563EB),
                      ),
                      label: const Text(
                        'أدوات PDF (دمج • تقسيم • ضغط • استيراد)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PdfToolsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(
                        Icons.enhanced_encryption_rounded,
                        size: 17,
                        color: Color(0xFF059669),
                      ),
                      label: const Text(
                        'الخزنة السرية والحماية (AES-256)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const VaultScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(
                        Icons.folder_zip_rounded,
                        size: 17,
                        color: Color(0xFF9333EA),
                      ),
                      label: const Text(
                        'نسخ احتياطي واستعادة (.ZIP)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      onPressed: () => _showBackupRestoreDialog(allDocs),
                    ),
                  ],
                ),
              ),
            ),

            // ── Folders Section (when in root view) ──
            if (_activeFolderId == null && !_isLoadingFolders)
              SliverToBoxAdapter(
                child: _buildFoldersSection(allDocs, palette, isDark),
              ),

            // ── Active Folder Header Banner ──
            if (activeFolder != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: DragTarget<PendingUpload>(
                    onWillAcceptWithDetails: (details) =>
                        details.data.folderId != null,
                    onAcceptWithDetails: (details) =>
                        _moveDocToFolder(details.data, null),
                    builder: (context, candidates, _) {
                      final isHover = candidates.isNotEmpty;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isHover
                              ? palette.accent.withValues(alpha: 0.18)
                              : palette.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isHover
                                ? palette.accent
                                : palette.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.folder_open_rounded, color: palette.warning),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isHover
                                    ? 'أفلت المستند هنا لإخراجه إلى المكتبة الرئيسية'
                                    : 'أنت داخل مجلد "${activeFolder.name}"',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _activeFolderId = null),
                              icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16),
                              label: const Text('كل المستندات'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

            // ── Documents Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    Text(
                      activeFolder != null
                          ? 'مستندات المجلد (${visibleDocs.length})'
                          : (_searchQuery.trim().isNotEmpty
                              ? 'نتائج البحث (${visibleDocs.length})'
                              : 'المستندات (${visibleDocs.length})'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    if (visibleDocs.isNotEmpty)
                      Text(
                        'اسحب المستند مطولاً لنقله لمجلد',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Empty State or Grid/List of Documents ──
            if (visibleDocs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(
                  palette,
                  isDark,
                  hasTotalDocs: allDocs.isNotEmpty,
                ),
              )
            else if (_isGridView)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDocumentGridCard(
                      visibleDocs[index],
                      palette,
                      isDark,
                    ),
                    childCount: visibleDocs.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                sliver: SliverList.builder(
                  itemCount: visibleDocs.length,
                  itemBuilder: (context, index) => _buildDocumentListTile(
                    visibleDocs[index],
                    palette,
                    isDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersSection(
    List<PendingUpload> allDocs,
    AppThemePalette palette,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'المجلدات (${_folders.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _createFolderDialog,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'مجلد جديد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
            ],
          ),
          if (_folders.isEmpty)
            InkWell(
              onTap: _createFolderDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.create_new_folder_outlined,
                      color: palette.warning,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'أنشئ مجلدات لتصنيف المستندات وسحبها وإفلاتها بسهولة',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _folders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  final docCount = allDocs
                      .where((d) => d.folderId == folder.id)
                      .length;
                  return _buildFolderChipCard(
                    folder: folder,
                    docCount: docCount,
                    palette: palette,
                    isDark: isDark,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Folder card preserving the exact drag-and-drop architecture:
  /// - Single tap opens the folder.
  /// - `LongPressDraggable<DocumentFolder>(delay: Duration(milliseconds: 450))`
  ///   allows reordering folders without interfering with normal scrolling.
  /// - `DragTarget<PendingUpload>` accepts dropped documents to move them into the folder.
  /// - Three-dots menu (`...`) is placed OUTSIDE `LongPressDraggable` so tapping it
  ///   never triggers or conflicts with dragging!
  Widget _buildFolderChipCard({
    required DocumentFolder folder,
    required int docCount,
    required AppThemePalette palette,
    required bool isDark,
  }) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is PendingUpload) {
          return data.folderId != folder.id;
        }
        if (data is DocumentFolder) {
          return data.id != folder.id;
        }
        return false;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is PendingUpload) {
          _moveDocToFolder(data, folder);
        } else if (data is DocumentFolder) {
          _reorderFolders(data, folder);
        }
      },
      builder: (context, candidates, _) {
        final isHovered = candidates.isNotEmpty;
        return Container(
          width: 185,
          decoration: BoxDecoration(
            color: isHovered
                ? palette.warning.withValues(alpha: 0.2)
                : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isHovered
                  ? palette.warning
                  : Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.65),
              width: isHovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Draggable + Single-tap zone
              Expanded(
                child: LongPressDraggable<DocumentFolder>(
                  data: folder,
                  delay: const Duration(milliseconds: 450),
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 175,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26262B) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: palette.warning, width: 1.8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_rounded, color: palette.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => setState(() => _activeFolderId = folder.id),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.folder_rounded,
                              color: palette.warning,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$docCount مستند',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Separate `...` menu button OUTSIDE LongPressDraggable
              PopupMenuButton<String>(
                tooltip: 'خيارات المجلد',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onSelected: (action) {
                  if (action == 'rename') {
                    _renameFolderDialog(folder);
                  } else if (action == 'delete') {
                    _deleteFolderDialog(folder);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('إعادة تسمية'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('حذف المجلد'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDocumentThumbnail(
    PendingUpload doc, {
    required double width,
    required double height,
    required AppThemePalette palette,
  }) {
    final thumbPath = doc.previewImagePath;
    final hasImage =
        thumbPath != null && thumbPath.isNotEmpty && File(thumbPath).existsSync();

    return Hero(
      tag: 'doc_thumb_${doc.id}',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Image.file(
                File(thumbPath),
                fit: BoxFit.cover,
                cacheWidth: 320,
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 36,
                    color: palette.accent,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDocumentGridCard(
    PendingUpload doc,
    AppThemePalette palette,
    bool isDark,
  ) {
    final isSelected = _selectedDocIds.contains(doc.id);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? palette.accent
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Draggable area (thumbnail + title)
          Expanded(
            child: LongPressDraggable<PendingUpload>(
              data: doc,
              delay: const Duration(milliseconds: 450),
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF26262B) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.accent, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_rounded, color: palette.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          doc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: InkWell(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                onTap: () {
                  if (_isMultiSelectMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedDocIds.remove(doc.id);
                      } else {
                        _selectedDocIds.add(doc.id);
                      }
                    });
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerScreen(document: doc),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildDocumentThumbnail(
                              doc,
                              width: double.infinity,
                              height: double.infinity,
                              palette: palette,
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  formatPageCount(doc.pageCount),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: CircleAvatar(
                                  radius: 13,
                                  backgroundColor: palette.accent,
                                  child: const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatFileSize(doc.fileSizeBytes)} • ${formatDate(doc.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_activeFolderId == null && doc.folderId != null) ...[
                        Builder(
                          builder: (context) {
                            final folder = _findFolderById(doc.folderId);
                            if (folder == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_rounded,
                                    size: 11,
                                    color: palette.warning,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      folder.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: palette.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom action strip with format badges + separate `...` button OUTSIDE LongPressDraggable
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 10, 6),
            child: Row(
              children: [
                _FormatMiniPill(label: 'PDF', color: const Color(0xFFE53935)),
                if (doc.docxPath != null) ...[
                  const SizedBox(width: 4),
                  _FormatMiniPill(label: 'W', color: const Color(0xFF2B579A)),
                ],
                if (doc.xlsxPath != null) ...[
                  const SizedBox(width: 4),
                  _FormatMiniPill(label: 'X', color: const Color(0xFF217346)),
                ],
                const Spacer(),
                InkWell(
                  onTap: () => _exportDocumentSheet(doc),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.ios_share_rounded,
                      size: 17,
                      color: palette.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: () => _showDocumentOptionsMenu(doc),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 19,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildDocumentListTile(
    PendingUpload doc,
    AppThemePalette palette,
    bool isDark,
  ) {
    final isSelected = _selectedDocIds.contains(doc.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? palette.accent
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: LongPressDraggable<PendingUpload>(
              data: doc,
              delay: const Duration(milliseconds: 450),
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF26262B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.accent, width: 2),
                  ),
                  child: Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  if (_isMultiSelectMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedDocIds.remove(doc.id);
                      } else {
                        _selectedDocIds.add(doc.id);
                      }
                    });
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerScreen(document: doc),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _buildDocumentThumbnail(
                        doc,
                        width: 64,
                        height: 82,
                        palette: palette,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatPageCount(doc.pageCount)} • ${formatFileSize(doc.fileSizeBytes)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  formatDate(doc.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_activeFolderId == null && doc.folderId != null) ...[
                                  Builder(
                                    builder: (context) {
                                      final folder = _findFolderById(doc.folderId);
                                      if (folder == null) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.folder_rounded,
                                              size: 12,
                                              color: palette.warning,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              folder.name,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: palette.warning,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Separate buttons OUTSIDE LongPressDraggable
          IconButton(
            tooltip: 'تصدير PDF / Word / Excel',
            onPressed: () => _exportDocumentSheet(doc),
            icon: Icon(Icons.ios_share_rounded, color: palette.accent, size: 20),
          ),
          IconButton(
            tooltip: 'المزيد من الخيارات',
            onPressed: () => _showDocumentOptionsMenu(doc),
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    AppThemePalette palette,
    bool isDark, {
    bool hasTotalDocs = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 110),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.accent.withValues(alpha: 0.12),
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.document_scanner_rounded,
                size: 52,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty
                  ? 'لا توجد نتائج مطابقة للبحث'
                  : (_activeFolderId != null
                        ? 'هذا المجلد فارغ حالياً'
                        : (hasTotalDocs && _folders.isNotEmpty
                            ? 'كل مستنداتك منظمة داخل المجلدات'
                            : 'مكتبة المستندات جاهزة لأول مسحة ضوئية')),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'جرّب البحث بكلمات أخرى أو مسح نص البحث.'
                  : (_activeFolderId != null
                        ? 'يمكنك سحب مستندات إلى هذا المجلد أو بدء مسح جديد بداخله.'
                        : (hasTotalDocs && _folders.isNotEmpty
                            ? 'افتح أي مجلد أعلاه لتصفح مستنداته، أو ابدأ مسحاً ضوئياً جديداً.'
                            : 'امسح الوثائق والفواتير والعقود بالكاميرا الذكية مع الكشف التلقائي للحواف والفلاتر الاحترافية، وصدّرها فوراً إلى PDF أو Word أو Excel بدون إنترنت.')),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _startNewScanSession,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text(
                'ابدأ المسح الضوئي الآن',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatMiniPill extends StatelessWidget {
  const _FormatMiniPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _BottomBarActionButton extends StatelessWidget {
  const _BottomBarActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final color = isActive
        ? palette.accent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
