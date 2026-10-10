import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_screen.dart';

/// شاشة البداية (Splash Screen) بهوية آبل فائقة البساطة والأناقة (Minimalist Apple Luxury)
/// - تصميم هادئ وعصري يبتعد عن التكلف والازدحام البصري
/// - شعار أنيق بتأثير Squircle مع إضاءة ناعمة وانبثاق انسيابي
/// - كتابة اسم التطبيق "لَـقْـطَـة" بخط عربي رصين وهوية موحدة
/// - مؤشر تقدم سلس وانتقال فوري بلمسة واحدة
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _titleFadeAnimation;
  late final Animation<double> _subtitleFadeAnimation;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF090D16),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Duration 1400ms for a swift, responsive, and luxury launch
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );

    _subtitleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
      ),
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
          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          _navigateToHome();
        },
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Soft Subtle Ambient Glow in the Center
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF10B981).withValues(alpha: 0.12 * _fadeAnimation.value),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2. Centered Logo and Typography
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Iconic Squircle Logo Container
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF131D2D),
                                    Color(0xFF0D1522),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.20),
                                    blurRadius: 28,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/images/app_icon.png',
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.document_scanner_rounded,
                                      size: 52,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Brand Title: "لَـقْـطَـة"
                        FadeTransition(
                          opacity: _titleFadeAnimation,
                          child: const Text(
                            'لَـقْـطَـة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              height: 1.2,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Subtitle: "LAQTA SCANNER"
                        FadeTransition(
                          opacity: _subtitleFadeAnimation,
                          child: Text(
                            'LAQTA SCANNER',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Minimalist Luxury Footer
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28,
                    child: FadeTransition(
                      opacity: _subtitleFadeAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Sleek offline badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
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
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'الماسح الضوئي الذكي الاحترافي • خصوصية وأمان',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            'الإصدار 1.0.0 • تشفير وخصوصية فائقة',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.28),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
