import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../data/native_scanner_bridge.dart';

/// Screen for Lanyard ID Badge Generator (صانع كارنيهات العمل وشارات الزوار)
/// Generates standard 54x86 mm plastic holder badges with photo, QR code,
/// lanyard punch slot, and physical 1:1 scale PDF print sheet.
class LanyardIdBadgeScreen extends ConsumerStatefulWidget {
  const LanyardIdBadgeScreen({super.key});

  @override
  ConsumerState<LanyardIdBadgeScreen> createState() =>
      _LanyardIdBadgeScreenState();
}

class _LanyardIdBadgeScreenState extends ConsumerState<LanyardIdBadgeScreen> {
  final TextEditingController _nameCtrl =
      TextEditingController(text: 'م. أحمد خالد الشريف');
  final TextEditingController _roleCtrl =
      TextEditingController(text: 'كبير مهندسي البرمجيات');
  final TextEditingController _orgCtrl =
      TextEditingController(text: 'مجموعة التقنية المتقدمة');
  final TextEditingController _idNumberCtrl =
      TextEditingController(text: 'EMP-9082');

  String? _photoPath;
  final bool _isVertical = true;
  Color _themeColor = const Color(0xFF007AFF);
  String _badgeType = 'موظف معتمد'; // 'موظف معتمد', 'زائر VIP', 'منظم فعالية'
  bool _isProcessing = false;

  final List<Color> _availableColors = const [
    Color(0xFF007AFF), // Corporate Blue
    Color(0xFF10B981), // Emerald Green
    Color(0xFF8B5CF6), // Royal Purple
    Color(0xFF1E293B), // Executive Slate
    Color(0xFFD97706), // Amber Gold
    Color(0xFFDC2626), // Certified Crimson
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _orgCtrl.dispose();
    _idNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    HapticFeedback.lightImpact();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _photoPath = result.files.single.path!);
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _capturePhoto() async {
    HapticFeedback.lightImpact();
    try {
      final scanned = await NativeScannerBridge.startScan();
      if (scanned.isNotEmpty) {
        setState(() => _photoPath = scanned.first.path);
        HapticFeedback.lightImpact();
      }
    } catch (_) {
      await _pickPhoto();
    }
  }

