import 'package:flutter/material.dart';

class ChatCustomTheme {
  const ChatCustomTheme({this.accentColorHex = '#3390EC'});
  final String accentColorHex;
}

class ChatPreferences {
  const ChatPreferences({
    this.themeId = 'default',
    this.customTheme = const ChatCustomTheme(),
  });

  static const defaults = ChatPreferences();
  final String themeId;
  final ChatCustomTheme customTheme;
}

class _ResolvedAppearance {
  const _ResolvedAppearance({
    required this.accent,
    required this.wallpaperColors,
    required this.patternColor,
  });

  final Color accent;
  final List<Color> wallpaperColors;
  final Color patternColor;
}

class ChatAppearanceCatalog {
  static Color colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final val = int.tryParse('FF$cleaned', radix: 16);
      if (val != null) return Color(val);
    }
    return const Color(0xFF3390EC);
  }

  // ignore: library_private_types_in_public_api
  static _ResolvedAppearance resolveAppearance({
    required ChatPreferences preferences,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    final accent = colorScheme.primary;
    return _ResolvedAppearance(
      accent: accent,
      wallpaperColors: isDark
          ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
          : [const Color(0xFFF8FAFC), const Color(0xFFEFF6FF)],
      patternColor: accent,
    );
  }
}

class AppThemePalette extends ThemeExtension<AppThemePalette> {
  const AppThemePalette({
    required this.accent,
    required this.accentSoft,
    required this.accentStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.backdropColors,
    required this.backdropPatternColor,
    required this.heroGradientColors,
    required this.isDark,
  });

  final Color accent;
  final Color accentSoft;
  final Color accentStrong;
  final Color success;
  final Color warning;
  final Color danger;
  final List<Color> backdropColors;
  final Color backdropPatternColor;
  final List<Color> heroGradientColors;
  final bool isDark;

  @override
  AppThemePalette copyWith({
    Color? accent,
    Color? accentSoft,
    Color? accentStrong,
    Color? success,
    Color? warning,
    Color? danger,
    List<Color>? backdropColors,
    Color? backdropPatternColor,
    List<Color>? heroGradientColors,
    bool? isDark,
  }) {
    return AppThemePalette(
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentStrong: accentStrong ?? this.accentStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      backdropColors: backdropColors ?? this.backdropColors,
      backdropPatternColor: backdropPatternColor ?? this.backdropPatternColor,
      heroGradientColors: heroGradientColors ?? this.heroGradientColors,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppThemePalette lerp(ThemeExtension<AppThemePalette>? other, double t) {
    if (other is! AppThemePalette) {
      return this;
    }
    return AppThemePalette(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      accentStrong:
          Color.lerp(accentStrong, other.accentStrong, t) ?? accentStrong,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      backdropColors: _lerpColorList(backdropColors, other.backdropColors, t),
      backdropPatternColor:
          Color.lerp(backdropPatternColor, other.backdropPatternColor, t) ??
          backdropPatternColor,
      heroGradientColors: _lerpColorList(
        heroGradientColors,
        other.heroGradientColors,
        t,
      ),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    final count = a.length > b.length ? a.length : b.length;
    return List<Color>.generate(count, (index) {
      final aColor = a[index.clamp(0, a.length - 1)];
      final bColor = b[index.clamp(0, b.length - 1)];
      return Color.lerp(aColor, bColor, t) ?? aColor;
    });
  }
}

extension AppThemePaletteContext on BuildContext {
  AppThemePalette get appThemePalette =>
      Theme.of(this).extension<AppThemePalette>()!;
}

class AppThemedPage extends StatelessWidget {
  const AppThemedPage({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    final isLight = theme.brightness == Brightness.light;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isLight ? theme.scaffoldBackgroundColor : null,
              gradient: isLight
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette.backdropColors,
                      stops: _buildGradientStops(palette.backdropColors.length),
                    ),
            ),
            child: isLight
                ? const SizedBox.expand()
                : CustomPaint(
                    painter: _AppBackdropPainter(
                      color: palette.backdropPatternColor,
                      isDark: palette.isDark,
                    ),
                  ),
          ),
        ),
        body,
      ],
    );
  }

  List<double> _buildGradientStops(int length) {
    if (length <= 1) {
      return const [0];
    }
    return List<double>.generate(length, (index) => index / (length - 1));
  }
}

class AppTheme {
  static const _seed = Color(0xFF3390EC);
  static const _accent = Color(0xFF64B5F6);
  static const _success = Color(0xFF38B873);

  static ThemeData lightTheme([
    ChatPreferences preferences = ChatPreferences.defaults,
  ]) => _buildTheme(Brightness.light, preferences);

  static ThemeData darkTheme([
    ChatPreferences preferences = ChatPreferences.defaults,
  ]) => _buildTheme(Brightness.dark, preferences);

