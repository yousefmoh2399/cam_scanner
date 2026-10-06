import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/document_paper_size.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/permission_request_coordinator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../data/native_scanner_bridge.dart';
import '../data/office_exporter_service.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/models/image_filter_type.dart';
import 'scan_review_screen.dart';
import 'signature_bottom_sheet.dart';
import 'signature_placement_screen.dart';
import 'widgets/export_format_sheet.dart';

enum _PostScanAction { addPage, startNewFile, saveAndFinish }

class ScannerSessionScreen extends ConsumerStatefulWidget {
  const ScannerSessionScreen({
    super.key,
    this.initialTargetFolderId,
  });

  final String? initialTargetFolderId;

  @override
  ConsumerState<ScannerSessionScreen> createState() =>
      _ScannerSessionScreenState();
}

class _ScannerSessionScreenState extends ConsumerState<ScannerSessionScreen> {
  bool _autoStarted = false;
  bool _isSavingSession = false;
  bool _isLoadingScanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localDocumentStoreProvider).purgeOrphanDrafts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    if (!_autoStarted && (session == null || session.pages.isEmpty)) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
    }
  }

  Future<void> _editPage(ScanPage page) async {
    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    if (session == null) return;
    final sourcePath = page.originalPath ?? page.imagePath;

    final updatedPage = await Navigator.of(context).push<ScanPage>(
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          rawImagePath: sourcePath,
          sessionId: session.id,
          pageId: page.id,
          initialCorners: page.corners ?? const [],
          initialFilter: page.filter.nativeKey,
          initialQuarterRotations: page.quarterTurns,
        ),
      ),
    );

    if (updatedPage != null && mounted) {
      await ref
          .read(scanSessionControllerProvider.notifier)
          .replacePage(page.id, updatedPage);
    }
  }

  Future<void> _splitBookPageFlow(ScanPage page) async {
    final draftsDir =
        await ref.read(localDocumentStoreProvider).getDraftsDirectory();
    final tag = DateTime.now().millisecondsSinceEpoch;
    final outRight = '${draftsDir.path}/book_right_$tag.jpg';
    final outLeft = '${draftsDir.path}/book_left_$tag.jpg';

    setState(() => _isLoadingScanner = true);
    try {
      final res = await NativeScannerBridge.splitBookPage(
        path: page.imagePath,
        outRightPath: outRight,
        outLeftPath: outLeft,
      );
      if (res == null || !mounted) return;

      final sessionController = ref.read(scanSessionControllerProvider.notifier);
      final page1 = ScanPage(
        id: const Uuid().v4(),
        imagePath: res.pageRight,
        createdAt: DateTime.now(),
        paperSize: page.paperSize,
        filter: page.filter,
      );
      final page2 = ScanPage(
        id: const Uuid().v4(),
        imagePath: res.pageLeft,
        createdAt: DateTime.now(),
        paperSize: page.paperSize,
        filter: page.filter,
      );

      await sessionController.replacePage(page.id, page1);
      await sessionController.addPage(page2);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم فصل الصفحتين بنجاح بترتيب القراءة العربي (يمين ثم يسار)',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل فصل صفحتين الكتاب: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingScanner = false);
    }
  }

  Future<void> _importFromGallery() async {
    if (_isSavingSession || _isLoadingScanner) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null || result.paths.isEmpty) return;

      final sessionController = ref.read(scanSessionControllerProvider.notifier);
      await sessionController.ensureSession();
      int addedCount = 0;
      for (final path in result.paths) {
        if (path != null && File(path).existsSync()) {
          final page = ScanPage(
            id: const Uuid().v4(),
            imagePath: path,
            createdAt: DateTime.now(),
          );
          await sessionController.addPage(page);
          addedCount++;
        }
      }
      if (mounted && addedCount > 0) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة $addedCount صفحة من ألبوم الصور بنجاح'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استيراد الصور: $e')),
        );
      }
    }
  }

  Future<void> _startScan({String? replacePageId}) async {
    if (_isSavingSession || _isLoadingScanner) {
      return;
    }

    setState(() => _isLoadingScanner = true);

    final sessionController = ref.read(scanSessionControllerProvider.notifier);

    await sessionController.ensureSession();
    if (!mounted) return;
    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    if (session == null) {
      setState(() => _isLoadingScanner = false);
      return;
    }

    List<NativeScannerResult> scanResults = const [];
    try {
      final cameraStatus = await PermissionRequestCoordinator.run(
        Permission.camera.request,
      );
      if (!cameraStatus.isGranted) {
        throw ScannerPermissionDeniedException(
          permission: 'الكاميرا',
          permanentlyDenied:
              cameraStatus.isPermanentlyDenied || cameraStatus.isRestricted,
        );
      }

      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      scanResults = await NativeScannerBridge.startScan(
        destDir: draftsDir.path,
        batch: replacePageId == null,
      );
    } on ScannerPermissionDeniedException catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingScanner = false);
      await _showScannerPermissionDialog(error);
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingScanner = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    } finally {
      if (mounted) {
        setState(() => _isLoadingScanner = false);
      }
    }

    if (!mounted || scanResults.isEmpty) return;

    var saveAllRemaining = false;
    for (var i = 0; i < scanResults.length; i++) {
      if (!mounted) break;
      final result = scanResults[i];

      if (saveAllRemaining) {
        final autoPage = await _autoProcessBatchResult(
          result: result,
          sessionId: session.id,
          pageId: replacePageId,
        );
        if (autoPage != null && mounted) {
          if (replacePageId != null) {
            await sessionController.replacePage(replacePageId, autoPage);
            break;
          } else {
            await sessionController.addPage(autoPage);
          }
        }
        continue;
      }

      final dynamic reviewResult = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(
            rawImagePath: result.path,
            sessionId: session.id,
            pageId: replacePageId,
            initialCorners: result.corners,
            imageWidth: result.width,
            imageHeight: result.height,
            pageIndex: i + 1,
            totalPages: scanResults.length,
          ),
        ),
      );

      if (reviewResult != null && mounted) {
        ScanPage? scanPage;
        if (reviewResult is ScanReviewResult) {
          scanPage = reviewResult.page;
          saveAllRemaining = reviewResult.saveAllRemaining;
        } else if (reviewResult is ScanPage) {
          scanPage = reviewResult;
        }

        if (scanPage != null) {
          if (replacePageId != null) {
            await sessionController.replacePage(replacePageId, scanPage);
            break;
          } else {
            await sessionController.addPage(scanPage);
          }
        }
      }
    }
  }

  Future<ScanPage?> _autoProcessBatchResult({
    required NativeScannerResult result,
    required String sessionId,
    String? pageId,
  }) async {
    try {
      final pid = pageId ?? const Uuid().v4();
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      final fullWarpPath = '${draftsDir.path}/full_warp_$pid.jpg';
      final fullFilteredPath = '${draftsDir.path}/full_filtered_$pid.jpg';

      await NativeScannerBridge.warp(
        path: result.path,
        corners: result.corners,
        outPath: fullWarpPath,
        maxSide: 2048,
        quarterTurns: 0,
      ).timeout(const Duration(seconds: 20));

      await NativeScannerBridge.applyFilter(
        path: fullWarpPath,
        filter: 'enhance',
        outPath: fullFilteredPath,
        maxSide: 2048,
      ).timeout(const Duration(seconds: 20));

      final savedPath = await ref.read(localDocumentStoreProvider).savePageFile(
            sessionId: sessionId,
            pageId: pid,
            sourcePath: fullFilteredPath,
          );

      String preservedRawPath = result.path;
      if (!preservedRawPath.contains(sessionId)) {
        preservedRawPath =
            await ref.read(localDocumentStoreProvider).importRawScanFile(
                  sessionId: sessionId,
                  sourcePath: result.path,
                );
      }

      for (final p in [fullWarpPath, fullFilteredPath]) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }

      return ScanPage(
        id: pid,
        imagePath: savedPath,
        createdAt: DateTime.now(),
        originalPath: preservedRawPath,
        corners: result.corners,
        filter: ImageFilterType.enhance,
        quarterTurns: 0,
      );
    } catch (e) {
      debugPrint('[ScannerSessionScreen] _autoProcessBatchResult error: $e');
      return null;
    }
  }

  Future<void> _showScannerPermissionDialog(
    ScannerPermissionDeniedException error,
  ) {
    final isPermanent = error.permanentlyDenied;
    final palette = context.appThemePalette;

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.photo_camera_front_rounded,
            color: palette.danger,
            size: 40,
          ),
        ),
        title: const Text(
          'الصلاحية مطلوبة للمسح',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isPermanent
                  ? 'المسح الضوئي يحتاج إذن الوصول إلى الكاميرا (${error.permission}).\n\nتم رفض الإذن سابقاً من إعدادات النظام، يرجى فتح الإعدادات وتفعيله يدوياً.'
                  : 'يحتاج التطبيق إلى إذن الوصول إلى الكاميرا (${error.permission}) لتتمكن من مسح الصفحات والمستندات واستيرادها بنجاح.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(110, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('إلغاء'),
          ),
          if (isPermanent)
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('فتح الإعدادات'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('موافق'),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSheetOption({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.3 : 0.6,
              ),
            ),
            color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<_PostScanAction?> _showPostScanSheet() {
    final palette = context.appThemePalette;

    return showModalBottomSheet<_PostScanAction>(
      isScrollControlled: true,
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                'ما الخطوة التالية للمستند؟',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 18),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.add_photo_alternate_rounded,
                iconColor: palette.accent,
                iconBgColor: palette.accent.withValues(alpha: 0.12),
                title: 'إضافة صفحة لنفس الملف',
                subtitle: 'التقط صفحة إضافية وألحقها بالملف الحالي',
                onTap: () => Navigator.pop(context, _PostScanAction.addPage),
              ),
              const SizedBox(height: 12),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.check_circle_rounded,
                iconColor: palette.success,
                iconBgColor: palette.success.withValues(alpha: 0.12),
                title: 'حفظ المستند الحالي وإنهاء',
                subtitle: 'حفظ الصفحات الممسوحة بصيغة PDF أو Word أو Excel',
                onTap: () =>
                    Navigator.pop(context, _PostScanAction.saveAndFinish),
              ),
              const SizedBox(height: 12),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.library_add_rounded,
                iconColor: palette.warning,
                iconBgColor: palette.warning.withValues(alpha: 0.12),
                title: 'حفظ وبدء ملف جديد',
                subtitle: 'حفظ الملف الحالي والبدء فوراً بمسح مستند آخر',
                onTap: () =>
                    Navigator.pop(context, _PostScanAction.startNewFile),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _generatedDefaultFileName() {
    return defaultPdfName();
  }

  Future<void> _saveAndFinish() async {
    if (_isSavingSession) {
      return;
    }

    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    final pageCount = session?.pages.length ?? 1;

    final selection = await showSaveAndExportBottomSheet(
      context: context,
      initialName: _generatedDefaultFileName(),
      pageCount: pageCount,
      title: 'حفظ وتصدير المستند',
    );
    if (selection == null || selection.fileName.isEmpty || !mounted) return;

    try {
      setState(() {
        _isSavingSession = true;
      });
      final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
      final sessionController = ref.read(
        scanSessionControllerProvider.notifier,
      );
      final pendingController = ref.read(
        pendingUploadsControllerProvider.notifier,
      );
      PendingUpload pending = await sessionController.saveCurrentSession(
        selection.fileName,
        saveDirectoryPath: preferences?.scanSaveDirectoryPath,
        applyEnhancement: selection.applyEnhancement,
      );

      if (widget.initialTargetFolderId != null &&
          widget.initialTargetFolderId!.isNotEmpty) {
        await pendingController.assignToFolder(
          pending.id,
          widget.initialTargetFolderId,
        );
        pending = pending.copyWith(folderId: widget.initialTargetFolderId);
      }

      if (!mounted) return;
      await pendingController.refresh();
      if (!mounted) return;

      setState(() {
        _isSavingSession = false;
      });

      // Execute export & show immediate Open/Share/Print options
      await executeDocumentExportWithUi(
        context: context,
        ref: ref,
        document: pending,
        selection: selection,
      );

      if (mounted) {
        Navigator.of(context).pop(pending);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scannerFriendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSession = false;
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _saveCurrentAndStartNew() async {
    if (_isSavingSession) {
      return;
    }

    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    final pageCount = session?.pages.length ?? 1;

    final selection = await showSaveAndExportBottomSheet(
      context: context,
      initialName: _generatedDefaultFileName(),
      pageCount: pageCount,
      title: 'حفظ وبدء مستند جديد',
    );
    if (selection == null || selection.fileName.isEmpty || !mounted) return;

    try {
      setState(() {
        _isSavingSession = true;
      });
      final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
      final sessionController = ref.read(
        scanSessionControllerProvider.notifier,
      );
      final pendingController = ref.read(
        pendingUploadsControllerProvider.notifier,
      );
      PendingUpload pending = await sessionController.saveCurrentSession(
        selection.fileName,
        saveDirectoryPath: preferences?.scanSaveDirectoryPath,
        applyEnhancement: selection.applyEnhancement,
      );
      if (widget.initialTargetFolderId != null &&
          widget.initialTargetFolderId!.isNotEmpty) {
        await pendingController.assignToFolder(
          pending.id,
          widget.initialTargetFolderId,
        );
        pending = pending.copyWith(folderId: widget.initialTargetFolderId);
      }
      if (!mounted) return;
      await pendingController.refresh();
      if (!mounted) return;

      if (selection.format != ExportFormat.pdf) {
        final exporter = ref.read(officeExporterServiceProvider);
        final exportedPath = await exporter.exportDocument(
          document: pending,
          format: selection.format,
        );
        if (selection.format == ExportFormat.docx) {
          await pendingController.updateExportPaths(
            pending.id,
            docxPath: exportedPath,
          );
        } else if (selection.format == ExportFormat.xlsx) {
          await pendingController.updateExportPaths(
            pending.id,
            xlsxPath: exportedPath,
          );
        }
      }

      if (!mounted) return;
      await sessionController.startNewEmptySession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الملف الحالي وبدء ملف جديد')),
      );
      await _startScan();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scannerFriendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSession = false;
        });
      }
    }
  }

  String _scannerFriendlyErrorMessage(Object error) {
    final rawMessage = error.toString().trim();
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('pathaccessexception') ||
        normalized.contains('operation not permitted') ||
        normalized.contains('errno = 1')) {
      return 'تعذر الحفظ في المجلد المحدد على الهاتف. تم تجهيز النظام لاستخدام مجلد التطبيق الآمن بدلًا منه. جرّب الحفظ مرة أخرى.';
    }
    if (rawMessage.startsWith('Exception: ')) {
      return rawMessage.substring('Exception: '.length).trim();
    }
    return rawMessage.isEmpty
        ? 'تعذر حفظ الملف حاليًا. حاول مرة أخرى.'
        : rawMessage;
  }

  /// Full signature flow for a single page:
  /// 1. Show bottom sheet (draw or pick saved signature).
  /// 2. Navigate to placement screen (drag + pinch to resize).
  /// 3. Apply composited result back into the session page file.
  Future<void> _openSignatureFlow(ScanPage page) async {
    if (_isSavingSession) return;

    // Step 1 — bottom sheet: draw or pick signature
    final storageService = ref.read(signatureStorageServiceProvider);
    final signatureResult = await showSignatureBottomSheet(
      context: context,
      storageService: storageService,
    );
    if (signatureResult == null || !mounted) return;

    // Step 2 — placement screen: drag & resize
    final compositedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => SignaturePlacementScreen(
          pageImagePath: page.imagePath,
          signatureBytes: signatureResult.pngBytes,
        ),
        fullscreenDialog: true,
      ),
    );

    if (compositedBytes == null || !mounted) return;

    // Step 3 — write composited image back to the session page
    try {
      await ref
          .read(scanSessionControllerProvider.notifier)
          .applySignatureToPage(page.id, compositedBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تطبيق التوقيع على الصفحة بنجاح'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ التوقيع: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(scanSessionControllerProvider);
    final pages = sessionState.valueOrNull?.pages ?? const <ScanPage>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.appThemePalette;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'مراجعة وتعديل المسح',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (pages.isNotEmpty)
              Text(
                '${pages.length} ${pages.length == 1 ? "صفحة ممسوحة" : "صفحات ممسوحة"}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        actions: [
          if (pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: FilledButton.icon(
                onPressed: _isSavingSession ? null : _saveAndFinish,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'حفظ وإنهاء',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: pages.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSavingSession ? null : _startScan,
              backgroundColor: palette.accent,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text(
                'التقاط أول صفحة',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
      body: Stack(
        children: [
          sessionState.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ShimmerSkeleton(height: 86, borderRadius: 16),
                SizedBox(height: 12),
                Row(
                  children: [
                    ShimmerSkeleton(width: 86, height: 124, borderRadius: 14),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          ShimmerSkeleton(height: 14, borderRadius: 8),
                          SizedBox(height: 8),
                          SizedBox(
                            width: 180,
                            child: ShimmerSkeleton(height: 12, borderRadius: 8),
                          ),
                          SizedBox(height: 10),
                          ShimmerSkeleton(height: 34, borderRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ShimmerSkeleton(height: 130, borderRadius: 16),
                SizedBox(height: 12),
                ShimmerSkeleton(height: 130, borderRadius: 16),
              ],
            ),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
            data: (_) {
              if (pages.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                palette.accent.withValues(alpha: 0.16),
                                palette.accent.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh
                                    : Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.accent.withValues(
                                      alpha: 0.1,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: palette.accent.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.document_scanner_rounded,
                                size: 44,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'جاهز للمسح الضوئي',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'ابدأ بمسح أول صفحة. بعد التقاط كل صفحة، يمكنك تدويرها أو إعادة مسحها أو ترتيب الصفحات كما يحلو لك.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.7),
                                  height: 1.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  // ── Apple Top Info Strip ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.2 : 0.03,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.touch_app_rounded,
                              size: 16,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'اسحب لإعادة الترتيب • اضغط على الصفحة للتعديل والقص',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: _isSavingSession ? null : _importFromGallery,
                            style: TextButton.styleFrom(
                              foregroundColor: palette.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.add_photo_alternate_rounded, size: 15),
                            label: const Text(
                              'المعرض',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Apple Clean Reorderable Page Cards ──
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                      itemCount: pages.length,
                      // ignore: deprecated_member_use
                      onReorder: _isSavingSession
                          ? (_, _) {}
                          : (oldIndex, newIndex) => ref
                                .read(scanSessionControllerProvider.notifier)
                                .reorderPages(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        return Container(
                          key: ValueKey(page.id),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.04,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Header: Page number, Paper Size, Drag Handle, Delete ──
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'صفحة ${index + 1}',
                                        style: TextStyle(
                                          color: palette.accent,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<DocumentPaperSize>(
                                      enabled: !_isSavingSession,
                                      tooltip: 'تغيير مقاس الصفحة',
                                      onSelected: (size) {
                                        ref
                                            .read(scanSessionControllerProvider.notifier)
                                            .updatePagePaperSize(page.id, size);
                                      },
                                      itemBuilder: (_) => DocumentPaperSize.values
                                          .map(
                                            (s) => PopupMenuItem(
                                              value: s,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    s == page.paperSize
                                                        ? Icons.radio_button_checked_rounded
                                                        : Icons.radio_button_off_rounded,
                                                    size: 16,
                                                    color: palette.accent,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(s.label),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : Colors.black.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              page.paperSize.label,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? Colors.white70
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.arrow_drop_down_rounded,
                                              size: 16,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.drag_indicator_rounded,
                                      size: 20,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'حذف الصفحة',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                        color: palette.danger.withValues(alpha: 0.8),
                                      ),
                                      onPressed: _isSavingSession
                                          ? null
                                          : () => ref
                                                .read(scanSessionControllerProvider.notifier)
                                                .deletePage(page.id),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.05),
                              ),

                              // ── Content: Thumbnail Preview + Apple Action Grid ──
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: _isSavingSession
                                          ? null
                                          : () => _editPage(page),
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: 100,
                                            height: 135,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.12)
                                                    : Colors.black.withValues(alpha: 0.08),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(
                                                    alpha: isDark ? 0.3 : 0.08,
                                                  ),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(13),
                                              child: Image.file(
                                                File(page.imagePath),
                                                width: 100,
                                                height: 135,
                                                fit: BoxFit.cover,
                                                cacheWidth: 300,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 6,
                                            right: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.75),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.crop_rotate_rounded,
                                                    size: 11,
                                                    color: Colors.white,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'تعديل',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildAppleCardActionTile(
                                                  icon: Icons.tune_rounded,
                                                  label: 'قص وفلاتر',
                                                  color: palette.accent,
                                                  onTap: _isSavingSession
                                                      ? null
                                                      : () => _editPage(page),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildAppleCardActionTile(
                                                  icon: Icons.draw_rounded,
                                                  label: 'توقيع',
                                                  color: const Color(0xFF34C759),
                                                  onTap: _isSavingSession
                                                      ? null
                                                      : () => _openSignatureFlow(page),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildAppleCardActionTile(
                                                  icon: Icons.rotate_right_rounded,
                                                  label: 'تدوير',
                                                  color: const Color(0xFFFF9500),
                                                  onTap: _isSavingSession
                                                      ? null
                                                      : () => ref
                                                            .read(
                                                              scanSessionControllerProvider
                                                                  .notifier,
                                                            )
                                                            .rotatePage(page.id),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildAppleCardActionTile(
                                                  icon: Icons.cameraswitch_rounded,
                                                  label: 'إعادة التقاط',
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black87,
                                                  onTap: _isSavingSession
                                                      ? null
                                                      : () => _startScan(
                                                          replacePageId: page.id,
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          _buildAppleCardActionTile(
                                            icon: Icons.auto_stories_rounded,
                                            label: 'فصل صفحتين (كتاب / مجلد)',
                                            color: const Color(0xFF5856D6),
                                            isFullWidth: true,
                                            onTap: _isSavingSession
                                                ? null
                                                : () => _splitBookPageFlow(page),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Apple Floating Control Dock ──
          if (pages.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isDark
                              ? const Color(0xFF1E1E24)
                              : Colors.white)
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.35 : 0.12,
                          ),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Gallery Button
                        InkWell(
                          onTap: _isSavingSession ? null : _importFromGallery,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.photo_library_rounded, size: 18, color: palette.accent),
                                const SizedBox(width: 6),
                                const Text(
                                  'المعرض',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Primary Camera Snap Button
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSavingSession ? null : () => _startScan(),
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 19),
                            label: const Text(
                              'التقاط صفحة',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Save & Finish Button
                        InkWell(
                          onTap: _isSavingSession ? null : _saveAndFinish,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF34C759)),
                                SizedBox(width: 6),
                                Text(
                                  'إنهاء',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF34C759),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Modern Frosted-Glass PDF Saving Modal ──
          if (_isSavingSession)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.48),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 310),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E24).withValues(
                                    alpha: 0.94,
                                  )
                                : Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: palette.accent.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 66,
                                    height: 66,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3.5,
                                      color: palette.accent,
                                    ),
                                  ),
                                  Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 30,
                                    color: palette.accent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'جارٍ حفظ المستند',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Consumer(
                                builder: (ctx, ref, _) {
                                  final progress = ref.watch(
                                    scanSaveProgressProvider,
                                  );
                                  return AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: Text(
                                      key: ValueKey(progress),
                                      progress.isNotEmpty
                                          ? progress
                                          : 'يتم دمج الصفحات بأعلى جودة...',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 5,
                                  color: palette.accent,
                                  backgroundColor: palette.accent.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (_isLoadingScanner)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E24)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: palette.accent),
                            const SizedBox(height: 14),
                            const Text(
                              'جارٍ فتح الكاميرا الذكية...',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppleCardActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool isFullWidth = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: color.withValues(alpha: isDark ? 0.12 : 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.25 : 0.18),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: isFullWidth
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

