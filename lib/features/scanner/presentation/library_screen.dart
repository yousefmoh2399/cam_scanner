import 'dart:io';

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
import 'scanner_session_screen.dart';
import 'trash_screen.dart';
import 'vault_screen.dart';
import 'widgets/apple_bottom_nav_bar.dart';
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';
import 'widgets/theme_selection_sheet.dart';

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

  bool _showFavoritesOnly = false;
  String? _selectedCategoryFilter;

  List<DocumentFolder> _folders = const [];

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



  Future<void> _moveDocToFolder(
    PendingUpload doc,
    DocumentFolder? folder,
  ) async {
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .assignToFolder(doc.id, folder?.id);
    await _loadFolders();
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
        child: SingleChildScrollView(
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
                  doc.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                ),
                title: Text(
                  doc.isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(pendingUploadsControllerProvider.notifier)
                      .toggleFavorite(doc.id);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.psychology_rounded,
                  color: palette.accent,
                ),
                title: const Text(
                  'استخراج ذكي وقراءة صوتية (OCR)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'استخراج رقم قومي، هواتف، كروت vCard، وقراءة صوتية بدون إنترنت',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSmartExtractionForDoc(doc);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: palette.danger,
                ),
                title: Text(
                  'نقل إلى سلة المحذوفات',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.danger,
                  ),
                ),
                subtitle: const Text(
                  'يمكنك استعادة المستند خلال 30 يوماً',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(pendingUploadsControllerProvider.notifier)
                      .moveToTrash(doc.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم نقل "${doc.title}" إلى سلة المحذوفات'),
                        action: SnackBarAction(
                          label: 'تراجع',
                          onPressed: () {
                            ref
                                .read(pendingUploadsControllerProvider.notifier)
                                .restoreFromTrash(doc.id);
                          },
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSmartExtractionForDoc(PendingUpload doc) async {
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
        const SnackBar(content: Text('لا توجد صور صفحات لاستخراج النص.')),
      );
      return;
    }

    final ocr = ref.read(ocrServiceProvider);
    final text = await ocr.extractTextFromFile(imagePaths.first);
    if (!mounted) return;
    await SmartDataExtractionSheet.show(
      context: context,
      text: text,
      document: doc,
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
        builder: (sheetCtx) => SingleChildScrollView(
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

  List<PendingUpload> _filterAndSortDocuments(List<PendingUpload> allDocs) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = allDocs.where((doc) {
      if (_showFavoritesOnly && !doc.isFavorite) return false;
      if (_selectedCategoryFilter != null && doc.category != _selectedCategoryFilter) {
        return false;
      }
      if (_activeFolderId != null) {
        if (doc.folderId != _activeFolderId) return false;
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
      extendBody: true,
      backgroundColor: isDark ? const Color(0xFF101012) : const Color(0xFFF7F8FA),
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
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: isDark
                  ? const Color(0xFF101012)
                  : const Color(0xFFF7F8FA),
              leading: activeFolder != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _activeFolderId = null);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF242426)
                                : const Color(0xFFE5E5EA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 16,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.document_scanner_rounded,
                            color: palette.accent,
                            size: 21,
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
                        : 'المستندات',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    activeFolder != null
                        ? '${visibleDocs.length} مستند بالمجلد'
                        : '${allDocs.length} مستند • معالجة محلية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
              actions: [
                // Trash / سلة المحذوفات button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrashScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF242426)
                            : const Color(0xFFE5E5EA),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: isDark
                            ? const Color(0xFFE5E5EA)
                            : const Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isGridView = !_isGridView);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF242426)
                            : const Color(0xFFE5E5EA),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isGridView
                            ? Icons.view_agenda_rounded
                            : Icons.grid_view_rounded,
                        size: 18,
                        color: isDark
                            ? const Color(0xFFE5E5EA)
                            : const Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 3),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF242426)
                          : const Color(0xFFE5E5EA),
                      shape: BoxShape.circle,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'خيارات إضافية',
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 19,
                        color: isDark
                            ? const Color(0xFFE5E5EA)
                            : const Color(0xFF1C1C1E),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 0.5,
                        ),
                      ),
                  onSelected: (val) {
                    if (val == 'select_mode') {
                      setState(() {
                        if (visibleDocs.isNotEmpty) {
                          _selectedDocIds.add(visibleDocs.first.id);
                        }
                      });
                    } else if (val == 'dark_mode') {
                      ref
                          .read(userPreferencesControllerProvider.notifier)
                          .toggleDarkMode();
                    } else if (val == 'sort_newest') {
                      setState(() => _sortOption = LibrarySortOption.newest);
                    } else if (val == 'sort_name') {
                      setState(() => _sortOption = LibrarySortOption.name);
                    } else if (val == 'sort_size') {
                      setState(() => _sortOption = LibrarySortOption.size);
                    } else if (val == 'trash_screen') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrashScreen(),
                        ),
                      );
                    } else if (val == 'theme_palette') {
                      showThemeSelectionSheet(context, ref);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      enabled: false,
                      height: 28,
                      child: Text(
                        'ترتيب المستندات',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sort_newest',
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: _sortOption == LibrarySortOption.newest ? palette.accent : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'الأحدث أولاً',
                            style: TextStyle(
                              fontWeight: _sortOption == LibrarySortOption.newest
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sort_name',
                      child: Row(
                        children: [
                          Icon(
                            Icons.sort_by_alpha_rounded,
                            size: 18,
                            color: _sortOption == LibrarySortOption.name ? palette.accent : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'الاسم (أ - ي)',
                            style: TextStyle(
                              fontWeight: _sortOption == LibrarySortOption.name
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sort_size',
                      child: Row(
                        children: [
                          Icon(
                            Icons.data_usage_rounded,
                            size: 18,
                            color: _sortOption == LibrarySortOption.size ? palette.accent : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'الحجم (الأكبر)',
                            style: TextStyle(
                              fontWeight: _sortOption == LibrarySortOption.size
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'theme_palette',
                      child: Row(
                        children: [
                          Icon(Icons.palette_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('ألوان التمييز (Themes)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'trash_screen',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('سلة المحذوفات'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'select_mode',
                      child: Row(
                        children: [
                          Icon(Icons.checklist_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('تحديد مستندات'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'dark_mode',
                      child: Row(
                        children: [
                          Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            size: 18,
                          ),
                          Text(isDark ? 'الوضع النهاري' : 'الوضع الليلي'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      bottomNavigationBar: AppleBottomNavBar(
        currentIndex: 0,
        onScanTap: _startNewScanSession,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsControllerProvider.notifier).refresh();
          await _loadFolders();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Apple iOS Search Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchQueryChanged,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'بحث في المستندات...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF8E8E93),
                        size: 19,
                      ),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF8E8E93),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _searchController.clear();
                                _onSearchQueryChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF242426)
                          : const Color(0xFFE5E5EA),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          width: 0.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          width: 0.5,
                        ),
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
                        'نتائج البحث داخل النصوص:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
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

            // ── Quick Document Filter Chips Strip ──
            SliverToBoxAdapter(
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  children: [
                    _buildFilterPill(
                      label: 'الكل',
                      isSelected: !_showFavoritesOnly && _selectedCategoryFilter == null,
                      onTap: () {
                        setState(() {
                          _showFavoritesOnly = false;
                          _selectedCategoryFilter = null;
                        });
                      },
                      palette: palette,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      label: 'المفضلة',
                      icon: Icons.star_rounded,
                      iconColor: Colors.amber,
                      isSelected: _showFavoritesOnly,
                      onTap: () {
                        setState(() {
                          _showFavoritesOnly = !_showFavoritesOnly;
                          if (_showFavoritesOnly) {
                            _selectedCategoryFilter = null;
                          }
                        });
                      },
                      palette: palette,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    ...['هوية وبطاقات', 'فواتير وإيصالات', 'عقود ووثائق', 'شهادات رسمية'].map((cat) {
                      final isSelected = _selectedCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildFilterPill(
                          label: cat,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedCategoryFilter = isSelected ? null : cat;
                              if (!isSelected) {
                                _showFavoritesOnly = false;
                              }
                            });
                          },
                          palette: palette,
                          isDark: isDark,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ── Dedicated Folders Section (Only in main library when not searching) ──
            if (activeFolder == null && _searchQuery.trim().isEmpty)
              SliverToBoxAdapter(
                child: _buildFoldersSection(allDocs, palette, isDark),
              ),

            // ── Active Folder Header Banner (When browsing inside a folder) ──
            if (activeFolder != null)
              SliverToBoxAdapter(
                child: _buildActiveFolderBanner(activeFolder, visibleDocs.length, palette, isDark),
              ),

            // ── Documents Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        activeFolder != null
                            ? 'مستندات "${activeFolder.name}" (${visibleDocs.length})'
                            : (_searchQuery.trim().isNotEmpty
                                ? 'نتائج البحث (${visibleDocs.length})'
                                : (_showFavoritesOnly
                                    ? 'المفضلة (${visibleDocs.length})'
                                    : (_selectedCategoryFilter != null
                                        ? '$_selectedCategoryFilter (${visibleDocs.length})'
                                        : 'المستندات (${visibleDocs.length})'))),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (visibleDocs.isNotEmpty)
                      Text(
                        'اسحب المستند لنقله لمجلد',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                    childAspectRatio: 0.75,
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



  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required AppThemePalette palette,
    required bool isDark,
    IconData? icon,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent
              : (isDark ? const Color(0xFF242426) : const Color(0xFFE5E5EA)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? palette.accent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
            width: 0.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? Colors.white
                    : (iconColor ?? const Color(0xFF8E8E93)),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E)),
                letterSpacing: -0.2,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_copy_rounded,
                      color: palette.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'المجلدات',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: palette.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_folders.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _createFolderDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 15, color: palette.accent),
                      const SizedBox(width: 3),
                      Text(
                        'مجلد جديد',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_folders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: InkWell(
              onTap: _createFolderDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.create_new_folder_outlined,
                        color: palette.warning,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نظّم مستنداتك داخل مجلدات',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'اضغط هنا لإنشاء أول مجلد (عقود، فواتير...)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: palette.accent,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              itemCount: _folders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final folder = _folders[index];
                final count = allDocs.where((d) => d.folderId == folder.id).length;
                return DragTarget<Object>(
                  onWillAcceptWithDetails: (details) {
                    final data = details.data;
                    if (data is PendingUpload) {
                      return data.folderId != folder.id;
                    }
                    return false;
                  },
                  onAcceptWithDetails: (details) {
                    final data = details.data;
                    if (data is PendingUpload) {
                      _moveDocToFolder(data, folder);
                    }
                  },
                  builder: (context, candidates, _) {
                    final isHovered = candidates.isNotEmpty;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _activeFolderId = folder.id;
                          _showFavoritesOnly = false;
                          _selectedCategoryFilter = null;
                        });
                      },
                      onLongPress: () => _showFolderOptions(folder),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 144,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: isHovered
                              ? palette.warning.withValues(alpha: 0.25)
                              : (isDark
                                  ? const Color(0xFF1E1E24)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isHovered
                                ? palette.warning
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.5),
                            width: isHovered ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.2 : 0.04,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(
                                  Icons.folder_rounded,
                                  color: palette.warning,
                                  size: 25,
                                ),
                                InkWell(
                                  onTap: () => _showFolderOptions(folder),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.more_vert_rounded,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  count == 0
                                      ? 'فارغ'
                                      : (count == 1
                                          ? 'مستند واحد'
                                          : (count == 2
                                              ? 'مستندان'
                                              : '$count مستندات')),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
              },
            ),
          ),
      ],
    );
  }

  Widget _buildActiveFolderBanner(
    DocumentFolder activeFolder,
    int docCount,
    AppThemePalette palette,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: DragTarget<PendingUpload>(
        onWillAcceptWithDetails: (details) => details.data.folderId != null,
        onAcceptWithDetails: (details) => _moveDocToFolder(details.data, null),
        builder: (context, candidates, _) {
          final isHover = candidates.isNotEmpty;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isHover
                  ? palette.accent.withValues(alpha: 0.18)
                  : palette.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHover
                    ? palette.accent
                    : palette.warning.withValues(alpha: 0.4),
                width: isHover ? 1.8 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.folder_open_rounded, color: palette.warning, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            onTap: () => setState(() => _activeFolderId = null),
                            child: Text(
                              'المكتبة الرئيسية',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          Flexible(
                            child: Text(
                              activeFolder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isHover
                            ? 'أفلت المستند هنا لإخراجه إلى المكتبة الرئيسية'
                            : '$docCount مستند داخل المجلد',
                        style: TextStyle(
                          fontSize: 11,
                          color: isHover
                              ? palette.accent
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: isHover ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'خيارات المجلد',
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onPressed: () => _showFolderOptions(activeFolder),
                ),
                IconButton(
                  tooltip: 'إغلاق المجلد',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => setState(() => _activeFolderId = null),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFolderOptions(DocumentFolder folder) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final pal = ctx.appThemePalette;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_rounded, color: Colors.amber),
                  ),
                  title: Text(
                    folder.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                const Divider(),
                if (_activeFolderId != folder.id)
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('فتح المجلد'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _activeFolderId = folder.id;
                        _showFavoritesOnly = false;
                        _selectedCategoryFilter = null;
                      });
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('إعادة تسمية المجلد'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameFolderDialog(folder);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: pal.danger,
                  ),
                  title: Text(
                    'حذف المجلد',
                    style: TextStyle(
                      color: pal.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteFolderDialog(folder);
                  },
                ),
              ],
            ),
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
                            Positioned(
                              top: 6,
                              left: 6,
                              child: isSelected
                                  ? CircleAvatar(
                                      radius: 13,
                                      backgroundColor: palette.accent,
                                      child: const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    )
                                  : InkWell(
                                      onTap: () {
                                        ref
                                            .read(
                                                pendingUploadsControllerProvider
                                                    .notifier)
                                            .toggleFavorite(doc.id);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.65),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          doc.isFavorite
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          size: 16,
                                          color: doc.isFavorite
                                              ? Colors.amber
                                              : Colors.white70,
                                        ),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (doc.category != null &&
                                doc.category!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: palette.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  doc.category!,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                            if (doc.isExifClean)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: palette.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_rounded,
                                        size: 9, color: palette.success),
                                    const SizedBox(width: 2),
                                    Text(
                                      'نظيف',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: palette.success,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
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
                                if (_activeFolderId == null && doc.folderId != null)
                                  Builder(
                                    builder: (context) {
                                      final folder = _findFolderById(doc.folderId);
                                      if (folder == null) return const SizedBox.shrink();
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.folder_rounded,
                                            size: 12,
                                            color: palette.warning,
                                          ),
                                          const SizedBox(width: 3),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 80),
                                            child: Text(
                                              folder.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: palette.warning,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
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
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 160),
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
                  ? 'لا توجد نتائج'
                  : (_activeFolderId != null
                        ? 'المجلد فارغ'
                        : (hasTotalDocs && _folders.isNotEmpty
                            ? 'المستندات منظمة داخل المجلدات'
                            : 'لا توجد مستندات بعد')),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'جرّب البحث بكلمات أخرى.'
                  : (_activeFolderId != null
                        ? 'اضغط على زر الكاميرا لمسح مستند في هذا المجلد.'
                        : (hasTotalDocs && _folders.isNotEmpty
                            ? 'افتح أي مجلد أعلاه لتصفح مستنداته.'
                            : 'اضغط على زر الكاميرا للبدء بالمسح الضوئي.')),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _startNewScanSession,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(190, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.camera_alt_rounded, size: 19),
              label: const Text(
                'مسح ضوئي جديد',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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


