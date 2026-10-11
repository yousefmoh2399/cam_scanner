import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/models/three_d_scan_models.dart';
import '../data/native_scanner_bridge.dart';
import '../data/three_d_reconstruction_service.dart';
import 'three_d_mesh_viewer_screen.dart';

/// Guided Multi-View 3D Capture Screen with Live Gyroscope Pitch Guide, Orbit Radar, and Auto-Capture.
class ThreeDGuidedCaptureScreen extends StatefulWidget {
  const ThreeDGuidedCaptureScreen({super.key});

  @override
  State<ThreeDGuidedCaptureScreen> createState() => _ThreeDGuidedCaptureScreenState();
}

class _ThreeDGuidedCaptureScreenState extends State<ThreeDGuidedCaptureScreen> {
  final List<ThreeDScanPhoto> _capturedPhotos = [];
  double _currentElevation = 35.0; // default ring
  bool _isFlippedSession = false;
  bool _isProcessing = false;
  String _progressMessage = '';
  double _progressValue = 0.0;

  // Live Sensor & Auto-Capture states
  StreamSubscription<Map<String, double>>? _orientationSub;
  double _livePitch = 35.0;
  double _liveAzimuth = 0.0;
  bool _isAutoCapturing = false;
  Timer? _autoCaptureTimer;
  Map<String, dynamic>? _lastSilhouetteQuality;

  final TextEditingController _modelNameController =
      TextEditingController(text: 'قطعة_طباعة_3D');

  final List<double> _elevationRings = [15.0, 35.0, 60.0, 85.0];

  @override
  void initState() {
    super.initState();
    _startOrientationListener();
  }

