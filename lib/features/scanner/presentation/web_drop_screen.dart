import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/providers/providers.dart';
import '../data/local_web_drop_service.dart';
import '../data/transferred_files_service.dart';
import 'transferred_files_screen.dart';

/// Screen for Local AirDrop / Web Drop:
/// Running an embedded local HTTP server on the phone so any PC, Mac, iPad, or
/// phone on the same Wi-Fi can view, download PDFs, and send files to the phone
/// 100% offline without cables or internet.
///
/// Features:
/// 1. Sleek Apple Cupertino visual design with live radar wave broadcast.
/// 2. Pick any file from phone to share directly to PC / other phone.
/// 3. Pick from app scan library to stage for instant download.
/// 4. High-contrast QR code and 1-tap copy/share IP address.
/// 5. Live activity stream and list of received uploads from computer.
class WebDropScreen extends ConsumerStatefulWidget {
  const WebDropScreen({super.key});

  @override
  ConsumerState<WebDropScreen> createState() => _WebDropScreenState();
}

class _WebDropScreenState extends ConsumerState<WebDropScreen> {
  final LocalWebDropService _webDropService = LocalWebDropService.instance;
  final TransferredFilesService _transferredFilesService =
      TransferredFilesService.instance;
  bool _isStarting = false;
  bool _showQrCode = false;
  bool _isImportingFiles = false;
  String _importStatusText = '';

  List<TransferredFile> _receivedFiles = [];
  StreamSubscription<List<SharedDropFile>>? _stagedSubscription;
  DropTransferProgress? _activeTransfer;
  StreamSubscription<DropTransferProgress?>? _transferSubscription;

  @override
  void initState() {
    super.initState();
    _stagedSubscription = _webDropService.stagedFilesStream.listen((_) {
      if (mounted) setState(() {});
    });

    _activeTransfer = _webDropService.activeTransfer;
    _transferSubscription =
        _webDropService.transferProgressStream.listen((transfer) {
      if (mounted) {
        setState(() {
          _activeTransfer = transfer;
        });
        if (transfer != null && transfer.isCompleted) {
          HapticFeedback.mediumImpact();
          _loadRecentTransferred();
        }
      }
    });

    _loadRecentTransferred();
    // Server starts in OFF state by default so the user controls it manually
  }

  Future<void> _loadRecentTransferred() async {
    final all = await _transferredFilesService.loadFiles();
    if (mounted) {
      setState(() {
        _receivedFiles = all.where((f) => f.isReceived).take(5).toList();
      });
    }
  }

  @override
  void dispose() {
    _stagedSubscription?.cancel();
    _transferSubscription?.cancel();
    _webDropService.stopServer();
    super.dispose();
  }

  Future<void> _startServer() async {
    if (_webDropService.isRunning || _isStarting) return;
    setState(() => _isStarting = true);

    try {
      await _webDropService.startServer(
        getDocuments: () {
          return ref.read(pendingUploadsControllerProvider).value ?? [];
        },
        onFileUploaded: _handleUploadedFileFromPc,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر بدء خادم المشاركة المحلي: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _stopServer() async {
    await _webDropService.stopServer();
    if (mounted) setState(() {});
  }

  Future<void> _toggleServer() async {
    HapticFeedback.mediumImpact();
    if (_webDropService.isRunning) {
      await _stopServer();
    } else {
      await _startServer();
    }
  }

  Future<void> _handleUploadedFileFromPc(
      String fileName, List<int> bytes) async {
    try {
      final cleanName =
          fileName.replaceAll(RegExp(r'[^\w\.\-\u0600-\u06FF]'), '_');

      final item = await _transferredFilesService.recordReceivedFile(
        fileName: cleanName,
        bytes: bytes,
      );

      if (mounted) {
        setState(() {
          _receivedFiles.insert(0, item);
        });
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.download_done_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('📥 تم استقبال ملف من الكمبيوتر: $cleanName'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[WebDropScreen] Error saving uploaded file: $e');
    }
  }

  void _copyUrlToClipboard() {
    final url = _webDropService.serverUrl;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('تم نسخ الرابط بنجاح: $url')),
          ],
        ),
        backgroundColor: const Color(0xFF007AFF),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareUrl() {
    final url = _webDropService.serverUrl;
    HapticFeedback.lightImpact();
    Share.share(
      'افتح هذا الرابط في متصفح الكمبيوتر أو الماك أو أي جهاز آخر لنقل المستندات فوراً:\n$url',
      subject: 'رابط نقل المستندات عبر الشبكة المحلية (Web Drop)',
    );
  }

  Future<void> _pickExternalFiles() async {
    if (_isImportingFiles) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isImportingFiles = true;
      _importStatusText = 'جارٍ فتح مستعرض ملفات الهاتف...';
    });

    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (res != null && res.files.isNotEmpty) {
        final totalCount = res.files.length;
        int added = 0;

        for (int i = 0; i < res.files.length; i++) {
          final f = res.files[i];
          if (mounted) {
            setState(() {
              _importStatusText =
                  'جارٍ استيراد (${i + 1}/$totalCount): ${f.name} (${SharedDropFile.formatBytes(f.size)})...';
            });
          }

          if (f.path != null) {
            final drop = SharedDropFile(
              id: 'staged_${DateTime.now().millisecondsSinceEpoch}_${f.name.hashCode}',
              name: f.name,
              filePath: f.path!,
              fileSize: f.size,
              sharedAt: DateTime.now(),
              mimeType: lookupDropMimeType(f.name),
              isFromAppLibrary: false,
            );
            _webDropService.addStagedFile(drop);
            added++;
          }
        }

        if (mounted) {
          setState(() {
            _isImportingFiles = false;
            _importStatusText = '';
          });
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('تم استيراد $added ملف بنجاح • متاح للتحميل فوراً على الكمبيوتر!'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF34C759),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isImportingFiles = false;
            _importStatusText = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImportingFiles = false;
          _importStatusText = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر اختيار الملفات: $e')),
        );
      }
    }
  }

