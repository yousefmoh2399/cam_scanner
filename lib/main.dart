import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/scanner/presentation/library_screen.dart';
import 'shared/providers/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CamScannerApp()));
}

class CamScannerApp extends ConsumerWidget {
  const CamScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPreferencesControllerProvider).valueOrNull;
    final themeMode = prefs == null
        ? ThemeMode.system
        : (prefs.darkMode ? ThemeMode.dark : ThemeMode.light);

    final chatPrefs =
        ChatPreferences(themeId: prefs?.accentThemeId ?? 'default');

    return MaterialApp(
      title: 'لقطة - Laqta Scanner',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme(chatPrefs),
      darkTheme: AppTheme.darkTheme(chatPrefs),
      themeMode: themeMode,
      home: const LibraryScreen(),
    );
  }
}