  static ThemeData _buildTheme(
    Brightness brightness,
    ChatPreferences preferences,
  ) {
    final isDark = brightness == Brightness.dark;
    final seedScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: _seedColorFor(preferences),
      primary: isDark ? const Color(0xFF74B6F4) : _seed,
      secondary: _accent,
      tertiary: _success,
      surface: isDark ? const Color(0xFF1F2C38) : const Color(0xFFF8FAFC),
    );

    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: preferences,
      isDark: isDark,
      colorScheme: seedScheme,
    );
    final accent = resolved.accent;
    final backdropBase = isDark
        ? _averageColor(resolved.wallpaperColors)
        : const Color(0xFFF8FAFC);

    final scaffoldBackground = isDark
        ? _blend(const Color(0xFF0B0F19), backdropBase, 0.04)
        : const Color(0xFFF8FAFC);
    final surface = isDark
        ? _blend(const Color(0xFF161E2E), backdropBase, 0.03)
        : Colors.white;
    final surfaceContainer = _blend(surface, accent, isDark ? 0.04 : 0.02);
    final surfaceContainerHigh = _blend(surface, accent, isDark ? 0.06 : 0.03);
    final surfaceContainerHighest = _blend(
      surface,
      accent,
      isDark ? 0.09 : 0.05,
    );
    final outline = _blend(
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      accent,
      isDark ? 0.06 : 0.03,
    );

    final colorScheme = seedScheme.copyWith(
      primary: accent,
      secondary: _blend(
        accent,
        isDark ? Colors.white : const Color(0xFF102033),
        isDark ? 0.18 : 0.10,
      ),
      tertiary: _success,
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      surfaceContainerLowest: isDark
          ? _blend(surface, Colors.black, 0.12)
          : const Color(0xFFF8FAFC),
      primaryContainer: _blend(accent, backdropBase, isDark ? 0.38 : 0.22),
      onPrimaryContainer: isDark ? Colors.white : const Color(0xFF0E2234),
      secondaryContainer: _blend(accent, surface, isDark ? 0.28 : 0.18),
      onSecondaryContainer: isDark ? Colors.white : const Color(0xFF102033),
      outline: outline,
      outlineVariant: outline.withValues(alpha: isDark ? 0.74 : 0.58),
      error: const Color(0xFFD92D20),
      errorContainer: isDark
          ? const Color(0xFF4C1211)
          : const Color(0xFFFEE4E2),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
    );

    // 100% Offline bundled Cairo font
    final baseTextTheme = Typography.material2021().black.apply(
      fontFamily: 'Cairo',
      bodyColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      displayColor: isDark ? Colors.white : const Color(0xFF0F172A),
    );

    final palette = AppThemePalette(
      accent: accent,
      accentSoft: accent.withValues(alpha: isDark ? 0.18 : 0.12),
      accentStrong: _blend(accent, isDark ? Colors.white : Colors.black, 0.16),
      success: _blend(_success, accent, isDark ? 0.14 : 0.08),
      warning: _blend(const Color(0xFFF59E0B), accent, 0.08),
      danger: const Color(0xFFD92D20),
      backdropColors: isDark
          ? [
              _blend(resolved.wallpaperColors.first, scaffoldBackground, 0.12),
              scaffoldBackground,
              _blend(resolved.wallpaperColors.last, scaffoldBackground, 0.18),
            ]
          : [scaffoldBackground, scaffoldBackground, scaffoldBackground],
      backdropPatternColor: resolved.patternColor,
      heroGradientColors: [
        _blend(accent, resolved.wallpaperColors.first, isDark ? 0.26 : 0.18),
        _blend(accent, resolved.wallpaperColors.last, isDark ? 0.34 : 0.26),
        _blend(
          accent,
          isDark ? const Color(0xFF08111A) : Colors.white,
          isDark ? 0.20 : 0.10,
        ),
      ],
      isDark: isDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Cairo',
      colorScheme: colorScheme,
      textTheme: baseTextTheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: surface,
      splashFactory: InkSparkle.splashFactory,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceContainer,
        elevation: 6,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          side: BorderSide(color: colorScheme.outlineVariant),
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.error, width: 1.4),
        ),
        filled: true,
        fillColor: surfaceContainerHigh.withValues(alpha: isDark ? 0.92 : 0.85),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF1C2B38)
            : const Color(0xFF17304A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainerHigh,
        selectedColor: accent.withValues(alpha: 0.14),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        labelStyle: TextStyle(
          fontFamily: 'Cairo',
          color: isDark ? Colors.white : const Color(0xFF16335C),
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: isDark ? Colors.white : const Color(0xFF12325C),
        unselectedLabelColor: isDark
            ? const Color(0xFF93A7BC)
            : const Color(0xFF708499),
        indicator: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w600,
        ),
      ),
      extensions: [palette],
    );
  }

  static Color _seedColorFor(ChatPreferences preferences) {
    return switch (preferences.themeId) {
      'mint' => const Color(0xFF10B981),
      'violet' => const Color(0xFF7C3AED),
      'sunset' => const Color(0xFFF59E0B),
      'mono' => const Color(0xFF64748B),
      'custom' => ChatAppearanceCatalog.colorFromHex(
        preferences.customTheme.accentColorHex,
      ),
      _ => _seed,
    };
  }

  static Color _averageColor(List<Color> colors) {
    if (colors.isEmpty) {
      return const Color(0xFFEAF0F6);
    }
    var alpha = 0.0;
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    for (final color in colors) {
      alpha += color.a;
      red += color.r;
      green += color.g;
      blue += color.b;
    }
    final length = colors.length.toDouble();
    return Color.fromARGB(
      (alpha / length).round(),
      (red / length).round(),
      (green / length).round(),
      (blue / length).round(),
    );
  }

  static Color _blend(Color base, Color overlay, double amount) {
    return Color.lerp(base, overlay, amount.clamp(0, 1)) ?? base;
  }
}

class _AppBackdropPainter extends CustomPainter {
  const _AppBackdropPainter({required this.color, required this.isDark});

  final Color color;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.18 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.08 : 0.05)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.18),
      42,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.14),
      56,
      strokePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.72),
      72,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.86),
      34,
      strokePaint,
    );

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.36)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.24,
        size.width * 0.42,
        size.height * 0.38,
      )
      ..quadraticBezierTo(
        size.width * 0.60,
        size.height * 0.54,
        size.width * 0.86,
        size.height * 0.42,
      );
    canvas.drawPath(path, strokePaint);

    final roundedRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.64, size.height * 0.28),
        width: 22,
        height: 22,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(roundedRect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _AppBackdropPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isDark != isDark;
  }
}
