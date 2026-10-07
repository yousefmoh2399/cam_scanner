import 'dart:io';
import 'dart:ui';

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
import 'web_drop_screen.dart';
import 'widgets/apple_bottom_nav_bar.dart';
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';
import 'widgets/theme_selection_sheet.dart';
import '../data/batch_zip_service.dart';
import '../data/native_scanner_bridge.dart';
import 'id_card_a4_screen.dart';

enum LibraryTab {
  documents('المستندات'),
  folders('المجلدات'),
  favorites('المفضلة');

  const LibraryTab(this.label);
  final String label;
}

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
  LibraryTab _currentTab = LibraryTab.documents;
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
    NativeScannerBridge.setQuickActionListener(_handleQuickAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialSecurityAndIntents();
    });
  }

  void _handleQuickAction(String action) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    switch (action) {
      case 'scan':
        _startNewScanSession();
        break;
      case 'gov':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const IdCardA4Screen()),
        );
        break;
      case 'vault':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VaultScreen()),
        );
        break;
    }
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
    final initialAction = await NativeScannerBridge.getInitialQuickAction();
    if (initialAction != null) {
      _handleQuickAction(initialAction);
    }
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

      final currentDocs =
          ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];

      for (final item in rawList.whereType<String>()) {
        final f = File(item);
        if (!await f.exists()) continue;

        // Never re-import internal files generated or exported by our app
        final normalized = item.replaceAll('\\', '/');
        if (normalized.contains('com.yourname.docscanner') ||
            normalized.contains('app_flutter') ||
            normalized.contains('/Exports/') ||
            normalized.contains('/Documents/') ||
            normalized.contains('/Pages/')) {
          continue;
        }

        // Avoid duplicating if file with same size and name already exists
        final fSize = await f.length();
        final baseName = p.basename(item);
        if (currentDocs.any((d) =>
            d.fileSizeBytes == fSize &&
            (p.basename(d.filePath) == baseName || d.fileName == baseName))) {
          continue;
        }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildInsetGroup(List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            width: 0.5,
          ),
        ),
        child: Column(
          children: children,
        ),
      );
    }

    Widget buildActionRow({
      required IconData icon,
      required Color iconColor,
      required String title,
      String? subtitle,
      Color? titleColor,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: titleColor ??
                            (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1.5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFF8E8E93),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildDivider() {
      return Divider(
        height: 1,
        thickness: 0.5,
        indent: 52,
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag handle
                Container(
                  width: 36,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E8E93).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),

                // Document Header Card
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildDocumentThumbnail(
                        doc,
                        width: 44,
                        height: 56,
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
                            const SizedBox(height: 3),
                            Text(
                              '${formatPageCount(doc.pageCount)} • ${formatFileSize(doc.fileSizeBytes)} • ${formatDate(doc.createdAt)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Group 1: Primary Actions
                buildInsetGroup([
                  buildActionRow(
                    icon: Icons.visibility_rounded,
                    iconColor: palette.accent,
                    title: 'معاينة وعرض المستند',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DocumentViewerScreen(document: doc),
                        ),
                      );
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.ios_share_rounded,
                    iconColor: palette.accent,
                    title: 'مشاركة المستند',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Share.shareXFiles(
                        [XFile(doc.filePath)],
                        subject: doc.title,
                      );
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.transform_rounded,
                    iconColor: const Color(0xFF2B579A),
                    title: 'حفظ وتصدير (PDF • Word • Excel)',
                    subtitle: 'تحويل ذكي أوفلاين مع تعرف النصوص OCR',
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportDocumentSheet(doc);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.table_chart_rounded,
                    iconColor: const Color(0xFF107C41),
                    title: 'تصدير مباشر إلى جداول Excel (XLSX)',
                    subtitle: 'تحويل الجداول الممسوحة إلى إكسيل قابل للتعديل',
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportToExcelDirectly(doc);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.print_rounded,
                    iconColor: palette.accent,
                    title: 'طباعة مباشرة',
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
                ]),

                // Group 2: Organization & Editing
                buildInsetGroup([
                  if (doc.pages.isNotEmpty) ...[
                    buildActionRow(
                      icon: Icons.edit_document,
                      iconColor: palette.success,
                      title: 'تعديل الصفحات والتوقيع',
                      onTap: () {
                        Navigator.pop(ctx);
                        _reopenDocumentForEditing(doc);
                      },
                    ),
                    buildDivider(),
                  ],
                  buildActionRow(
                    icon: Icons.drive_file_move_rounded,
                    iconColor: palette.warning,
                    title: 'نقل إلى مجلد...',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showMoveToFolderSheet([doc]);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.drive_file_rename_outline_rounded,
                    iconColor: palette.accent,
                    title: 'إعادة تسمية المستند',
                    onTap: () {
                      Navigator.pop(ctx);
                      _renameDocumentDialog(doc);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: doc.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    iconColor: Colors.amber,
                    title: doc.isFavorite
                        ? 'إزالة من المفضلة'
                        : 'إضافة إلى المفضلة',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(pendingUploadsControllerProvider.notifier)
                          .toggleFavorite(doc.id);
                    },
                  ),
                ]),

                // Group 3: AI Intelligence & Security
                buildInsetGroup([
                  buildActionRow(
                    icon: Icons.psychology_rounded,
                    iconColor: const Color(0xFF9333EA),
                    title: 'استخراج ذكي وقراءة صوتية (OCR)',
                    subtitle: 'استخراج رقم قومي وهواتف وقراءة ناطقة',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showSmartExtractionForDoc(doc);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.auto_fix_high_rounded,
                    iconColor: const Color(0xFF0284C7),
                    title: 'التعرف على النص وإعادة التسمية الذكية',
                    subtitle: 'تسمية المستند تلقائياً بناءً على محتواه وموضوعه',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showOcrAndSmartRenameDialog(doc);
                    },
                  ),
                  buildDivider(),
                  buildActionRow(
                    icon: Icons.enhanced_encryption_rounded,
                    iconColor: const Color(0xFF059669),
                    title: 'نقل إلى الخزنة المشفرة (AES-256)',
                    subtitle: 'تشفير كامل للملف وإخفاؤه من المكتبة',
                    onTap: () {
                      Navigator.pop(ctx);
                      _moveSingleDocToSecretVault(doc);
                    },
                  ),
                ]),

                // Group 4: Destructive Action
                buildInsetGroup([
                  buildActionRow(
                    icon: Icons.delete_outline_rounded,
                    iconColor: palette.danger,
                    title: 'نقل إلى سلة المحذوفات',
                    titleColor: palette.danger,
                    subtitle: 'يمكنك استعادة المستند خلال 30 يوماً',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(pendingUploadsControllerProvider.notifier)
                          .moveToTrash(doc.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم نقل "${doc.title}" إلى سلة المحذوفات',
                            ),
                            action: SnackBarAction(
                              label: 'تراجع',
                              onPressed: () {
                                ref
                                    .read(pendingUploadsControllerProvider
                                        .notifier)
                                    .restoreFromTrash(doc.id);
                              },
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ]),
              ],
            ),
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
    final isFavMode = _showFavoritesOnly || _currentTab == LibraryTab.favorites;
    final filtered = allDocs.where((doc) {
      if (isFavMode && !doc.isFavorite) return false;
      if (_selectedCategoryFilter != null && doc.category != _selectedCategoryFilter) {
        return false;
      }
      if (_activeFolderId != null) {
        if (doc.folderId != _activeFolderId) return false;
      } else {
        // At the root level of the library:
        // Hide documents that have been moved into folders so they don't linger outside!
        if (query.isEmpty && !isFavMode && _selectedCategoryFilter == null) {
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

  Future<void> _exportSelectedAsBatchZip(List<PendingUpload> allDocs) async {
    final selected =
        allDocs.where((d) => _selectedDocIds.contains(d.id)).toList();
    if (selected.isEmpty) return;

    double progress = 0.0;
    String status = 'جارٍ تجهيز ملفات الأرشيف...';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.folder_zip_rounded,
                    color: Color(0xFF007AFF), size: 24),
                SizedBox(width: 10),
                Text('تصدير كأرشيف ZIP مجمع',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 14),
                Text(
                  status,
                  style: const TextStyle(fontSize: 12.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final zipFile = await BatchZipService.instance.createBatchZip(
        documents: selected,
        onProgress: (p, s) {
          progress = p;
          status = s;
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _selectedDocIds.clear());

        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'تم إنشاء الأرشيف بنجاح: ${p.basename(zipFile.path)} (${(zipFile.lengthSync() / 1024).toStringAsFixed(1)} KB)'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'مشاركة ZIP',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(zipFile.path)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء الأرشيف: $e')),
        );
      }
    }
  }

  Widget _buildMultiSelectBottomBar(
    List<PendingUpload> allDocs,
    AppThemePalette palette,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMultiSelectActionItem(
                icon: Icons.folder_zip_rounded,
                label: 'أرشيف ZIP',
                color: const Color(0xFF007AFF),
                onTap: () => _exportSelectedAsBatchZip(allDocs),
              ),
              _buildMultiSelectActionItem(
                icon: Icons.drive_file_move_rounded,
                label: 'نقل لمجلد',
                color: palette.accent,
                onTap: () {
                  final selected = allDocs
                      .where((d) => _selectedDocIds.contains(d.id))
                      .toList();
                  _showMoveToFolderSheet(selected);
                },
              ),
              _buildMultiSelectActionItem(
                icon: Icons.ios_share_rounded,
                label: 'مشاركة',
                color: const Color(0xFF34C759),
                onTap: () => _shareSelectedDocuments(allDocs),
              ),
              _buildMultiSelectActionItem(
                icon: Icons.delete_outline_rounded,
                label: 'حذف',
                color: palette.danger,
                onTap: _deleteSelectedDocuments,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(pendingUploadsControllerProvider);
    final allDocs = docsAsync.valueOrNull ?? const <PendingUpload>[];
    final visibleDocs = _filterAndSortDocuments(allDocs);
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFolder = _activeFolder;
    final rootDocsCount = allDocs
        .where((d) => d.folderId == null || d.folderId!.isEmpty)
        .length;
    final favDocsCount = allDocs.where((d) => d.isFavorite).length;

    return Scaffold(
      extendBody: true,
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: _isMultiSelectMode
          ? AppBar(
              leading: TextButton(
                onPressed: () => setState(() => _selectedDocIds.clear()),
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                    fontSize: 15,
                  ),
                ),
              ),
              title: Text(
                'تم تحديد ${_selectedDocIds.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'تحديد الكل',
                  onPressed: () {
                    setState(() {
                      if (_selectedDocIds.length == visibleDocs.length) {
                        _selectedDocIds.clear();
                      } else {
                        _selectedDocIds.addAll(visibleDocs.map((d) => d.id));
                      }
                    });
                  },
                  icon: const Icon(Icons.select_all_rounded),
                ),
                IconButton(
                  tooltip: 'تصدير كأرشيف ZIP مجمع',
                  onPressed: () => _exportSelectedAsBatchZip(allDocs),
                  icon: const Icon(Icons.folder_zip_rounded, color: Color(0xFF007AFF)),
                ),
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
                  icon: const Icon(Icons.ios_share_rounded),
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
              backgroundColor:
                  isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
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
                                ? const Color(0xFF1C1C1E)
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/app_icon.png',
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeFolder != null ? activeFolder.name : 'المكتبة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    activeFolder != null
                        ? '${visibleDocs.length} مستند بالمجلد'
                        : '${allDocs.length} مستند • أوفلاين',
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
                // View Mode Toggle (Grid vs List)
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
                            ? const Color(0xFF1C1C1E)
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

                // Apple Select Mode Pill Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (visibleDocs.isNotEmpty) {
                          _selectedDocIds.add(visibleDocs.first.id);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'تحديد',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFE5E5EA)
                              : const Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                  ),
                ),

                // Apple More Menu Button (...)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 3),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E)
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
                      ),
                      onSelected: (val) {
                        if (val == 'web_drop') {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WebDropScreen(),
                            ),
                          );
                        } else if (val == 'trash_screen') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TrashScreen(),
                            ),
                          );
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
                        } else if (val == 'theme_palette') {
                          showThemeSelectionSheet(context, ref);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'web_drop',
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_tethering_rounded,
                                size: 18,
                                color: Color(0xFF007AFF),
                              ),
                              SizedBox(width: 10),
                              Text('نقل للكمبيوتر والماك (Web Drop)'),
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
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          enabled: false,
                          height: 26,
                          child: Text(
                            'ترتيب المستندات',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'sort_newest',
                          child: Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: _sortOption == LibrarySortOption.newest
                                    ? palette.accent
                                    : null,
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
                                color: _sortOption == LibrarySortOption.name
                                    ? palette.accent
                                    : null,
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
                                color: _sortOption == LibrarySortOption.size
                                    ? palette.accent
                                    : null,
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
                              Text('ألوان التمييز'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'dark_mode',
                          child: Row(
                            children: [
                              Icon(
                                isDark
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
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
      bottomNavigationBar: _isMultiSelectMode
          ? _buildMultiSelectBottomBar(allDocs, palette, isDark)
          : AppleBottomNavBar(
              currentIndex: 0,
              onScanTap: _startNewScanSession,
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsControllerProvider.notifier).refresh();
          await _loadFolders();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ── Apple Inset Search Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchQueryChanged,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'البحث في المستندات والنصوص...',
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
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFE5E5EA),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
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
              ),
            ),

            // ── Apple Segmented Control (المستندات | المجلدات | المفضلة) ──
            if (activeFolder == null && _searchQuery.trim().isEmpty)
              SliverToBoxAdapter(
                child: _buildAppleSegmentedControl(
                  isDark: isDark,
                  palette: palette,
                  documentsCount: rootDocsCount,
                  foldersCount: _folders.length,
                  favoritesCount: favDocsCount,
                ),
              ),

            // ── Highlighted OCR Snippets when searching inside pages ──
            if (_searchQuery.trim().isNotEmpty && _ocrSearchHits.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

            // ── Category Filter Pills (Only in Documents tab, at root, not searching) ──
            if (_currentTab == LibraryTab.documents &&
                activeFolder == null &&
                _searchQuery.trim().isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 2),
                    children: [
                      _buildFilterPill(
                        label: 'الكل',
                        isSelected: _selectedCategoryFilter == null,
                        onTap: () {
                          setState(() {
                            _selectedCategoryFilter = null;
                          });
                        },
                        palette: palette,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      ...['هوية وبطاقات', 'فواتير وإيصالات', 'عقود ووثائق', 'شهادات رسمية']
                          .map((cat) {
                        final isSelected = _selectedCategoryFilter == cat;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _buildFilterPill(
                            label: cat,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedCategoryFilter =
                                    isSelected ? null : cat;
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

            // ── Active Folder Header Banner (When browsing inside a folder) ──
            if (activeFolder != null)
              SliverToBoxAdapter(
                child: _buildActiveFolderBanner(
                    activeFolder, visibleDocs.length, palette, isDark),
              ),

            // ── Section Content Header ──
            if (_currentTab == LibraryTab.folders && activeFolder == null)
              SliverToBoxAdapter(
                child: _buildFoldersHeader(palette, isDark),
              )
            else
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
                                  : (_currentTab == LibraryTab.favorites
                                      ? 'المستندات المفضلة (${visibleDocs.length})'
                                      : (_selectedCategoryFilter != null
                                          ? '$_selectedCategoryFilter (${visibleDocs.length})'
                                          : 'المستندات (${visibleDocs.length})'))),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                        ),
                      ),
                      if (visibleDocs.isNotEmpty && activeFolder == null)
                        Text(
                          'اسحب المستند لمجلد',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // ── Main Content Area ──
            if (_currentTab == LibraryTab.folders && activeFolder == null)
              _buildDedicatedFoldersSliver(allDocs, palette, isDark)
            else if (visibleDocs.isEmpty)
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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.77,
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

  Widget _buildAppleSegmentedControl({
    required bool isDark,
    required AppThemePalette palette,
    required int documentsCount,
    required int foldersCount,
    required int favoritesCount,
  }) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildSegmentItem(
            tab: LibraryTab.documents,
            label: 'المستندات',
            count: documentsCount,
            isSelected: _currentTab == LibraryTab.documents && _activeFolderId == null,
            isDark: isDark,
          ),
          _buildSegmentItem(
            tab: LibraryTab.folders,
            label: 'المجلدات',
            count: foldersCount,
            isSelected: _currentTab == LibraryTab.folders && _activeFolderId == null,
            isDark: isDark,
          ),
          _buildSegmentItem(
            tab: LibraryTab.favorites,
            label: 'المفضلة',
            count: favoritesCount,
            isSelected: _currentTab == LibraryTab.favorites && _activeFolderId == null,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem({
    required LibraryTab tab,
    required String label,
    required int count,
    required bool isSelected,
    required bool isDark,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _currentTab = tab;
            _activeFolderId = null;
            if (tab == LibraryTab.favorites) {
              _showFavoritesOnly = true;
            } else {
              _showFavoritesOnly = false;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black)
                      : const Color(0xFF8E8E93),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.07))
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ],
            ],
          ),
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

  Widget _buildFoldersHeader(AppThemePalette palette, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Text(
            'المجلدات (${_folders.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
          ),
          const Spacer(),
          InkWell(
            onTap: _createFolderDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 15, color: palette.accent),
                  const SizedBox(width: 4),
                  Text(
                    'مجلد جديد',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDedicatedFoldersSliver(
    List<PendingUpload> allDocs,
    AppThemePalette palette,
    bool isDark,
  ) {
    if (_folders.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 160),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    size: 40,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'لا توجد مجلدات بعد',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'نظّم مستنداتك وعقودك داخل مجلدات مخصصة لتسهيل الوصول إليها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _createFolderDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                  label: const Text(
                    'إنشاء أول مجلد',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final folder = _folders[index];
            final count =
                allDocs.where((d) => d.folderId == folder.id).length;
            return _buildDedicatedFolderCard(
              folder: folder,
              docCount: count,
              palette: palette,
              isDark: isDark,
            );
          },
          childCount: _folders.length,
        ),
      ),
    );
  }

  Widget _buildDedicatedFolderCard({
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
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _activeFolderId = folder.id;
                _showFavoritesOnly = false;
                _selectedCategoryFilter = null;
              });
            },
            onLongPress: () => _showFolderOptions(folder),
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isHovered
                    ? palette.warning.withValues(alpha: 0.18)
                    : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isHovered
                      ? palette.warning
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06)),
                  width: isHovered ? 1.8 : 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.22 : 0.04),
                    blurRadius: 8,
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
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Colors.amber,
                          size: 26,
                        ),
                      ),
                      InkWell(
                        onTap: () => _showFolderOptions(folder),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 19,
                            color: Color(0xFF8E8E93),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        docCount == 0
                            ? 'فارغ'
                            : (docCount == 1
                                ? 'مستند واحد'
                                : (docCount == 2
                                    ? 'مستندان'
                                    : '$docCount مستندات')),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                  : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHover
                    ? palette.accent
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                width: isHover ? 1.8 : 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    color: Colors.amber,
                    size: 22,
                  ),
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
                            color: const Color(0xFF8E8E93),
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
                              : const Color(0xFF8E8E93),
                          fontWeight:
                              isHover ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'خيارات المجلد',
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
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
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E8E93).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.amber,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            folder.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        if (_activeFolderId != folder.id) ...[
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.folder_open_rounded,
                                color: palette.accent,
                                size: 18,
                              ),
                            ),
                            title: const Text(
                              'فتح وتصفح المجلد',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _activeFolderId = folder.id;
                                _showFavoritesOnly = false;
                                _selectedCategoryFilter = null;
                              });
                            },
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 52,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ],
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              color: Color(0xFF007AFF),
                              size: 18,
                            ),
                          ),
                          title: const Text(
                            'إعادة تسمية المجلد',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _renameFolderDialog(folder);
                          },
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 52,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: palette.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: palette.danger,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            'حذف المجلد',
                            style: TextStyle(
                              color: palette.danger,
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
                ],
              ),
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
    final hasImage = thumbPath != null &&
        thumbPath.isNotEmpty &&
        PendingUpload.isImageFilePath(thumbPath) &&
        File(thumbPath).existsSync();

    Widget buildPdfFallback() => Column(
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
    );

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
                errorBuilder: (_, __, ___) => buildPdfFallback(),
              )
            : buildPdfFallback(),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? palette.accent
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06)),
          width: isSelected ? 2 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Draggable area (thumbnail + page count + favorite star)
          Expanded(
            child: LongPressDraggable<PendingUpload>(
              data: doc,
              delay: const Duration(milliseconds: 450),
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  width: 160,
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
                  top: Radius.circular(18),
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _buildDocumentThumbnail(
                          doc,
                          width: double.infinity,
                          height: double.infinity,
                          palette: palette,
                        ),
                      ),
                    ),
                    // Frosted page count pill (top-right)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2.5,
                            ),
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Text(
                              formatPageCount(doc.pageCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Frosted Favorite star or selection circle (top-left)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: isSelected
                          ? CircleAvatar(
                              radius: 12,
                              backgroundColor: palette.accent,
                              child: const Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: InkWell(
                                  onTap: () {
                                    ref
                                        .read(pendingUploadsControllerProvider
                                            .notifier)
                                        .toggleFavorite(doc.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4.5),
                                    color: Colors.black.withValues(alpha: 0.55),
                                    child: Icon(
                                      doc.isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      size: 15,
                                      color: doc.isFavorite
                                          ? Colors.amber
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Metadata area
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDate(doc.createdAt)} • ${formatFileSize(doc.fileSizeBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF8E8E93),
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
                            const Icon(
                              Icons.folder_rounded,
                              size: 11,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                folder.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber,
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

          // Bottom action strip with format badges + Share & More buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                const _FormatMiniPill(
                  label: 'PDF',
                  color: Color(0xFFE53935),
                ),
                if (doc.docxPath != null) ...[
                  const SizedBox(width: 4),
                  const _FormatMiniPill(
                    label: 'Word',
                    color: Color(0xFF2B579A),
                  ),
                ],
                if (doc.xlsxPath != null) ...[
                  const SizedBox(width: 4),
                  const _FormatMiniPill(
                    label: 'Excel',
                    color: Color(0xFF217346),
                  ),
                ],
                const Spacer(),
                InkWell(
                  onTap: () => _exportDocumentSheet(doc),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.ios_share_rounded,
                      size: 16,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: () => _showDocumentOptionsMenu(doc),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: Color(0xFF8E8E93),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? palette.accent
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06)),
          width: isSelected ? 2 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
                borderRadius: BorderRadius.circular(16),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildDocumentThumbnail(
                          doc,
                          width: 56,
                          height: 72,
                          palette: palette,
                        ),
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
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${formatPageCount(doc.pageCount)} • ${formatFileSize(doc.fileSizeBytes)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF8E8E93),
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
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                                if (_activeFolderId == null &&
                                    doc.folderId != null)
                                  Builder(
                                    builder: (context) {
                                      final folder =
                                          _findFolderById(doc.folderId);
                                      if (folder == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.folder_rounded,
                                            size: 11,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            folder.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.amber,
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
          IconButton(
            tooltip: 'تصدير PDF / Word / Excel',
            onPressed: () => _exportDocumentSheet(doc),
            icon: const Icon(
              Icons.ios_share_rounded,
              size: 18,
              color: Color(0xFF8E8E93),
            ),
          ),
          IconButton(
            tooltip: 'المزيد',
            onPressed: () => _showDocumentOptionsMenu(doc),
            icon: const Icon(
              Icons.more_horiz_rounded,
              size: 20,
              color: Color(0xFF8E8E93),
            ),
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
    final isSearching = _searchQuery.isNotEmpty;
    final isInsideFolder = _activeFolderId != null;
    final isFavoritesTab = _currentTab == LibraryTab.favorites;

    final IconData emptyIcon = isSearching
        ? Icons.search_off_rounded
        : (isInsideFolder
            ? Icons.folder_open_rounded
            : (isFavoritesTab
                ? Icons.star_border_rounded
                : Icons.document_scanner_rounded));

    final String emptyTitle = isSearching
        ? 'لا توجد نتائج'
        : (isInsideFolder
            ? 'المجلد فارغ'
            : (isFavoritesTab
                ? 'لا توجد مستندات بالمفضلة'
                : 'لا توجد مستندات بعد'));

    final String emptySubtitle = isSearching
        ? 'جرّب البحث بكلمات أخرى أو تحقق من الإملاء.'
        : (isInsideFolder
            ? 'اضغط على زر الكاميرا لمسح مستند وإضافته لهذا المجلد.'
            : (isFavoritesTab
                ? 'اضغط على رمز النجمة في أي مستند لإضافته هنا.'
                : 'اضغط على زر الكاميرا للبدء بمسح المستندات.'));

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 160),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.accent.withValues(alpha: 0.10),
              ),
              child: Icon(
                emptyIcon,
                size: 42,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              emptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16.5,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              emptySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 18),
            if (!isSearching && !isFavoritesTab)
              FilledButton.icon(
                onPressed: _startNewScanSession,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(180, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text(
                  'مسح ضوئي جديد',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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