  void _pickLibraryDocuments() {
    HapticFeedback.lightImpact();
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة لمشاركتها')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_shared_rounded,
                        color: Color(0xFF007AFF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اختر مستنداً من المكتبة لمشاركته',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        Text(
                          'سيظهر فوراً للتحميل المباشر كـ PDF في المتصفح',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final doc = docs[idx];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded,
                          color: Color(0xFFFF2D55), size: 20),
                    ),
                    title: Text(
                      doc.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${doc.pageCount} صفحات • ${(doc.fileSize / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.add_circle_outline_rounded,
                        color: Color(0xFF007AFF)),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      setState(() {
                        _isImportingFiles = true;
                        _importStatusText = 'جارٍ تجهيز مستند "${doc.fileName}"...';
                      });
                      final drop = SharedDropFile(
                        id: 'doc_${doc.id}',
                        name: doc.fileName,
                        filePath: doc.filePath,
                        fileSize: doc.fileSize,
                        sharedAt: DateTime.now(),
                        mimeType: 'application/pdf',
                        isFromAppLibrary: true,
                      );
                      _webDropService.addStagedFile(drop);
                      if (mounted) {
                        setState(() {
                          _isImportingFiles = false;
                          _importStatusText = '';
                        });
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '✅ تمت إضافة "${doc.fileName}" للتحميل الفوري على الكمبيوتر!'),
                            backgroundColor: const Color(0xFF34C759),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return Icons.image_rounded;
      case '.xlsx':
      case '.xls':
        return Icons.table_chart_rounded;
      case '.docx':
      case '.doc':
        return Icons.description_rounded;
      case '.zip':
      case '.rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return const Color(0xFFFF2D55);
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return const Color(0xFF8B5CF6);
      case '.xlsx':
      case '.xls':
        return const Color(0xFF34C759);
      case '.docx':
      case '.doc':
        return const Color(0xFF007AFF);
      case '.zip':
      case '.rar':
        return const Color(0xFFFF9500);
      default:
        return const Color(0xFF5856D6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRunning = _webDropService.isRunning;
    final url = _webDropService.serverUrl;
    final staged = _webDropService.stagedFiles;
    final events = _webDropService.events;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'خادم المشاركة اللاسلكي (Web Drop)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              isRunning
                  ? 'بث مباشر على الشبكة المحلية • أوفلاين 100%'
                  : 'السيرفر متوقف حالياً',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isRunning ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'الملفات المنقولة',
            icon: const Icon(Icons.folder_shared_rounded, color: Color(0xFF007AFF)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TransferredFilesScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'تحديث الرابط وعنوان الشبكة',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              HapticFeedback.selectionClick();
              await _stopServer();
              await _startServer();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Compact Hero Connection Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isRunning
                      ? const Color(0xFF34C759).withValues(alpha: 0.35)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08)),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isRunning ? const Color(0xFF34C759) : Colors.black)
                        .withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRunning
                              ? const Color(0xFF34C759).withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.15),
                        ),
                        child: Center(
                          child: Icon(
                            isRunning
                                ? Icons.wifi_tethering_rounded
                                : Icons.wifi_tethering_off_rounded,
                            color: isRunning
                                ? const Color(0xFF34C759)
                                : Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRunning
                                  ? 'خادم المشاركة نشط'
                                  : 'خادم المشاركة متوقف',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isRunning
                                  ? 'بث مباشر على Wi-Fi • أوفلاين 100%'
                                  : 'اضغط على المفتاح لتشغيل البث',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: isRunning,
                        activeTrackColor: const Color(0xFF34C759),
                        onChanged: _isStarting ? null : (_) => _toggleServer(),
                      ),
                    ],
                  ),

                  // Prominent Manual Start Button when server is OFF
                  if (!isRunning) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF34C759),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: _isStarting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.power_settings_new_rounded, size: 20),
                        label: Text(
                          _isStarting
                              ? 'جارٍ تشغيل الخادم...'
                              : 'تشغيل خادم المشاركة الآن',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: _isStarting ? null : () => _startServer(),
                      ),
                    ),
                  ],

                  if (isRunning) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Compact High-Contrast URL Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : const Color(0xFFF0F5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded,
                              color: Color(0xFF007AFF), size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              url,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'نشط ⚡',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Uniform 3-Button Action Row (Exact same height: 38px, radius: 10px)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: FilledButton.tonalIcon(
                              onPressed: _copyUrlToClipboard,
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('نسخ الرابط',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: FilledButton.tonalIcon(
                              onPressed: _shareUrl,
                              icon: const Icon(Icons.ios_share_rounded, size: 15),
                              label: const Text('مشاركة',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _showQrCode = !_showQrCode);
                              },
                              icon: Icon(
                                  _showQrCode ? Icons.qr_code_rounded : Icons.qr_code_2_rounded,
                                  size: 16),
                              label: Text(_showQrCode ? 'إخفاء QR' : 'رمز QR',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: _showQrCode
                                    ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                                    : null,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Expandable QR Code Box
                    if (_showQrCode) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.25)
                              : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: SizedBox(
                                width: 130,
                                height: 130,
                                child: CustomPaint(
                                  painter: _QrPainter(
                                    data: url,
                                    darkColor: const Color(0xFF111827),
                                    lightColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'امسح الكود بكاميرا الهاتف أو اللابتوب للاتصال الفوري',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // ── Live Transfer Progress Indicator Card ──
            if (_activeTransfer != null) ...[
              const SizedBox(height: 14),
              _buildLiveTransferCard(isDark, _activeTransfer!),
            ],

            const SizedBox(height: 14),

            // ── 2. Unified Send to PC Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.send_to_mobile_rounded,
                          color: Color(0xFF007AFF),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إرسال ملفات للكمبيوتر والأجهزة',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              'اختر أي ملف ليظهر فوراً في المتصفح للتحميل السريع',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Action Buttons: Two perfectly balanced buttons (Height: 40px, Radius: 12px)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: FilledButton.icon(
                            onPressed: _isImportingFiles ? null : _pickExternalFiles,
                            icon: _isImportingFiles
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.file_upload_outlined, size: 17),
                            label: Text(
                              _isImportingFiles ? 'جارٍ الاستيراد...' : 'ملف من الهاتف',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: FilledButton.tonalIcon(
                            onPressed: _isImportingFiles ? null : _pickLibraryDocuments,
                            icon: const Icon(Icons.folder_shared_outlined, size: 17),
                            label: const Text(
                              'من المستندات',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Live Importing Progress Banner for large files
                  if (_isImportingFiles) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'جارٍ استيراد وتجهيز الملف للمشاركة...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (_importStatusText.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _importStatusText,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Staged Files List (Live queue available to PC)
                  if (staged.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded,
                            color: Color(0xFF34C759), size: 15),
                        const SizedBox(width: 4),
                        Text(
                          'جاهز للتحميل بالمتصفح (${staged.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Color(0xFF34C759),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _webDropService.clearStagedFiles();
                          },
                          child: const Text(
                            'مسح الكل',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: staged.length,
                      itemBuilder: (ctx, idx) {
                        final item = staged[idx];
                        final icon = _getFileIcon(item.name);
                        final iconColor = _getFileColor(item.name);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF34C759).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(icon, color: iconColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '${item.formattedSize} • متاح للتحميل',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 16, color: Colors.grey),
                                tooltip: 'إلغاء المشاركة',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _webDropService.removeStagedFile(item.id);
                                },
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
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

            const SizedBox(height: 14),

            // ── 3. Received Files Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.download_done_rounded,
                          color: Color(0xFF34C759),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'الملفات المستلمة من الكمبيوتر',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const Spacer(),
                      if (_receivedFiles.isNotEmpty)
                        Text(
                          '${_receivedFiles.length} ملفات',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_receivedFiles.isNotEmpty) ...[
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _receivedFiles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final item = _receivedFiles[idx];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Color(0xFF34C759), size: 18),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                          subtitle: Text(
                            '${item.formattedSize} • محفوظة محلياً',
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 17),
                            tooltip: 'فتح الملف',
                            onPressed: () => OpenFilex.open(item.filePath),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TransferredFilesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.folder_shared_rounded, size: 16),
                        label: const Text('عرض كافة الملفات المنقولة في صفحة مخصصة 📂',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black.withValues(alpha: 0.15) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_empty_rounded, size: 18, color: Colors.grey.shade400),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'بانتظار استقبال ملفات من المتصفح... يمكنك سحب وإفلات أي ملف في صفحة الويب.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── 4. Compact Collapsible Instructions & Activity ──
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.lightbulb_outline_rounded,
                      size: 18, color: Color(0xFFFF9500)),
                  title: const Text(
                    'كيف يعمل النقل فائق السرعة؟ (3 خطوات)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    _buildCompactStepRow('1', 'تأكد أن الهاتف والكمبيوتر على نفس شبكة Wi-Fi أو نقطة اتصال هاتفك.'),
                    const SizedBox(height: 6),
                    _buildCompactStepRow('2', 'افتح المتصفح (Chrome أو Edge أو Safari) واكتب عنوان الرابط أعلاه.'),
                    const SizedBox(height: 6),
                    _buildCompactStepRow('3', 'تصفح مستنداتك وحملها كـ PDF فوراً أو اسحب أي ملف لإرساله للهاتف.'),
                  ],
                ),
              ),
            ),

            if (events.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const Icon(Icons.sync_alt_rounded,
                        size: 18, color: Color(0xFF007AFF)),
                    title: Text(
                      'سجل النشاط المباشر (${events.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    children: [
                      ...events.take(6).map((item) {
                        final isUpload = item.type == 'upload';
                        final isDownload = item.type == 'download';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: (isUpload
                                        ? const Color(0xFF34C759)
                                        : (isDownload
                                            ? const Color(0xFF007AFF)
                                            : Colors.grey))
                                    .withValues(alpha: 0.15),
                                child: Icon(
                                  isUpload
                                      ? Icons.file_download_rounded
                                      : (isDownload
                                          ? Icons.file_upload_rounded
                                          : Icons.language_rounded),
                                  size: 11,
                                  color: isUpload
                                      ? const Color(0xFF34C759)
                                      : (isDownload
                                          ? const Color(0xFF007AFF)
                                          : Colors.grey),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.message,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTransferCard(bool isDark, DropTransferProgress transfer) {
    final isSending = transfer.direction == DropTransferDirection.sendingToPc;
    final isDone = transfer.isCompleted;
    final themeColor = isDone
        ? const Color(0xFF34C759)
        : (isSending ? const Color(0xFF007AFF) : const Color(0xFF34C759));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: themeColor.withValues(alpha: isDone ? 0.6 : 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: isDark ? 0.25 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (isSending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded),
                  color: themeColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDone
                          ? 'اكتمل النقل بنجاح'
                          : (isSending
                              ? 'جارٍ إرسال الملف للكمبيوتر...'
                              : 'جارٍ استقبال ملف من الكمبيوتر...'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      transfer.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${transfer.percent}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: themeColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: isDone ? 1.0 : transfer.fraction,
              minHeight: 8,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isDone
                      ? '⚡ محفوظ ومتاح الآن في مركز الملفات'
                      : '⚡ نقل لاسلكي محلي عالي السرعة',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                transfer.progressDetail,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: themeColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Offline Custom Painter that draws a sharp QR code matrix on the Canvas
class _QrPainter extends CustomPainter {
  _QrPainter({
    required this.data,
    required this.darkColor,
    required this.lightColor,
  }) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    _qrImage = QrImage(qrCode);
  }

  final String data;
  final Color darkColor;
  final Color lightColor;
  late final QrImage _qrImage;

  @override
  void paint(Canvas canvas, Size size) {
    final count = _qrImage.moduleCount;
    if (count <= 0) return;

    final moduleSize = size.width / count;
    final darkPaint = Paint()
      ..color = darkColor
      ..isAntiAlias = true;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        if (_qrImage.isDark(y, x)) {
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize + 0.3,
            moduleSize + 0.3,
          );
          // Slightly rounded modules for premium Apple look
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(moduleSize * 0.25)),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.darkColor != darkColor ||
        oldDelegate.lightColor != lightColor;
  }
}
