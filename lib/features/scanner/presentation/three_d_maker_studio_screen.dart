import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _checkAndShowBetaNotice();
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

  Future<void> _checkAndShowBetaNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hide = prefs.getBool('hide_3d_maker_beta_notice') ?? false;
      if (!hide && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showBetaNoticeBottomSheet(isManualTrigger: false);
          }
        });
      }
    } catch (_) {}
  }

  void _showBetaNoticeBottomSheet({bool isManualTrigger = false}) {
    bool doNotShowAgain = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF181B22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 25,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Scrollable Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header with Beta Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.science_rounded,
                                    color: Colors.black,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'استوديو النحت والمسح 3D',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                                width: 1,
                                              ),
                                            ),
                                            child: const Text(
                                              'BETA 0.9',
                                              style: TextStyle(
                                                color: Color(0xFFF59E0B),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'إصدار تجريبي قيد التطوير والترقية المستمرة',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                                  onPressed: () => Navigator.pop(bottomSheetContext),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Explanatory Banner
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2430),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.privacy_tip_outlined, color: Color(0xFF00E676), size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'معالجة محلية 100% دون اتصال بالإنترنت',
                                        style: TextStyle(
                                          color: Color(0xFF00E676),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'نظام المسح وتحويل المنتجات والمجسمات إلى ملفات ثلاثية الأبعاد (STL Models) يعمل حالياً بنسخته التجريبية المعتمدة على الرؤية الحاسوبية المباشرة (On-Device Computer Vision) لضمان الخصوصية التامة لكافة بياناتك وتصميماتك بدون إرسال أي صورة لخوادم خارجية.\n\nنعمل بصورة دورية على ترقية خوارزميات الذكاء الاصطناعي وبناء شبكات المضلعات ثلاثية الأبعاد المعقدة في التحديثات القادمة.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.5,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Tips Section Header
                            const Text(
                              '💡 نصائح للحصول على أدق مجسم 3D في هذه النسخة:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Tip 1: Transparent PNG
                            _buildBetaTipItem(
                              icon: Icons.image_search_rounded,
                              iconColor: const Color(0xFF00E676),
                              title: 'استخدام صور PNG مفرغة (الأعلى دقة)',
                              subtitle: 'إذا توفرت صور للمنتج بخلفية شفافة، سيقرأ المحرك طبقة الـ Alpha مباشرة لبناء مجسم متقن وفوري خالي من التشتيت والظلال.',
                            ),
                            const SizedBox(height: 8),

                            // Tip 2: A4 Paper
                            _buildBetaTipItem(
                              icon: Icons.aspect_ratio_rounded,
                              iconColor: const Color(0xFF00B0FF),
                              title: 'ورقة المعايرة البيضاء (A4)',
                              subtitle: 'عند مسح منتج حقيقي بالكاميرا، ضعه في منتصف ورقة A4 بيضاء سادة لمساعدة المحرك على قياس الأبعاد الحقيقية بالمليمتر وعزل الجسم.',
                            ),
                            const SizedBox(height: 8),

                            // Tip 3: Lighting & Angle
                            _buildBetaTipItem(
                              icon: Icons.wb_sunny_rounded,
                              iconColor: const Color(0xFFFFB300),
                              title: 'إضاءة واضحة وزاوية تصوير 35°',
                              subtitle: 'التقط الصور في إضاءة متجانسة وزاوية مائلة (35° إلى 45°) لإظهار بروز الأزرار والعدسات والتفاصيل السطحية بوضوح.',
                            ),
                            const SizedBox(height: 8),

                            // Tip 4: STL Watertight
                            _buildBetaTipItem(
                              icon: Icons.print_rounded,
                              iconColor: const Color(0xFFAB47BC),
                              title: 'ملفات STL متماسكة للطباعة ثلاثية الأبعاد',
                              subtitle: 'جميع النماذج المنتجة مغلقة هندسياً (Watertight Manifold) وتُحفظ بصيغة .stl القياسية لتتمكن من فتحها في برامج السلايسر (Cura/Prusa).',
                            ),
                            const SizedBox(height: 16),

                            // Checkbox: Don't show again
                            Material(
                              color: const Color(0xFF101216),
                              borderRadius: BorderRadius.circular(14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: Colors.white12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CheckboxListTile(
                                value: doNotShowAgain,
                                activeColor: const Color(0xFF00E676),
                                checkColor: Colors.black,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                title: const Text(
                                  'عدم إظهار هذه الرسالة التوضيحية مرة أخرى',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  'يمكنك دائماً مراجعة هذه النصائح بالضغط على شارة BETA في أعلى الشاشة',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                onChanged: (val) {
                                  setSheetState(() {
                                    doNotShowAgain = val ?? false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Confirmation Button
                            ElevatedButton.icon(
                              onPressed: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('hide_3d_maker_beta_notice', doNotShowAgain);
                                if (bottomSheetContext.mounted) {
                                  Navigator.pop(bottomSheetContext);
                                }
                              },
                              icon: const Icon(Icons.check_circle_rounded, size: 20),
                              label: const Text(
                                'فهمت ذلك، ابدأ التجربة',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C853),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBetaTipItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  Future<void> _pickProductImagesAndReconstruct() async {
    HapticFeedback.selectionClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: true,
    );

    if (result == null || result.paths.isEmpty) return;
    final validPaths = result.paths.whereType<String>().toList();
    if (validPaths.isEmpty) return;

    if (mounted) {
      _showProductReconstructSheet(validPaths);
    }
  }

  void _showProductReconstructSheet(List<String> initialPaths) {
    final List<String> currentPaths = List.from(initialPaths);
    final String defaultTitle = initialPaths.isNotEmpty
        ? 'مجسم_${p.basenameWithoutExtension(initialPaths.first)}'
        : 'مجسم_منتج';
    final TextEditingController titleController = TextEditingController(text: defaultTitle);
                    double selectedVoxelSize = 1.4;
                    String selectedObjectType = 'auto';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final int count = currentPaths.length;
            final bool hasPng = currentPaths.any((p) => p.toLowerCase().endsWith('.png'));

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF00E676),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'تحويل صور المنتج إلى مجسم 3D',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'تجميع الصور ونحت المجسم 360° أوفلاين بالكامل',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Transparency / Feature notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasPng
                            ? const Color(0xFF00E676).withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasPng
                              ? const Color(0xFF00E676).withValues(alpha: 0.3)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasPng ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            color: hasPng ? const Color(0xFF00E676) : Colors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasPng
                                  ? 'تم اكتشاف صور PNG! سيتم استخراج الشفافية بدقة 100% لعزل فوري ونحت 3D بدون تشويش.'
                                  : 'للحصول على مجسم 360° دقيق، يُفضل 3 صور أو أكثر بزوايا مختلفة حول المنتج أو بصيغة PNG مفرغة.',
                              style: TextStyle(
                                color: hasPng ? Colors.white : Colors.white70,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Thumbnails Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الصور المحددة ($count)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final added = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                              allowMultiple: true,
                            );
                            if (added != null) {
                              final newPaths = added.paths.whereType<String>();
                              setSheetState(() {
                                currentPaths.addAll(newPaths);
                              });
                            }
                          },
                          icon: const Icon(Icons.add_photo_alternate_rounded, size: 16, color: Color(0xFF00E676)),
                          label: const Text(
                            'إضافة صور',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Thumbnails Row
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: currentPaths.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, idx) {
                          final imgPath = currentPaths[idx];
                          final isPng = imgPath.toLowerCase().endsWith('.png');

                          return Stack(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isPng
                                        ? const Color(0xFF00E676).withValues(alpha: 0.6)
                                        : Colors.white24,
                                  ),
                                  color: Colors.black26,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.file(
                                  File(imgPath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image, color: Colors.white24, size: 24),
                                  ),
                                ),
                              ),
                              if (isPng)
                                Positioned(
                                  bottom: 10,
                                  left: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E676),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'PNG',
                                      style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setSheetState(() {
                                      currentPaths.removeAt(idx);
                                    });
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close, color: Colors.redAccent, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title Input
                    const Text(
                      'اسم المجسم 3D',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF101216),
                        hintText: 'مثال: علبة_سماعات_3D',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Object Profile Selection
                    const Text(
                      'نوع المجسم (Object Profile)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            selected: selectedObjectType == 'auto',
                            label: const Text('تلقائي (كشف ذكي)'),
                            selectedColor: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF101216),
                            labelStyle: TextStyle(
                              color: selectedObjectType == 'auto' ? Colors.black87 : Colors.white70,
                              fontWeight: selectedObjectType == 'auto' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) => setSheetState(() => selectedObjectType = 'auto'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            selected: selectedObjectType == 'smartphone',
                            label: const Text('📱 هاتف ذكي'),
                            selectedColor: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF101216),
                            labelStyle: TextStyle(
                              color: selectedObjectType == 'smartphone' ? Colors.black87 : Colors.white70,
                              fontWeight: selectedObjectType == 'smartphone' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) => setSheetState(() => selectedObjectType = 'smartphone'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            selected: selectedObjectType == 'box',
                            label: const Text('📦 علبة / منتج'),
                            selectedColor: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF101216),
                            labelStyle: TextStyle(
                              color: selectedObjectType == 'box' ? Colors.black87 : Colors.white70,
                              fontWeight: selectedObjectType == 'box' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) => setSheetState(() => selectedObjectType = 'box'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            selected: selectedObjectType == 'freeform',
                            label: const Text('⚙️ قطعة حرة / CAD'),
                            selectedColor: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF101216),
                            labelStyle: TextStyle(
                              color: selectedObjectType == 'freeform' ? Colors.black87 : Colors.white70,
                              fontWeight: selectedObjectType == 'freeform' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) => setSheetState(() => selectedObjectType = 'freeform'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quality Selection
                    const Text(
                      'دقة النحت الشبكي (Voxel Resolution)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildQualityChip(
                          label: 'فائق (1.2 مم)',
                          selected: selectedVoxelSize == 1.2,
                          onTap: () => setSheetState(() => selectedVoxelSize = 1.2),
                        ),
                        const SizedBox(width: 8),
                        _buildQualityChip(
                          label: 'متوازن (1.4 مم)',
                          selected: selectedVoxelSize == 1.4,
                          onTap: () => setSheetState(() => selectedVoxelSize = 1.4),
                        ),
                        const SizedBox(width: 8),
                        _buildQualityChip(
                          label: 'سريع (2.0 مم)',
                          selected: selectedVoxelSize == 2.0,
                          onTap: () => setSheetState(() => selectedVoxelSize = 2.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Build Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: currentPaths.isEmpty
                            ? null
                            : () {
                                final title = titleController.text.trim().isEmpty
                                    ? defaultTitle
                                    : titleController.text.trim();
                                Navigator.pop(bottomSheetContext);
                                _startProductReconstruction(
                                  paths: currentPaths,
                                  title: title,
                                  voxelSizeMm: selectedVoxelSize,
                                  objectType: selectedObjectType,
                                );
                              },
                        icon: const Icon(Icons.view_in_ar_rounded, size: 20),
                        label: Text(
                          'بدء بناء المجسم 3D (${currentPaths.length} صور)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildQualityChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E676).withValues(alpha: 0.15) : const Color(0xFF101216),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF00E676) : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? const Color(0xFF00E676) : Colors.white70,
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startProductReconstruction({
    required List<String> paths,
    required String title,
    required double voxelSizeMm,
    String objectType = 'auto',
  }) async {
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.05);
    final ValueNotifier<String> statusNotifier =
        ValueNotifier('جارٍ قراءة الصور وتحليل القنوات والأقنعة...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: const Color(0xFF181B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: Color(0xFF00E676),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'جارٍ بناء المجسم ثلاثي الأبعاد (3D)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, status, __) => Text(
                    status,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (_, progress, __) => Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white12,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
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
    );

    try {
      final result = await ThreeDReconstructionService.reconstructFromImageFiles(
        filePaths: paths,
        title: title,
        voxelSizeMm: voxelSizeMm,
        objectType: objectType,
        onProgress: (status, progress) {
          statusNotifier.value = status;
          progressNotifier.value = progress;
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _loadSavedScans();

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreeDMeshViewerScreen(result: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل بناء المجسم ثلاثي الأبعاد: $e')),
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
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Center(
              child: InkWell(
                onTap: () => _showBetaNoticeBottomSheet(isManualTrigger: true),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.science_rounded, size: 14, color: Color(0xFFF59E0B)),
                      SizedBox(width: 4),
                      Text(
                        'BETA',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
                        'بدء مسح قطعة جديدة (الكاميرا الحية)',
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
                  const SizedBox(height: 10),
                  // Secondary CTA: Convert Product Images (PNG / JPG) to 3D
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickProductImagesAndReconstruct,
                      icon: const Icon(Icons.add_photo_alternate_rounded, size: 20, color: Color(0xFF00E676)),
                      label: const Text(
                        'تحويل صور المنتج (PNG / JPG) إلى مجسم 3D',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
                        backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