  Future<void> _exportPrintSheet() async {
    HapticFeedback.lightImpact();
    setState(() => _isProcessing = true);

    try {
      final doc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      // Standard badge dimensions: 54mm x 86mm in points (72dpi: 1mm = 2.83465 pt)
      const badgeWidthPt = 54.0 * 2.83465;
      const badgeHeightPt = 86.0 * 2.83465;

      pw.MemoryImage? photoImg;
      if (_photoPath != null && File(_photoPath!).existsSync()) {
        final bytes = await File(_photoPath!).readAsBytes();
        photoImg = pw.MemoryImage(bytes);
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'كارنيه تعريف بمقياس 1:1 حقيقي لحوامل الكروت البلاستيكية (54×86 ملم)',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                    pw.SizedBox(height: 12),

                    // Badge Container with physical size
                    pw.Container(
                      width: _isVertical ? badgeWidthPt : badgeHeightPt,
                      height: _isVertical ? badgeHeightPt : badgeWidthPt,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.grey400, width: 1),
                      ),
                      child: pw.Column(
                        children: [
                          // Top Header with Theme Color
                          pw.Container(
                            height: 48,
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.blue800,
                              borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(7)),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                _orgCtrl.text.trim(),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          // Lanyard punch hole mark
                          pw.Container(
                            margin: const pw.EdgeInsets.only(top: 6),
                            width: 14,
                            height: 3,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey300,
                              borderRadius: pw.BorderRadius.circular(2),
                            ),
                          ),

                          pw.SizedBox(height: 10),

                          // Photo
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              border: pw.Border.all(color: PdfColors.blue700, width: 2),
                            ),
                            child: photoImg != null
                                ? pw.ClipOval(child: pw.Image(photoImg, fit: pw.BoxFit.cover))
                                : pw.Center(
                                    child: pw.Text(
                                      'صورة',
                                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                                    ),
                                  ),
                          ),

                          pw.SizedBox(height: 10),

                          // Name & Role
                          pw.Text(
                            _nameCtrl.text.trim(),
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.Text(
                            _roleCtrl.text.trim(),
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),

                          pw.Spacer(),

                          // Badge Type & ID Barcode
                          pw.Container(
                            margin: const pw.EdgeInsets.symmetric(horizontal: 12),
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey200,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                '$_badgeType • ${_idNumberCtrl.text.trim()}',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.blueGrey800,
                                ),
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 8),
                        ],
                      ),
                    ),

                    pw.SizedBox(height: 20),
                    pw.Text(
                      'خطوط القص: قص على الإطار الخارجي بالضبط لوضع الكارنيه داخل الحامل البلاستيكي.',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/كارنيه_معتمد_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(outPath);
      await file.writeAsBytes(await doc.save());

      HapticFeedback.lightImpact();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('تم إنشاء شيت الطباعة 1:1', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              'تم حفظ ملف الكارنيه بمقاس الجيب الفيزيائي الحقيقي:\n${outPath.split(Platform.pathSeparator).last}',
              style: const TextStyle(fontSize: 12.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(outPath)]);
                },
                child: const Text('مشاركة'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(outPath);
                },
                child: const Text('فتح الملف'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'صانع كارنيهات العمل والزوار',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'مقاس حوامل الكروت القياسي (54×86 ملم) بمقياس 1:1',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_rounded),
            tooltip: 'التقاط صورة شخصية',
            onPressed: _capturePhoto,
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'طباعة وتصدير',
            onPressed: _exportPrintSheet,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Interactive Badge Preview
                Center(
                  child: Container(
                    width: _isVertical ? 220 : 320,
                    height: _isVertical ? 340 : 220,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: _themeColor.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Lanyard Slot Cutout Hole
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 32,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black54 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),

                        // Header Bar
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          color: _themeColor,
                          child: Text(
                            _orgCtrl.text.trim(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Photo Avatar with InkWell
                        InkWell(
                          onTap: _pickPhoto,
                          borderRadius: BorderRadius.circular(40),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: _themeColor.withValues(alpha: 0.15),
                                backgroundImage: _photoPath != null && File(_photoPath!).existsSync()
                                    ? FileImage(File(_photoPath!))
                                    : null,
                                child: _photoPath == null
                                    ? Icon(Icons.person_rounded, size: 40, color: _themeColor)
                                    : null,
                              ),
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: _themeColor,
                                child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Name & Role
                        Text(
                          _nameCtrl.text.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        Text(
                          _roleCtrl.text.trim(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),

                        const Spacer(),

                        // Bottom Section: Badge Type & QR Pass
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _themeColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _badgeType,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                      color: _themeColor,
                                    ),
                                  ),
                                  Text(
                                    _idNumberCtrl.text.trim(),
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                              _BadgeQrWidget(
                                data: '${_idNumberCtrl.text}|${_nameCtrl.text}',
                                size: 36,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Theme Color Palette
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _availableColors.map((color) {
                    final isSelected = _themeColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _themeColor = color);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Card Customization Fields
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'الاسم الكامل',
                            prefixIcon: const Icon(Icons.badge_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _roleCtrl,
                          decoration: InputDecoration(
                            labelText: 'المسمى الوظيفي / الصفة',
                            prefixIcon: const Icon(Icons.work_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _orgCtrl,
                          decoration: InputDecoration(
                            labelText: 'اسم المؤسسة / الفعالية',
                            prefixIcon: const Icon(Icons.business_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _idNumberCtrl,
                                decoration: InputDecoration(
                                  labelText: 'الرقم التعريفي (ID)',
                                  prefixIcon: const Icon(Icons.tag_rounded),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _badgeType,
                                isExpanded: true,
                                isDense: true,
                                decoration: InputDecoration(
                                  labelText: 'نوع الشارة',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'موظف معتمد', child: Text('موظف معتمد', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'زائر VIP', child: Text('زائر VIP', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'منظم فعالية', child: Text('منظم فعالية', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _badgeType = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action Export Button
                FilledButton.icon(
                  icon: const Icon(Icons.print_rounded),
                  label: const Text(
                    'تصدير شيت الطباعة 1:1 لمقاس الحامل البلاستيكي',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  onPressed: _exportPrintSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: _themeColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator.adaptive()),
            ),
        ],
      ),
    );
  }
}

class _BadgeQrWidget extends StatelessWidget {
  const _BadgeQrWidget({required this.data, this.size = 36});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);

      return CustomPaint(
        size: Size(size, size),
        painter: _BadgeQrPainter(qrImage: qrImage, color: Colors.black),
      );
    } catch (_) {
      return Icon(Icons.qr_code_2_rounded, size: size);
    }
  }
}

class _BadgeQrPainter extends CustomPainter {
  _BadgeQrPainter({required this.qrImage, required this.color});
  final QrImage qrImage;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final count = qrImage.moduleCount;
    if (count <= 0) return;
    final moduleSize = size.width / count;
    final paint = Paint()..color = color..isAntiAlias = true;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        if (qrImage.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * moduleSize, y * moduleSize, moduleSize + 0.2, moduleSize + 0.2),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
