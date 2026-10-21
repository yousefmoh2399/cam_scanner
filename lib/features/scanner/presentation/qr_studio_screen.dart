import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/motion_tokens.dart';
import '../data/native_scanner_bridge.dart';
import '../data/qr_scanner_service.dart';

/// Categories / types of QR codes that can be generated offline
enum QrStudioType {
  wifi('واي فاي', Icons.wifi_rounded),
  vcard('بطاقة أعمال', Icons.badge_rounded),
  url('رابط ويب', Icons.link_rounded),
  whatsapp('واتساب', Icons.chat_rounded),
  phone('اتصال هاتفي', Icons.call_rounded),
  email('بريد إلكتروني', Icons.mail_rounded),
  text('نص حر', Icons.notes_rounded);

  const QrStudioType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Offline Barcode & QR Studio Screen:
/// Generates instant, highly customizable QR codes with custom styling,
/// center logo badge, and offline export/print features.
class QrStudioScreen extends StatefulWidget {
  const QrStudioScreen({super.key});

  @override
  State<QrStudioScreen> createState() => _QrStudioScreenState();
}

class _QrStudioScreenState extends State<QrStudioScreen> {
  QrStudioType _selectedType = QrStudioType.wifi;

  // Controllers for Wi-Fi
  final TextEditingController _wifiSsidCtrl =
      TextEditingController(text: 'MyHome_WiFi');
  final TextEditingController _wifiPasswordCtrl =
      TextEditingController(text: 'Password123');
  String _wifiAuth = 'WPA'; // WPA, WEP, nopass
  bool _wifiHidden = false;

  // Controllers for vCard
  final TextEditingController _vcardNameCtrl =
      TextEditingController(text: 'محمد أحمد');
  final TextEditingController _vcardPhoneCtrl =
      TextEditingController(text: '+201012345678');
  final TextEditingController _vcardEmailCtrl =
      TextEditingController(text: 'mohamed@example.com');
  final TextEditingController _vcardCompanyCtrl =
      TextEditingController(text: 'شركة الرواد');
  final TextEditingController _vcardTitleCtrl =
      TextEditingController(text: 'مدير تنفيذي');
  final TextEditingController _vcardUrlCtrl =
      TextEditingController(text: 'https://example.com');

  // Controllers for URL
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://laqta.app');

  // Controllers for WhatsApp
  final TextEditingController _waPhoneCtrl =
      TextEditingController(text: '+201012345678');
  final TextEditingController _waMessageCtrl =
      TextEditingController(text: 'مرحباً، أود الاستفسار عن...');

  // Controllers for Phone
  final TextEditingController _phoneCtrl =
      TextEditingController(text: '+201012345678');

  // Controllers for Email
  final TextEditingController _emailAddressCtrl =
      TextEditingController(text: 'contact@example.com');
  final TextEditingController _emailSubjectCtrl =
      TextEditingController(text: 'استفسار رسمي');
  final TextEditingController _emailBodyCtrl =
      TextEditingController(text: 'تحية طيبة وبعد،');

  // Controllers for Text
  final TextEditingController _plainTextCtrl =
      TextEditingController(text: 'لقطة - الماسح الضوئي الاحترافي');

  // Customization Options
  Color _darkColor = const Color(0xFF000000);
  Color _lightColor = const Color(0xFFFFFFFF);
  bool _includeLogo = true;
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isExporting = false;

  final List<Color> _foregroundPresets = const [
    Color(0xFF000000), // Pure Black
    Color(0xFF007AFF), // Apple Blue
    Color(0xFF10B981), // Emerald
    Color(0xFF5856D6), // Indigo
    Color(0xFFFF2D55), // Crimson
    Color(0xFFFF9500), // Amber
    Color(0xFF1C1C1E), // Slate
  ];

  final List<Color> _backgroundPresets = const [
    Color(0xFFFFFFFF), // White
    Color(0xFFF2F2F7), // Apple System Gray
    Color(0xFFFFFBEB), // Warm Ivory
    Color(0xFFEFF6FF), // Soft Blue
    Color(0xFFF3E8FF), // Lavender
  ];