  void _startOrientationListener() {
    _orientationSub = ThreeDReconstructionService.deviceOrientationStream.listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _livePitch = data['pitch'] ?? 35.0;
          _liveAzimuth = data['azimuth'] ?? 0.0;
        });
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _orientationSub?.cancel();
    _modelNameController.dispose();
    super.dispose();
  }

  int get _uprightCount => _capturedPhotos.where((p) => !p.isFlipped).length;
  int get _flippedCount => _capturedPhotos.where((p) => p.isFlipped).length;

  List<double> get _coveredAzimuthsOnCurrentRing {
    return _capturedPhotos
        .where((p) => p.elevationDeg == _currentElevation && p.isFlipped == _isFlippedSession)
        .map((p) => p.azimuthDeg)
        .toList();
  }

  int get _coveredSectorsCount {
    final covered = _coveredAzimuthsOnCurrentRing;
    int count = 0;
    for (int i = 0; i < 12; i++) {
      final sectorAngle = i * 30.0;
      final isFound = covered.any((a) {
        final diff = (a - sectorAngle).abs();
        return diff <= 15.0 || diff >= 345.0;
      });
      if (isFound) count++;
    }
    return count;
  }

  void _addPhoto(String filePath) {
    HapticFeedback.lightImpact();
    final countOnRing = _capturedPhotos
        .where((p) => p.elevationDeg == _currentElevation && p.isFlipped == _isFlippedSession)
        .length;
    final azimuth = _liveAzimuth > 0.0 ? _liveAzimuth : ((countOnRing * 30.0) % 360.0);

    setState(() {
      _capturedPhotos.add(
        ThreeDScanPhoto(
          path: filePath,
          elevationDeg: _currentElevation,
          azimuthDeg: azimuth,
          isFlipped: _isFlippedSession,
          timestamp: DateTime.now(),
        ),
      );
    });

    if (_capturedPhotos.length == 1) {
      _checkQualityForPhoto(filePath);
    }
  }

  Future<void> _checkQualityForPhoto(String filePath) async {
    final quality = await ThreeDReconstructionService.checkSilhouetteQuality(filePath);
    if (!mounted) return;
    setState(() {
      _lastSilhouetteQuality = quality;
    });
  }

  void _toggleAutoCapture() {
    if (_isAutoCapturing) {
      _autoCaptureTimer?.cancel();
      setState(() => _isAutoCapturing = false);
    } else {
      setState(() => _isAutoCapturing = true);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل الدوران التلقائي: تحرك ببطء حول المجسم وسيلتقط التطبيق الصور تلقائياً.'),
          duration: Duration(seconds: 3),
        ),
      );
      _autoCaptureTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) async {
        if (!mounted || !_isAutoCapturing) return;
        final count = _capturedPhotos
            .where((p) => p.elevationDeg == _currentElevation && p.isFlipped == _isFlippedSession)
            .length;
        if (count >= 12) {
          _toggleAutoCapture();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('اكتملت حلقة ${_currentElevation.toInt()}° بنجاح (12 زاوية)!')),
          );
          return;
        }
        await _captureWithCamera();
      });
    }
  }

  void _showSilhouetteInspectorDialog(BuildContext context) {
    if (_lastSilhouetteQuality == null) return;
    final previewPath = _lastSilhouetteQuality!['previewPath'] as String? ?? '';
    final isClean = _lastSilhouetteQuality!['isClean'] as bool? ?? false;
    final coverage = (_lastSilhouetteQuality!['coveragePercent'] as num?)?.toDouble() ?? 0.0;
    final message = _lastSilhouetteQuality!['message'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isClean ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: isClean ? const Color(0xFF00E676) : const Color(0xFFFF9100),
              size: 22,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'فاحص عزل الخلفية (Silhouette)',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (File(previewPath).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(previewPath),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isClean
                    ? const Color(0xFF00E676).withValues(alpha: 0.12)
                    : const Color(0xFFFF9100).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: isClean ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اللون الأخضر يمثل المجسم الذي سيعالجه المحرك. النسبة: ${coverage.toStringAsFixed(1)}% من مساحة الكادر.',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق', style: TextStyle(color: Color(0xFF00E676))),
          ),
        ],
      ),
    );
  }

  Future<void> _captureWithCamera() async {
    HapticFeedback.mediumImpact();
    try {
      final results = await NativeScannerBridge.startScan(batch: true);
      if (results.isNotEmpty) {
        for (final item in results) {
          if (item.path.isNotEmpty && File(item.path).existsSync()) {
            _addPhoto(item.path);
          }
        }
      }
    } on ScannerPermissionDeniedException catch (e) {
      if (!mounted) return;
      showScannerPermissionDialog(context, e);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
      );
    }
  }

  Future<void> _pickImagesFromGallery() async {
    HapticFeedback.selectionClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        if (file.path != null) {
          _addPhoto(file.path!);
        }
      }
    }
  }

  void _promptFlipScan() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.flip_camera_android_rounded, color: Color(0xFF00E676), size: 36),
        ),
        title: const Text(
          'خطوة قلب القطعة (Flip Scan)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'للحصول على مجسم صلب مغلق 100% وإزالة حجب القاعدة:\n\n'
          '1. اقلب القطعة بمقدار 90° على أحد جوانبها فوق لوحة ChArUco.\n'
          '2. التقط 12 إلى 24 صورة إضافية من زوايا مختلفة.\n'
          '3. سيقوم المحرك بدمج الجلستين تلقائياً للحصول على أعلى دقة ميكانيكية.',
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تخطي (جلسة واحدة فقط)', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _isFlippedSession = true;
              });
            },
            child: const Text('بدء الجلسة المقلوبة', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _startReconstruction() async {
    if (_capturedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى التقاط أو استيراد صور للمجسم أولاً')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressMessage = 'جارٍ تحضير الصور والمعايرة...';
      _progressValue = 0.05;
    });

    try {
      final title = _modelNameController.text.trim().isNotEmpty
          ? _modelNameController.text.trim()
          : '3D_Model';

      final result = await ThreeDReconstructionService.reconstructFromPhotos(
        photos: _capturedPhotos,
        title: title,
        config: ThreeDReconstructionConfig(
          voxelSizeMm: 1.4,
          consensusRatio: 0.40,
          isFlipScanEnabled: _flippedCount > 0,
        ),
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _progressMessage = status;
              _progressValue = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Navigate to the 3D Viewer
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ThreeDMeshViewerScreen(result: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت المعالجة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D24),
        elevation: 0,
        title: const Text(
          'جلسة المسح ثلاثي الأبعاد',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white70),
            tooltip: 'إرشادات التصوير',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E222B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('نصائح المسح الناجح', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    '• للأجهزة والقطع (الموبايل، البطاقات، القطع الميكانيكية): ضع القطعة على ورقة بيضاء سادة، والتقط 1 إلى 3 صور من الأعلى والجانب. وسيقوم النظام ببنائها بدقة أبعاد مليمترية CAD مسطحة ومطابقة فوراً!\n\n'
                    '• للمجسمات الحجمية (الأكواب، العلب، التماثيل): التقط 12 إلى 24 صورة أثناء الدوران 360° حول المجسم ليقوم المحرك بنحت جميع الجوانب.\n\n'
                    '• احرص على إضاءة جيدة وتجنب الانعكاسات الشديدة على الزجاج.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('فهمت', style: TextStyle(color: Color(0xFF00E676))),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Session Status Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF1A1D24),
                child: Row(
                  children: [
                    // Model Name Input
                    Expanded(
                      child: TextField(
                        controller: _modelNameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'اسم المجسم...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF242832),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Flip badge toggle
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isFlippedSession = !_isFlippedSession;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isFlippedSession
                              ? const Color(0xFFFF9100).withValues(alpha: 0.2)
                              : const Color(0xFF00E676).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isFlippedSession
                                ? const Color(0xFFFF9100)
                                : const Color(0xFF00E676),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isFlippedSession
                                  ? Icons.rotate_90_degrees_ccw_rounded
                                  : Icons.vertical_align_top_rounded,
                              color: _isFlippedSession
                                  ? const Color(0xFFFF9100)
                                  : const Color(0xFF00E676),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isFlippedSession ? 'مقلوبة (Flip)' : 'رأسية (Upright)',
                              style: TextStyle(
                                color: _isFlippedSession
                                    ? const Color(0xFFFF9100)
                                    : const Color(0xFF00E676),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Elevation Ring Selector Tabs
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: const Color(0xFF16181F),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _elevationRings.map((deg) {
                    final isSelected = _currentElevation == deg;
                    final count = _capturedPhotos.where((p) => p.elevationDeg == deg).length;

                    return InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _currentElevation = deg);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00C853).withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF00C853) : Colors.white12,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${deg.toInt()}°',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF00E676) : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$count صور',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF00E676) : Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Middle Interactive Guidance Viewport
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_capturedPhotos.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2430),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF448AFF).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.lightbulb_rounded, color: Color(0xFF448AFF), size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'للموبايل والقطع على الورقة: التقط صورة واضحة من الأعلى وبزاوية، واضغط "بناء المجسم" فوراً!',
                                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Live Silhouette Quality Inspector Banner
                      if (_lastSilhouetteQuality != null) ...[
                        Builder(builder: (context) {
                          final isClean = _lastSilhouetteQuality!['isClean'] as bool? ?? false;
                          final msg = _lastSilhouetteQuality!['message'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                            child: InkWell(
                              onTap: () => _showSilhouetteInspectorDialog(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isClean
                                      ? const Color(0xFF00E676).withValues(alpha: 0.12)
                                      : const Color(0xFFFF9100).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isClean
                                        ? const Color(0xFF00E676).withValues(alpha: 0.4)
                                        : const Color(0xFFFF9100).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isClean ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                      color: isClean ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        msg,
                                        style: TextStyle(
                                          color: isClean ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('معاينة', style: TextStyle(color: Colors.white60, fontSize: 10)),
                                    const Icon(Icons.chevron_left_rounded, color: Colors.white38, size: 14),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                      ],

                      // Live Device Gyroscope Pitch Guide Pill
                      Builder(builder: (context) {
                        final isPitchOptimal = (_livePitch - _currentElevation).abs() <= 7.0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPitchOptimal
                                ? const Color(0xFF00E676).withValues(alpha: 0.16)
                                : const Color(0xFFFF9100).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isPitchOptimal ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPitchOptimal ? Icons.check_circle_rounded : Icons.explore_rounded,
                                size: 15,
                                color: isPitchOptimal ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'الميل: ${_livePitch.toStringAsFixed(0)}° (المطلوب: ${_currentElevation.toInt()}°) • ${isPitchOptimal ? 'زاوية مثالية ✓' : (_livePitch < _currentElevation ? 'ارفع الهاتف ⬆' : 'اخفض الهاتف ⬇')}',
                                style: TextStyle(
                                  color: isPitchOptimal ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      // 360-Degree Orbit Radar & Centered Shutter Button
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: CustomPaint(
                          painter: _OrbitRadarPainter(
                            currentAzimuth: _liveAzimuth,
                            coveredAzimuths: _coveredAzimuthsOnCurrentRing,
                          ),
                          child: Center(
                            child: InkWell(
                              onTap: _captureWithCamera,
                              borderRadius: BorderRadius.circular(70),
                              child: Container(
                                width: 135,
                                height: 135,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isAutoCapturing
                                      ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                                      : const Color(0xFF00E676).withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: _isAutoCapturing ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                                    width: 2.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isAutoCapturing
                                          ? Icons.fiber_manual_record_rounded
                                          : (_isFlippedSession ? Icons.flip_camera_android_rounded : Icons.camera_alt_rounded),
                                      size: 38,
                                      color: _isAutoCapturing ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$_coveredSectorsCount / 12 زوايا',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      _isAutoCapturing ? 'جارٍ الالتقاط...' : 'اضغط للتصوير',
                                      style: TextStyle(
                                        color: _isAutoCapturing ? const Color(0xFFFF5252) : Colors.white60,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Auto-Capture Continuous Orbit Button
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ElevatedButton.icon(
                          onPressed: _toggleAutoCapture,
                          icon: Icon(
                            _isAutoCapturing ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _isAutoCapturing ? 'إيقاف الدوران التلقائي' : 'تشغيل الدوران التلقائي (360° Auto)',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isAutoCapturing ? const Color(0xFFD32F2F) : const Color(0xFF1E2430),
                            foregroundColor: _isAutoCapturing ? Colors.white : const Color(0xFF00E676),
                            side: BorderSide(
                              color: _isAutoCapturing
                                  ? const Color(0xFFD32F2F)
                                  : const Color(0xFF00E676).withValues(alpha: 0.4),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isFlippedSession
                            ? 'الجلسة 2: القطعة مقلوبة على جانبها @ ${_currentElevation.toInt()}°'
                            : 'الجلسة 1: القطعة رأسية @ ${_currentElevation.toInt()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إجمالي الصور الملتقطة: ${_capturedPhotos.length} صورة (رأسية: $_uprightCount • مقلوبة: $_flippedCount)',
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                      const SizedBox(height: 16),
                      if (!_isFlippedSession && _uprightCount >= 12)
                        OutlinedButton.icon(
                          onPressed: _promptFlipScan,
                          icon: const Icon(Icons.flip_rounded, size: 16),
                          label: const Text('انتقل لجلسة القلب (Flip Scan) الآن'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF9100),
                            side: const BorderSide(color: Color(0xFFFF9100)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom Tray: Photos Gallery & Action Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1D24),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thumbnails list
                    if (_capturedPhotos.isNotEmpty)
                      SizedBox(
                        height: 65,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _capturedPhotos.length,
                          itemBuilder: (context, index) {
                            final photo = _capturedPhotos[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(photo.path),
                                      width: 65,
                                      height: 65,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 65,
                                        height: 65,
                                        color: Colors.white12,
                                        child: const Icon(Icons.broken_image, size: 20),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${photo.elevationDeg.toInt()}°',
                                        style: const TextStyle(color: Colors.white, fontSize: 8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Controls Row
                    Row(
                      children: [
                        // Camera capture button
                        IconButton.filled(
                          onPressed: _captureWithCamera,
                          icon: const Icon(Icons.camera_alt_rounded),
                          tooltip: 'التقاط بالكاميرا',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF00C853),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Import from gallery
                        IconButton.filledTonal(
                          onPressed: _pickImagesFromGallery,
                          icon: const Icon(Icons.photo_library_rounded),
                          tooltip: 'استيراد صور من المعرض',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF282D37),
                            foregroundColor: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Process Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _capturedPhotos.isEmpty ? null : _startReconstruction,
                            icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                            label: Text(
                              'معالجة واستخراج STL (${_capturedPhotos.length} صورة)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white12,
                              disabledForegroundColor: Colors.white38,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Processing Overlay Dialog
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF00E676),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _progressMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progressValue,
                        backgroundColor: Colors.white10,
                        color: const Color(0xFF00E676),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_progressValue * 100).toInt()}% • معالجة أوفلاين 100%',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for the 360-degree circular orbit radar around the shutter button.
class _OrbitRadarPainter extends CustomPainter {
  final double currentAzimuth;
  final List<double> coveredAzimuths;

  _OrbitRadarPainter({
    required this.currentAzimuth,
    required this.coveredAzimuths,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final basePaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawCircle(center, radius, basePaint);

    // 12 Sectors (30 degrees each)
    for (int i = 0; i < 12; i++) {
      final sectorAngle = i * 30.0;
      final rad = (sectorAngle - 90) * (math.pi / 180.0);

      final isCovered = coveredAzimuths.any((a) {
        final diff = (a - sectorAngle).abs();
        return diff <= 15.0 || diff >= 345.0;
      });

      final tickPaint = Paint()
        ..color = isCovered ? const Color(0xFF00E676) : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCovered ? 4.5 : 2.0
        ..strokeCap = StrokeCap.round;

      final startOffset = Offset(
        center.dx + (radius - (isCovered ? 12 : 7)) * math.cos(rad),
        center.dy + (radius - (isCovered ? 12 : 7)) * math.sin(rad),
      );
      final endOffset = Offset(
        center.dx + (radius + (isCovered ? 5 : 2)) * math.cos(rad),
        center.dy + (radius + (isCovered ? 5 : 2)) * math.sin(rad),
      );

      canvas.drawLine(startOffset, endOffset, tickPaint);

      if (isCovered) {
        final glowPaint = Paint()
          ..color = const Color(0xFF00E676).withValues(alpha: 0.8)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(endOffset, 3.0, glowPaint);
      }
    }

    // Pointer needle for currentAzimuth
    final needleRad = (currentAzimuth - 90) * (math.pi / 180.0);
    final needlePaint = Paint()
      ..color = const Color(0xFFFF9100)
      ..style = PaintingStyle.fill;

    final p1 = Offset(
      center.dx + (radius + 8) * math.cos(needleRad),
      center.dy + (radius + 8) * math.sin(needleRad),
    );
    final p2 = Offset(
      center.dx + (radius - 5) * math.cos(needleRad + 0.15),
      center.dy + (radius - 5) * math.sin(needleRad + 0.15),
    );
    final p3 = Offset(
      center.dx + (radius - 5) * math.cos(needleRad - 0.15),
      center.dy + (radius - 5) * math.sin(needleRad - 0.15),
    );

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, needlePaint);
  }

  @override
  bool shouldRepaint(covariant _OrbitRadarPainter oldDelegate) {
    return oldDelegate.currentAzimuth != currentAzimuth ||
        oldDelegate.coveredAzimuths.length != coveredAzimuths.length;
  }
}
