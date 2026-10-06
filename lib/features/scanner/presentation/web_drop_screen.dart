import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/local_web_drop_service.dart';

/// Screen for Local AirDrop / Web Drop:
/// Running an embedded local HTTP server on the phone so any PC, Mac, iPad, or
/// phone on the same Wi-Fi can view, download PDFs, and send files to the phone
/// 100% offline without cables or internet.
class WebDropScreen extends ConsumerStatefulWidget {
  const WebDropScreen({super.key});

  @override
  ConsumerState<WebDropScreen> createState() => _WebDropScreenState();
}

class _WebDropScreenState extends ConsumerState<WebDropScreen>
    with SingleTickerProviderStateMixin {
  final LocalWebDropService _webDropService = LocalWebDropService.instance;
  bool _isStarting = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startServer();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
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

  Future<void> _handleUploadedFileFromPc(String fileName, List<int> bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(dir.path, 'scans', 'web_drop_uploads'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final cleanName = fileName.replaceAll(RegExp(r'[^\w\.\-\u0600-\u06FF]'), '_');
      final filePath = p.join(
        targetDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$cleanName',
      );
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      // Save as document in app
      final doc = PendingUpload(
        id: 'webdrop_${DateTime.now().millisecondsSinceEpoch}',
        fileName: cleanName,
        filePath: filePath,
        fileSize: bytes.length,
        createdAt: DateTime.now(),
        pageCount: 1,
        thumbnailPath: null,
        pages: [
          ScanPage(
            id: 'p_webdrop_0',
            imagePath: filePath,
          ),
        ],
      );

      await ref.read(pendingUploadsControllerProvider.notifier).addDocument(doc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📥 تم استقبال ملف جديد من الكمبيوتر: $cleanName'),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
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
            Text('تم نسخ الرابط بنجاح: $url'),
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
      'افتح هذا الرابط في متصفح الكمبيوتر أو الماك لنقل المستندات فوراً:\n$url',
      subject: 'رابط نقل المستندات عبر الشبكة المحلية (Web Drop)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRunning = _webDropService.isRunning;
    final url = _webDropService.serverUrl;
    final events = _webDropService.events;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'نقل للكمبيوتر محلياً (Web Drop)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث الرابط والشبكة',
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Connection Status Card ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isRunning
                      ? const Color(0xFF34C759).withValues(alpha: 0.35)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isRunning ? const Color(0xFF34C759) : Colors.black)
                        .withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Pulsing status indicator
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isRunning
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFF8E8E93))
                              .withValues(
                            alpha: isRunning
                                ? 0.15 + (_pulseAnimation.value * 0.15)
                                : 0.12,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            isRunning
                                ? Icons.wifi_tethering_rounded
                                : Icons.wifi_tethering_off_rounded,
                            color: isRunning
                                ? const Color(0xFF34C759)
                                : const Color(0xFF8E8E93),
                            size: 26,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRunning
                              ? 'خادم المشاركة قيد التشغيل'
                              : 'خادم المشاركة متوقف',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isRunning
                              ? 'جاهز لاستقبال الاتصالات من متصفح أي كمبيوتر'
                              : 'اضغط على الزر للبدء بالنقل عبر الشبكة',
                          style: TextStyle(
                            fontSize: 12,
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
            ),

            const SizedBox(height: 18),

            // ── URL & QR Code Card (When Running) ──
            if (isRunning) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E2433), const Color(0xFF161922)]
                        : [const Color(0xFFF0F5FF), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'العنوان المحلي للمتصفح',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // High-contrast URL badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.5)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: SelectableText(
                        url,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Action buttons (Copy & Share)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _copyUrlToClipboard,
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('نسخ الرابط'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _shareUrl,
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: const Text('مشاركة الرابط'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // QR Code Presentation
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CustomPaint(
                              painter: _QrPainter(
                                data: url,
                                darkColor: const Color(0xFF090D16),
                                lightColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'وجّه كاميرا الهاتف أو اللابتوب للمسح المباشر',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3A3A3C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── Live Transfer Activity Log ──
            if (events.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.sync_alt_rounded, size: 18, color: Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Text(
                      'سجل النشاط المباشر',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${events.length} عمليات',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = events[idx];
                    final isDownload = item.type == 'download';
                    final isUpload = item.type == 'upload';

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: (isUpload
                                ? const Color(0xFF34C759)
                                : (isDownload
                                    ? const Color(0xFF007AFF)
                                    : const Color(0xFF8E8E93)))
                            .withValues(alpha: 0.15),
                        child: Icon(
                          isUpload
                              ? Icons.file_download_rounded
                              : (isDownload
                                  ? Icons.file_upload_rounded
                                  : Icons.language_rounded),
                          size: 16,
                          color: isUpload
                              ? const Color(0xFF34C759)
                              : (isDownload
                                  ? const Color(0xFF007AFF)
                                  : const Color(0xFF8E8E93)),
                        ),
                      ),
                      title: Text(
                        item.message,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── Visual Guide Steps (Apple Cards) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'كيف يعمل النقل المحلي (Web Drop)؟',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            _buildGuideCard(
              isDark: isDark,
              number: '1',
              title: 'الاتصال بنفس الشبكة',
              subtitle:
                  'تأكد أن الكمبيوتر والهاتف متصلان بنفس شبكة الـ Wi-Fi المنزلية أو بنقطة اتصال الهاتف (Hotspot).',
              icon: Icons.wifi_rounded,
              color: const Color(0xFF007AFF),
            ),
            const SizedBox(height: 10),
            _buildGuideCard(
              isDark: isDark,
              number: '2',
              title: 'فتح الرابط في المتصفح',
              subtitle:
                  'افتح Chrome أو Safari أو Edge على الكمبيوتر واكتب الرابط أعلاه، أو امسح الباركود بكاميرا الماك/اللابتوب.',
              icon: Icons.open_in_browser_rounded,
              color: const Color(0xFF5856D6),
            ),
            const SizedBox(height: 10),
            _buildGuideCard(
              isDark: isDark,
              number: '3',
              title: 'تنزيل ورفع المستندات فوراً',
              subtitle:
                  'ستظهر لوحة تحكم أنيقة بكل مستنداتك لتحميلها بنقرة واحدة كـ PDF، أو سحب أي ملفات جديدة من الكمبيوتر لهاتفك.',
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF34C759),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard({
    required bool isDark,
    required String number,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
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
