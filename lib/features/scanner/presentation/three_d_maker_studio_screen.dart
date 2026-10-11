import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../data/models/three_d_scan_models.dart';
import '../data/three_d_reconstruction_service.dart';
import 'three_d_guided_capture_screen.dart';
import 'three_d_mesh_viewer_screen.dart';

/// Central 3D Maker Studio Hub for 3D Printing & Scanning.
class ThreeDMakerStudioScreen extends StatefulWidget {
  const ThreeDMakerStudioScreen({super.key});

  @override
  State<ThreeDMakerStudioScreen> createState() => _ThreeDMakerStudioScreenState();
}

class _ThreeDMakerStudioScreenState extends State<ThreeDMakerStudioScreen> {
  List<ThreeDReconstructionResult> _savedScans = [];
  bool _isLoading = true;
  bool _isGeneratingDemo = false;

  @override
  void initState() {
    super.initState();
    _loadSavedScans();
  }

  Future<void> _loadSavedScans() async {
    setState(() => _isLoading = true);
    final scans = await ThreeDReconstructionService.getSavedScans();
    if (mounted) {
      setState(() {
        _savedScans = scans;
        _isLoading = false;
      });
    }
  }

  Future<void> _generateDemoCube() async {
    HapticFeedback.mediumImpact();
    setState(() => _isGeneratingDemo = true);

    try {
      final res = await ThreeDReconstructionService.generateCalibrationSpecimen(
        title: 'مكعب_معايرة_50مم',
        specimenType: 'cube_50mm',
      );

      if (mounted) {
        setState(() => _isGeneratingDemo = false);
        _loadSavedScans();

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreeDMeshViewerScreen(result: res),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingDemo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل توليد النموذج التجريبي: $e')),
        );
      }
    }
  }

  Future<void> _pickExternalStl() async {
    HapticFeedback.selectionClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.stl')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى اختيار ملف بامتداد .stl صالح')),
          );
        }
        return;
      }

      final file = File(path);
      final modelResult = ThreeDReconstructionResult(
        stlPath: path,
        title: p.basenameWithoutExtension(path),
        vertexCount: 0,
        triangleCount: (file.lengthSync() - 84) ~/ 50,
        dimX: 50.0,
        dimY: 50.0,
        dimZ: 50.0,
        isWatertight: true,
        durationMs: 0,
        createdAt: file.lastModifiedSync(),
        fileSizeBytes: file.lengthSync(),
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreeDMeshViewerScreen(result: modelResult),
          ),
        );
      }
    }
  }

  Future<void> _printMat() async {
    HapticFeedback.selectionClick();
    try {
      await ThreeDReconstructionService.printCharucoCalibrationMat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء إرسال الطباعة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101216),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181B22),
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.view_in_ar_rounded, color: Color(0xFF00E676), size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'استوديو الطباعة ثلاثية الأبعاد (3D)',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSavedScans,
        color: const Color(0xFF00E676),
        backgroundColor: const Color(0xFF1E222B),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero Studio Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E2430), Color(0xFF131720)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'أوفلاين 100% • مقياس متري 1:1',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.precision_manufacturing_rounded, color: Colors.white38, size: 22),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'مسح ثلاثي الأبعاد هندسي عالي الدقة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'امسح قطع الغيار والمجسمات بكاميرا الموبايل واستخرج ملف STL صلب (Watertight) جاهز لبرامج التقطيع Cura و PrusaSlicer.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  // Primary CTA: Start New Scan
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ThreeDGuidedCaptureScreen(),
                          ),
                        ).then((_) => _loadSavedScans());
                      },
                      icon: const Icon(Icons.camera_rounded, size: 20),
                      label: const Text(
                        'بدء مسح قطعة جديدة (New 3D Scan)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Quick Studio Actions Row
            Row(
              children: [
                // Action 1: Print ChArUco mat
                Expanded(
                  child: _StudioQuickActionCard(
                    title: 'ورقة المعايرة',
                    subtitle: 'طباعة ChArUco A4',
                    icon: Icons.print_rounded,
                    accentColor: const Color(0xFF448AFF),
                    onTap: _printMat,
                  ),
                ),
                const SizedBox(width: 12),
                // Action 2: Demo 50mm Cube
                Expanded(
                  child: _StudioQuickActionCard(
                    title: 'مكعب تجريبي',
                    subtitle: _isGeneratingDemo ? 'جارٍ التوليد...' : 'معاينة STL 50 مم',
                    icon: Icons.view_in_ar_rounded,
                    accentColor: const Color(0xFFFF9100),
                    onTap: _isGeneratingDemo ? null : _generateDemoCube,
                  ),
                ),
                const SizedBox(width: 12),
                // Action 3: Open External STL
                Expanded(
                  child: _StudioQuickActionCard(
                    title: 'استيراد STL',
                    subtitle: 'فتح ملف خارجي',
                    icon: Icons.folder_open_rounded,
                    accentColor: const Color(0xFFE040FB),
                    onTap: _pickExternalStl,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Saved Models Section Header
            Row(
              children: [
                const Text(
                  'المجسمات المحفوظة (STL Models)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_savedScans.length} ملفات',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              )
            else if (_savedScans.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF161920),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.layers_clear_rounded, size: 48, color: Colors.white24),
                    const SizedBox(height: 12),
                    const Text(
                      'لا توجد مجسمات 3D ممسوحة بعد',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'ابدأ جلسة مسح جديدة أو اضغط على "مكعب تجريبي" بالأعلى لاختبار العارض ثلاثي الأبعاد وتصدير STL الآن.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _generateDemoCube,
                      icon: const Icon(Icons.add_box_rounded, size: 16),
                      label: const Text('توليد مكعب معايرة 50 مم تجريبي'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00E676),
                        side: const BorderSide(color: Color(0xFF00E676)),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(_savedScans.length, (idx) {
                final item = _savedScans[idx];
                return _ScanResultCard(
                  result: item,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ThreeDMeshViewerScreen(result: item),
                      ),
                    );
                    _loadSavedScans();
                  },
                  onDelete: () => _confirmDelete(item),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(ThreeDReconstructionResult item) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('حذف المجسم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'هل تريد حذف مجسم "${item.title}" نهائياً من الجهاز؟\nلن يمكن التراجع عن هذا الإجراء.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              final file = File(item.stlPath);
              if (file.existsSync()) file.deleteSync();
              _loadSavedScans();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف المجسم بنجاح')),
              );
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }
}

class _StudioQuickActionCard extends StatelessWidget {
  const _StudioQuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161920),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({
    required this.result,
    required this.onTap,
    required this.onDelete,
  });

  final ThreeDReconstructionResult result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161920),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.view_in_ar_rounded, color: Color(0xFF00E676), size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${result.formattedDimensions} • ${result.triangleCount} مثلث',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF00E676), fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'حجم الملف: ${result.formattedFileSize}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white54, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    tooltip: 'مشاركة ملف STL',
                    onPressed: () {
                      final file = File(result.stlPath);
                      if (file.existsSync()) {
                        Share.shareXFiles([XFile(file.path, mimeType: 'model/stl')]);
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    tooltip: 'حذف',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
