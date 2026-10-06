import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_screen.dart';

/// شاشة البداية المتحركة فائقة الاحترافية لتطبيق "لقطة" (Laqta Scanner)
/// - تدعم الرسوم المتحركة الهندسية لتكوين الأيقونة وشعاع الليزر الماسح
/// - كتابة اسم التطبيق وهويته بتأثير التلاشي والانبثاق
/// - انتقال سلس وسريع إلى الشاشة الرئيسية
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Animation intervals
  late final Animation<double> _bgGlowAnim;
  late final Animation<double> _reticleAnim;
  late final Animation<double> _iconScaleAnim;
  late final Animation<double> _iconFadeAnim;
  late final Animation<double> _scannerBeamAnim;
  late final Animation<double> _shimmerAnim;
  late final Animation<double> _titleRevealAnim;
  late final Animation<double> _subtitleFadeAnim;
  late final Animation<double> _taglineAnim;
  late final Animation<double> _progressAnim;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // Lock status bar to dark styling during splash for seamless native blend
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF080C14),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // 1. Ambient glow emerges
    _bgGlowAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );

    // 2. Viewfinder reticles lock into place around the icon
    _reticleAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.42, curve: Curves.easeOutBack),
    );

    // 3. Icon scales with spring bounce & reveals
    _iconScaleAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.52, curve: Curves.easeOutBack),
    );
    _iconFadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.38, curve: Curves.easeIn),
    );

    // 4. Laser scanner sweep across the logo
    _scannerBeamAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.70, curve: Curves.easeInOutCubic),
    );

    // 5. Specular shimmer glint
    _shimmerAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.58, 0.82, curve: Curves.easeInOut),
    );

    // 6. Title ("لقطة") reveals with letter expansion & slide
    _titleRevealAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.46, 0.76, curve: Curves.easeOutCubic),
    );

    // 7. Subtitle ("LAQTA SCANNER") fades in
    _subtitleFadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.84, curve: Curves.easeOut),
    );

    // 8. Tagline & Offline badge appear
    _taglineAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.70, 0.92, curve: Curves.easeOut),
    );

    // 9. Smooth progress track
    _progressAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.95, curve: Curves.easeInOutCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToHome();
      }
    });

    _controller.forward();
  }

  void _navigateToHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LibraryScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          final scale = Tween<double>(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 550),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getStatusText(double progress) {
    if (progress < 0.35) {
      return 'تهيئة محرك المعالجة المحلي...';
    } else if (progress < 0.75) {
      return 'تجهيز المستندات وأدوات المسح الذكي...';
    } else {
      return 'جاهز للاستخدام • 100% بدون إنترنت';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Instant skip on tap
          HapticFeedback.lightImpact();
          _navigateToHome();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progressVal = _progressAnim.value;

            return Stack(
              children: [
                // ── 1. Futuristic Ambient Background & Glow Orbs ──
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SplashBackgroundPainter(
                      glowProgress: _bgGlowAnim.value,
                    ),
                  ),
                ),

                // ── 2. Center Content (Logo, Laser Scan & Typography) ──
                Center(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ── Logo Card with Viewfinder Reticles & Laser Beam ──
                          SizedBox(
                            width: 170,
                            height: 170,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Concentric Radar Ripple Waves
                                if (_bgGlowAnim.value > 0.1) ...[
                                  Opacity(
                                    opacity: (1.0 - _bgGlowAnim.value)
                                        .clamp(0.0, 1.0),
                                    child: Container(
                                      width: 130 + (_bgGlowAnim.value * 40),
                                      height: 130 + (_bgGlowAnim.value * 40),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.35),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                // Outer Viewfinder Brackets / Corners (Scanner Camera Reticles)
                                CustomPaint(
                                  size: const Size(160, 160),
                                  painter: _ScannerReticlePainter(
                                    progress: _reticleAnim.value,
                                    laserProgress: _scannerBeamAnim.value,
                                  ),
                                ),

                                // Main Logo Icon Container (Assembles with Spring Elastic Curve)
                                Transform.scale(
                                  scale: _iconScaleAnim.value.clamp(0.0, 1.2),
                                  child: Opacity(
                                    opacity: _iconFadeAnim.value.clamp(0.0, 1.0),
                                    child: Container(
                                      width: 116,
                                      height: 116,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(28),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981)
                                                .withValues(
                                              alpha: 0.30 * _iconScaleAnim.value,
                                            ),
                                            blurRadius: 26,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 8),
                                          ),
                                          BoxShadow(
                                            color: const Color(0xFF007AFF)
                                                .withValues(
                                              alpha: 0.22 * _iconScaleAnim.value,
                                            ),
                                            blurRadius: 38,
                                            spreadRadius: 4,
                                            offset: const Offset(0, 14),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.22),
                                          width: 1.8,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(26),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // App Icon Image
                                            Image.asset(
                                              'assets/images/app_icon.png',
                                              fit: BoxFit.cover,
                                              filterQuality: FilterQuality.high,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color: const Color(0xFF0E1E2E),
                                                child: const Icon(
                                                  Icons.document_scanner_rounded,
                                                  size: 56,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                            ),

                                            // Scanning Laser Beam Animation Over Logo
                                            if (_scannerBeamAnim.value > 0.0 &&
                                                _scannerBeamAnim.value < 1.0)
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter: _LaserBeamPainter(
                                                    position:
                                                        _scannerBeamAnim.value,
                                                  ),
                                                ),
                                              ),

                                            // Specular Glass Glint / Shimmer
                                            if (_shimmerAnim.value > 0.0 &&
                                                _shimmerAnim.value < 1.0)
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter: _ShimmerGlintPainter(
                                                    progress:
                                                        _shimmerAnim.value,
                                                  ),
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
                          ),

                          const SizedBox(height: 28),

                          // ── Typography: Brand Name "لقطة" (يتكتب الايقونه) ──
                          Transform.translate(
                            offset: Offset(
                              0,
                              (1.0 - _titleRevealAnim.value) * 16,
                            ),
                            child: Opacity(
                              opacity: _titleRevealAnim.value.clamp(0.0, 1.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Gradient Brand Text: لقطة
                                  ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Color(0xFFE2E8F0),
                                        Color(0xFF34D399),
                                      ],
                                      stops: [0.0, 0.6, 1.0],
                                      begin: Alignment.topRight,
                                      end: Alignment.bottomLeft,
                                    ).createShader(bounds),
                                    child: const Text(
                                      'لَـقْـطَـة',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 40,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  // Pro / Smart Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // ── Subtitle: "LAQTA SCANNER" ──
                          Transform.translate(
                            offset: Offset(
                              0,
                              (1.0 - _subtitleFadeAnim.value) * 12,
                            ),
                            child: Opacity(
                              opacity: _subtitleFadeAnim.value.clamp(0.0, 1.0),
                              child: const Text(
                                'LAQTA  SCANNER',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 5.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // ── Feature Pill: "الماسح الضوئي الذكي • بدون إنترنت 100%" ──
                          Transform.translate(
                            offset: Offset(
                              0,
                              (1.0 - _taglineAnim.value) * 10,
                            ),
                            child: Opacity(
                              opacity: _taglineAnim.value.clamp(0.0, 1.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.09),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF10B981),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0xFF10B981),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'الماسح الضوئي الذكي • يعمل محلياً 100% بدون إنترنت',
                                      style: TextStyle(
                                        color: Color(0xFFCBD5E1),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── 3. Bottom Progress Bar & Modern Status Indicator ──
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: size.height * 0.055,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Text
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _titleRevealAnim.value > 0.2 ? 1.0 : 0.0,
                        child: Text(
                          _getStatusText(progressVal),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Apple-style sleek progress bar
                      Container(
                        height: 3.5,
                        width: size.width * 0.65,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progressVal.clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF007AFF),
                                    Color(0xFF10B981),
                                    Color(0xFF34D399),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Version Indicator
                      Text(
                        'الإصدار 1.0.0 • آمن ومحمي بالكامل',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// يرسم الخلفية الداكنة المتطورة مع توهجات الألوان المتناسقة (Cyan / Emerald)
class _SplashBackgroundPainter extends CustomPainter {
  final double glowProgress;

  _SplashBackgroundPainter({required this.glowProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Deep slate vignette background
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.15),
        radius: 1.15,
        colors: [
          Color(0xFF0F1A2E),
          Color(0xFF0B1120),
          Color(0xFF060911),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, bgPaint);

    // Glowing Emerald Ambient Core behind logo
    if (glowProgress > 0.01) {
      final center = Offset(size.width / 2, size.height * 0.43);
      final radius = (size.width * 0.55) * glowProgress;

      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.22 * glowProgress),
            const Color(0xFF007AFF).withValues(alpha: 0.12 * glowProgress),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashBackgroundPainter oldDelegate) {
    return oldDelegate.glowProgress != glowProgress;
  }
}

/// يرسم زوايا التركيز والكاميرا المحيطة بالأيقونة (Scanner Viewfinder Reticles)
class _ScannerReticlePainter extends CustomPainter {
  final double progress;
  final double laserProgress;

  _ScannerReticlePainter({
    required this.progress,
    required this.laserProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;

    final paint = Paint()
      ..color = Color.lerp(
        const Color(0xFF10B981).withValues(alpha: 0.4),
        const Color(0xFF34D399),
        laserProgress,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final double pad = 12 * (1.0 - progress);
    final double arm = 18;

    final left = pad;
    final top = pad;
    final right = size.width - pad;
    final bottom = size.height - pad;

    // Top-Left corner
    canvas.drawLine(Offset(left, top + arm), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + arm, top), paint);

    // Top-Right corner
    canvas.drawLine(Offset(right - arm, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + arm), paint);

    // Bottom-Left corner
    canvas.drawLine(Offset(left, bottom - arm), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + arm, bottom), paint);

    // Bottom-Right corner
    canvas.drawLine(Offset(right - arm, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - arm), paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerReticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.laserProgress != laserProgress;
  }
}

/// شعاع ليزر متوهج يمسح الأيقونة عمودياً لمحاكاة الماسح الضوئي
class _LaserBeamPainter extends CustomPainter {
  final double position; // 0.0 to 1.0

  _LaserBeamPainter({required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * position;

    // Soft laser glow trailing above the beam
    final trailHeight = 28.0;
    final trailRect = Rect.fromLTRB(0, math.max(0, y - trailHeight), size.width, y);
    final trailPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF10B981).withValues(alpha: 0.28),
        ],
      ).createShader(trailRect);

    canvas.drawRect(trailRect, trailPaint);

    // Intense laser line
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xFF34D399),
          Colors.white,
          Color(0xFF34D399),
          Colors.transparent,
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2.5))
      ..strokeWidth = 2.5;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _LaserBeamPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}

/// لمعة زجاجية متحركة مائلة (Specular Glint)
class _ShimmerGlintPainter extends CustomPainter {
  final double progress;

  _ShimmerGlintPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final travel = (width + height) * 1.5;
    final current = -height + (travel * progress);

    final path = Path()
      ..moveTo(current, 0)
      ..lineTo(current + 40, 0)
      ..lineTo(current - height + 40, height)
      ..lineTo(current - height, height)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerGlintPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