  @override
  void dispose() {
    _wifiSsidCtrl.dispose();
    _wifiPasswordCtrl.dispose();
    _vcardNameCtrl.dispose();
    _vcardPhoneCtrl.dispose();
    _vcardEmailCtrl.dispose();
    _vcardCompanyCtrl.dispose();
    _vcardTitleCtrl.dispose();
    _vcardUrlCtrl.dispose();
    _urlCtrl.dispose();
    _waPhoneCtrl.dispose();
    _waMessageCtrl.dispose();
    _phoneCtrl.dispose();
    _emailAddressCtrl.dispose();
    _emailSubjectCtrl.dispose();
    _emailBodyCtrl.dispose();
    _plainTextCtrl.dispose();
    super.dispose();
  }

  String _buildQrPayload() {
    switch (_selectedType) {
      case QrStudioType.wifi:
        final ssid = _wifiSsidCtrl.text.trim();
        final pass = _wifiPasswordCtrl.text.trim();
        final auth = _wifiAuth;
        final hidden = _wifiHidden ? 'H:true;' : '';
        return 'WIFI:T:$auth;S:$ssid;P:$pass;$hidden;';

      case QrStudioType.vcard:
        final name = _vcardNameCtrl.text.trim();
        final phone = _vcardPhoneCtrl.text.trim();
        final email = _vcardEmailCtrl.text.trim();
        final company = _vcardCompanyCtrl.text.trim();
        final title = _vcardTitleCtrl.text.trim();
        final url = _vcardUrlCtrl.text.trim();
        final buf = StringBuffer()
          ..writeln('BEGIN:VCARD')
          ..writeln('VERSION:3.0')
          ..writeln('FN:$name')
          ..writeln('N:$name');
        if (company.isNotEmpty) buf.writeln('ORG:$company');
        if (title.isNotEmpty) buf.writeln('TITLE:$title');
        if (phone.isNotEmpty) buf.writeln('TEL:$phone');
        if (email.isNotEmpty) buf.writeln('EMAIL:$email');
        if (url.isNotEmpty) buf.writeln('URL:$url');
        buf.write('END:VCARD');
        return buf.toString();

      case QrStudioType.url:
        String u = _urlCtrl.text.trim();
        if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) {
          u = 'https://$u';
        }
        return u;

      case QrStudioType.whatsapp:
        final phone = _waPhoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
        final msg = Uri.encodeComponent(_waMessageCtrl.text.trim());
        return 'https://wa.me/$phone?text=$msg';

      case QrStudioType.phone:
        final phone = _phoneCtrl.text.trim();
        return 'tel:$phone';

      case QrStudioType.email:
        final email = _emailAddressCtrl.text.trim();
        final sub = Uri.encodeComponent(_emailSubjectCtrl.text.trim());
        final body = Uri.encodeComponent(_emailBodyCtrl.text.trim());
        return 'mailto:$email?subject=$sub&body=$body';

      case QrStudioType.text:
        return _plainTextCtrl.text.trim();
    }
  }

