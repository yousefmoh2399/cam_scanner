import 'package:flutter/material.dart';

class ChatCustomTheme {
  const ChatCustomTheme({this.accentColorHex = '#007AFF'});
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
    return const Color(0xFF007AFF);
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
          ? [const Color(0xFF000000), const Color(0xFF1C1C1E)]
          : [const Color(0xFFF2F2F7), const Color(0xFFFFFFFF)],
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
    final theme = Theme.of(context);
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: body,
    );
  }
}

class AppTheme {
  // Apple iOS System Palette
  static const _seed = Color(0xFF007AFF);
  static const _success = Color(0xFF34C759);

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

    // Apple iOS 17/18 System Colors
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    final scaffoldBackground = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceContainer = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFFFFFFF);
    final surfaceContainerHigh = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFE5E5EA);
    final surfaceContainerHighest = isDark
        ? const Color(0xFF48484A)
        : const Color(0xFFD1D1D6);

    // Apple 0.5px hairline divider/border
    final outline = isDark
        ? const Color(0x38FFFFFF)
        : const Color(0x1F000000);

    final seedScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: _seedColorFor(preferences),
      primary: accent,
      secondary: accent,
      tertiary: isDark ? const Color(0xFF30D158) : _success,
      surface: surface,
    );

    final colorScheme = seedScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      tertiary: isDark ? const Color(0xFF30D158) : _success,
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      surfaceContainerLowest: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      primaryContainer: accent.withValues(alpha: isDark ? 0.25 : 0.12),
      onPrimaryContainer: isDark ? const Color(0xFF70B4FF) : const Color(0xFF0056B3),
      secondaryContainer: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      onSecondaryContainer: isDark ? Colors.white : const Color(0xFF1C1C1E),
      outline: outline,
      outlineVariant: outline,
      error: isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
      errorContainer: isDark
          ? const Color(0xFF4C1211)
          : const Color(0xFFFEE4E2),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
    );

    // Cairo font with Apple typography weight and hierarchy
    final baseTextTheme = Typography.material2021().black.apply(
      fontFamily: 'Cairo',
      bodyColor: isDark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
      displayColor: isDark ? Colors.white : const Color(0xFF000000),
    );

    final palette = AppThemePalette(
      accent: accent,
      accentSoft: accent.withValues(alpha: isDark ? 0.20 : 0.12),
      accentStrong: accent,
      success: isDark ? const Color(0xFF30D158) : const Color(0xFF34C759),
      warning: isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500),
      danger: isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
      backdropColors: isDark
          ? [const Color(0xFF000000), const Color(0xFF1C1C1E)]
          : [const Color(0xFFF2F2F7), const Color(0xFFF2F2F7)],
      backdropPatternColor: Colors.transparent,
      heroGradientColors: [
        accent,
        accent.withValues(alpha: 0.85),
        accent.withValues(alpha: 0.70),
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
      splashFactory: NoSplash.splashFactory,
      highlightColor: isDark ? Colors.white10 : Colors.black12,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        showDragHandle: true,
        dragHandleColor: isDark ? const Color(0xFF545458) : const Color(0xFFC7C7CC),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : const Color(0xFF000000),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF000000),
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline, width: 0.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 10,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline, width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          side: BorderSide(color: outline, width: 1),
          foregroundColor: accent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
          fontFamily: 'Cairo',
          fontSize: 15,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 0.5,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        selectedColor: accent,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          fontFamily: 'Cairo',
          color: isDark ? Colors.white : const Color(0xFF000000),
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: isDark ? Colors.white : Colors.black,
        unselectedLabelColor: const Color(0xFF8E8E93),
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      extensions: [palette],
    );
  }

  static Color _seedColorFor(ChatPreferences preferences) {
    return switch (preferences.themeId) {
      'mint' => const Color(0xFF34C759),
      'violet' => const Color(0xFFAF52DE),
      'sunset' => const Color(0xFFFF9500),
      'mono' => const Color(0xFF8E8E93),
      'custom' => ChatAppearanceCatalog.colorFromHex(
        preferences.customTheme.accentColorHex,
      ),
      _ => _seed,
    };
  }
}