  Future<Uint8List?> _captureQrImageBytes() async {
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[QrStudio] Capture error: $e');
      return null;
    }
  }

  Future<void> _exportAsPng() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    HapticFeedback.lightImpact();

    try {
      final bytes = await _captureQrImageBytes();
      if (bytes == null) {
        throw StateError('تعذر التقاط صورة الرمز');
      }

      final tempDir = await getTemporaryDirectory();
      final outDir = Directory(p.join(tempDir.path, 'Exports'));
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final file = File(p.join(
        outDir.path,
        'QR_${_selectedType.name}_${DateTime.now().millisecondsSinceEpoch}.png',
      ));
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('تم حفظ صورة الرمز بنجاح: ${p.basename(file.path)}')),
              ],
            ),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(file.path)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareQrCode() async {
    HapticFeedback.lightImpact();
    final bytes = await _captureQrImageBytes();
    if (bytes == null) return;

    final tempDir = await getTemporaryDirectory();
    final file = File(p.join(
      tempDir.path,
      'QR_Code_${DateTime.now().millisecondsSinceEpoch}.png',
    ));
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'رمز QR (${_selectedType.label}) - تم إنشاؤه عبر تطبيق لقطة',
    );
  }

  Future<void> _printOrExportPdf() async {
    HapticFeedback.lightImpact();
    final bytes = await _captureQrImageBytes();
    if (bytes == null) return;

    final doc = pw.Document();
    final qrPdfImage = pw.MemoryImage(bytes);
    final payload = _buildQrPayload();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'رمز استجابة سريعة (QR Code)',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'النوع: ${_selectedType.label}',
                  style: const pw.TextStyle(
                    fontSize: 13,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 260,
                  height: 260,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 1),
                    borderRadius: pw.BorderRadius.circular(16),
                  ),
                  child: pw.Image(qrPdfImage),
                ),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 320,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    payload,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey800,
                    ),
                    maxLines: 4,
                  ),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'تم الإنشاء والطباعة بدقة فائقة عبر تطبيق "لقطة" (Laqta Scanner)',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'QR_${_selectedType.name}_Laqta.pdf',
    );
  }

  void _copyPayload() {
    HapticFeedback.lightImpact();
    final text = _buildQrPayload();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ محتوى الرمز للحافظة بنجاح'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _scanQrCode() async {
    HapticFeedback.mediumImpact();
    final source = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: Color(0xFF007AFF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('مسح وقراءة رمز QR أو باركود',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('امسح عبر الكاميرا أو اختر صورة من المعرض',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildModalSourceCard(
                      ctx: ctx,
                      icon: Icons.camera_alt_rounded,
                      title: 'كاميرا الهاتف',
                      subtitle: 'مسح فوري الآن',
                      color: const Color(0xFF34C759),
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'camera');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModalSourceCard(
                      ctx: ctx,
                      icon: Icons.photo_library_rounded,
                      title: 'ألبوم الصور',
                      subtitle: 'لقطة أو صورة',
                      color: const Color(0xFF5856D6),
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx, 'gallery');
                      },
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

    if (source == null || !mounted) return;

    String? targetPath;
    if (source == 'camera') {
      try {
        final tmpDir = await getTemporaryDirectory();
        final res = await NativeScannerBridge.startSingleScan(
          destDir: tmpDir.path,
        );
        if (res == null || !mounted) return;
        targetPath = res.path;
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) await showScannerPermissionDialog(context, e);
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
        return;
      }
    } else if (source == 'gallery') {
      try {
        final res = await FilePicker.platform.pickFiles(type: FileType.image);
        if (res == null ||
            res.files.isEmpty ||
            res.files.first.path == null ||
            !mounted) {
          return;
        }
        targetPath = res.files.first.path!;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر اختيار الصورة: $e')),
          );
        }
        return;
      }
    }

    if (targetPath == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(width: 16),
                Text('جارٍ فحص الرمز...',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ],
            ),
          ),
        ),
      ),
    );

    final payload = await QrScannerService.instance.scanImage(targetPath);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (payload == null || payload.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child:
                      Text('لم يتم العثور على رمز QR أو باركود واضح في الصورة.'),
                ),
              ],
            ),
            backgroundColor: Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    await QrScannerService.instance.handleScannedPayload(
      context: context,
      payload: payload,
    );
  }

  Widget _buildModalSourceCard({
    required BuildContext ctx,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final payload = _buildQrPayload();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'منشئ رموز QR والباركود الذكي',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'توليد وتخصيص وطباعة بدقة وجودة عالية',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF34C759),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'مسح رمز QR أو باركود',
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF007AFF)),
            onPressed: _scanQrCode,
          ),
          IconButton(
            tooltip: 'طباعة فورية',
            icon: const Icon(Icons.print_rounded),
            onPressed: _printOrExportPdf,
          ),
          IconButton(
            tooltip: 'مشاركة الرمز',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _shareQrCode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Apple Squircle Type Selector Carousel ──
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: QrStudioType.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, idx) {
                  final t = QrStudioType.values[idx];
                  final isSel = t == _selectedType;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedType = t);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF007AFF)
                              : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFF007AFF)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06)),
                            width: 0.5,
                          ),
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              t.icon,
                              size: 16,
                              color: isSel ? Colors.white : const Color(0xFF007AFF),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              t.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                color: isSel
                                    ? Colors.white
                                    : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── 2. Apple Studio Live QR Hero Card ──
            Center(
              child: Container(
                width: 290,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Badge inside Preview Card
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(_selectedType.icon, size: 15, color: const Color(0xFF007AFF)),
                            const SizedBox(width: 6),
                            Text(
                              _selectedType.label,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(radius: 3, backgroundColor: Color(0xFF34C759)),
                              SizedBox(width: 5),
                              Text(
                                'جاهز للمسح',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF34C759),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Live QR Matrix View
                    RepaintBoundary(
                      key: _qrBoundaryKey,
                      child: Container(
                        width: 220,
                        height: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lightColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                            width: 0.8,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 196,
                              height: 196,
                              child: CustomPaint(
                                painter: _StudioQrPainter(
                                  data: payload.isEmpty ? 'LAQTA' : payload,
                                  darkColor: _darkColor,
                                  lightColor: _lightColor,
                                  includeLogoBadge: _includeLogo,
                                ),
                              ),
                            ),

                            // Center Logo Cutout Badge
                            if (_includeLogo)
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _lightColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: _darkColor.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.asset(
                                      'assets/images/app_icon.png',
                                      width: 30,
                                      height: 30,
                                      errorBuilder: (_, __, ___) => Icon(
                                        _selectedType.icon,
                                        color: _darkColor,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Inset Payload Summary & Copy Bar
                    InkWell(
                      onTap: _copyPayload,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF007AFF)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                payload.isEmpty ? 'لا توجد بيانات بعد' : payload,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8E8E93),
                                ),
                              ),
                            ),
                            const Text(
                              'نسخ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF007AFF),
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

            const SizedBox(height: 16),

            // ── Primary Action Buttons: Balanced 50% / 50% ──
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : _exportAsPng,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text(
                        'حفظ صورة (PNG)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                        foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _printOrExportPdf,
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text(
                        'طباعة ومشاركة (PDF)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── 3. Content Form Inputs According to Selected Type ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_selectedType.icon,
                          color: const Color(0xFF007AFF), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'بيانات ${_selectedType.label}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildInputFormForCurrentType(isDark),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── 4. Styling & Customization Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.palette_rounded,
                          color: Color(0xFF8B5CF6), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'تخصيص الألوان والمظهر',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Foreground Color Swatches
                  const Text(
                    'لون الرمز (Foreground):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _foregroundPresets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (ctx, idx) {
                        final c = _foregroundPresets[idx];
                        final isSel = _darkColor == c;
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _darkColor = c);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: [
                                if (isSel)
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                              ],
                            ),
                            child: isSel
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Background Color Swatches
                  const Text(
                    'لون الخلفية (Background):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _backgroundPresets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (ctx, idx) {
                        final c = _backgroundPresets[idx];
                        final isSel = _lightColor == c;
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _lightColor = c);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel
                                    ? const Color(0xFF007AFF)
                                    : Colors.black26,
                                width: isSel ? 2.5 : 1,
                              ),
                            ),
                            child: isSel
                                ? const Icon(Icons.check,
                                    color: Color(0xFF007AFF), size: 18)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Center Logo Toggle
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_rounded,
                            color: Color(0xFF10B981), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إضافة شعار التطبيق في المنتصف',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            Text(
                              'علامة مميزة تمنح الرمز مظهراً رسمياً وموثوقاً',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _includeLogo,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() => _includeLogo = val);
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
    );
  }

  Widget _buildInputFormForCurrentType(bool isDark) {
    switch (_selectedType) {
      case QrStudioType.wifi:
        return Column(
          children: [
            _buildTextField(
              controller: _wifiSsidCtrl,
              label: 'اسم شبكة الواي فاي (SSID)',
              icon: Icons.wifi_rounded,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _wifiPasswordCtrl,
              label: 'كلمة مرور الشبكة',
              icon: Icons.lock_outline_rounded,
              isPassword: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _wifiAuth,
                    decoration: InputDecoration(
                      labelText: 'نوع التشفير',
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'WPA', child: Text('WPA/WPA2/WPA3')),
                      DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                      DropdownMenuItem(
                          value: 'nopass', child: Text('بدون كلمة سر (مفتوحة)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _wifiAuth = val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('شبكة مخفية:',
                        style: TextStyle(fontSize: 12)),
                    Checkbox.adaptive(
                      value: _wifiHidden,
                      onChanged: (val) =>
                          setState(() => _wifiHidden = val ?? false),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

      case QrStudioType.vcard:
        return Column(
          children: [
            _buildTextField(
              controller: _vcardNameCtrl,
              label: 'الاسم بالكامل',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _vcardPhoneCtrl,
              label: 'رقم الهاتف',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _vcardEmailCtrl,
              label: 'البريد الإلكتروني',
              icon: Icons.email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _vcardCompanyCtrl,
                    label: 'الشركة / المؤسسة',
                    icon: Icons.business_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    controller: _vcardTitleCtrl,
                    label: 'المسمى الوظيفي',
                    icon: Icons.work_outline_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _vcardUrlCtrl,
              label: 'الموقع الإلكتروني',
              icon: Icons.language_rounded,
              keyboardType: TextInputType.url,
            ),
          ],
        );

      case QrStudioType.url:
        return Column(
          children: [
            _buildTextField(
              controller: _urlCtrl,
              label: 'رابط الموقع أو المستند',
              icon: Icons.link_rounded,
              keyboardType: TextInputType.url,
            ),
          ],
        );

      case QrStudioType.whatsapp:
        return Column(
          children: [
            _buildTextField(
              controller: _waPhoneCtrl,
              label: 'رقم الهاتف (مع كود الدولة مثل +20)',
              icon: Icons.phone_android_rounded,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _waMessageCtrl,
              label: 'الرسالة المسبقة (اختياري)',
              icon: Icons.message_rounded,
              maxLines: 2,
            ),
          ],
        );

      case QrStudioType.phone:
        return Column(
          children: [
            _buildTextField(
              controller: _phoneCtrl,
              label: 'رقم الهاتف للاتصال المباشر',
              icon: Icons.call_rounded,
              keyboardType: TextInputType.phone,
            ),
          ],
        );

      case QrStudioType.email:
        return Column(
          children: [
            _buildTextField(
              controller: _emailAddressCtrl,
              label: 'عنوان البريد الإلكتروني',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _emailSubjectCtrl,
              label: 'موضوع الرسالة',
              icon: Icons.subject_rounded,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _emailBodyCtrl,
              label: 'نص الرسالة',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
          ],
        );

      case QrStudioType.text:
        return Column(
          children: [
            _buildTextField(
              controller: _plainTextCtrl,
              label: 'أدخل أي نص أو ملاحظات أو أرقام تسلسلية',
              icon: Icons.notes_rounded,
              maxLines: 4,
            ),
          ],
        );
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Custom painter for the QR matrix that respects foreground/background color,
/// rounded modules, and reserves center space for the logo badge
class _StudioQrPainter extends CustomPainter {
  _StudioQrPainter({
    required this.data,
    required this.darkColor,
    required this.lightColor,
    required this.includeLogoBadge,
  }) {
    // If logo badge is included, use High error correction (30% redundancy)
    final errorLevel =
        includeLogoBadge ? QrErrorCorrectLevel.H : QrErrorCorrectLevel.M;
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: errorLevel,
    );
    _qrImage = QrImage(qrCode);
  }

  final String data;
  final Color darkColor;
  final Color lightColor;
  final bool includeLogoBadge;
  late final QrImage _qrImage;

  @override
  void paint(Canvas canvas, Size size) {
    final count = _qrImage.moduleCount;
    if (count <= 0) return;

    final moduleSize = size.width / count;
    final darkPaint = Paint()
      ..color = darkColor
      ..isAntiAlias = true;

    // Center exclusion boundary for logo (around 22% of matrix)
    final centerIdx = count / 2.0;
    final logoRadiusModules = includeLogoBadge ? (count * 0.15) : 0.0;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        // Skip modules under the central badge
        if (includeLogoBadge) {
          final dx = (x + 0.5) - centerIdx;
          final dy = (y + 0.5) - centerIdx;
          if ((dx * dx + dy * dy) < (logoRadiusModules * logoRadiusModules)) {
            continue;
          }
        }

        if (_qrImage.isDark(y, x)) {
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize + 0.35,
            moduleSize + 0.35,
          );
          // Rounded modules for Apple sleek aesthetic
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(moduleSize * 0.28)),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StudioQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.darkColor != darkColor ||
        oldDelegate.lightColor != lightColor ||
        oldDelegate.includeLogoBadge != includeLogoBadge;
  }
}
