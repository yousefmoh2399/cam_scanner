import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/core/theme/app_theme.dart';
import 'package:cam_scanner/features/scanner/presentation/government_documents_screen.dart';

Widget _buildTestApp(Widget child, {bool isDark = false}) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scannerChannel = MethodChannel('com.laqta.scanner/scanner');
  const legacyScannerChannel = MethodChannel('com.yourname.docscanner/scanner');
  const bridgeChannel = MethodChannel('ismart/doc_scanner');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (MethodCall methodCall) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(legacyScannerChannel, (MethodCall methodCall) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, (MethodCall methodCall) async => null);
  });

  group('Document Compression Studio - Apple Bento Paper & Zero Overflow Tests', () {
    const devices = [
      ('Small Phone (320x568)', Size(320, 568)),
      ('Standard Phone (390x844)', Size(390, 844)),
      ('Flagship Phone (412x915)', Size(412, 915)),
      ('Tablet (800x1280)', Size(800, 1280)),
    ];

    for (final (name, size) in devices) {
      testWidgets('Renders with ZERO overflow on $name in light & dark mode',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Test Light Mode
        await tester.pumpWidget(
          _buildTestApp(
            const GovernmentDocumentsScreen(initialMode: OfficialDocMode.compress),
            isDark: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('compression_studio')), findsOneWidget);

        // Verify Apple Bento elements
        expect(find.text('ضغط وتقليص حجم المستندات', skipOffstage: false), findsOneWidget);
        expect(find.text('الكاميرا', skipOffstage: false), findsOneWidget);
        expect(find.text('المعرض', skipOffstage: false), findsOneWidget);
        expect(find.text('المكتبة', skipOffstage: false), findsOneWidget);

        // Scroll the vertical studio ListView
        final verticalScrollable = find.descendant(
          of: find.byKey(const ValueKey('compression_studio')),
          matching: find.byType(Scrollable),
        );
        if (verticalScrollable.evaluate().isNotEmpty) {
          await tester.fling(verticalScrollable.first, const Offset(0, -400), 1000);
          await tester.pumpAndSettle();
        }

        expect(find.text('بوابات التوظيف والجهات الرسمية', skipOffstage: false), findsOneWidget);
        expect(find.text('السفارات والتأشيرات الدولية', skipOffstage: false), findsOneWidget);

        // Test Dark Mode
        await tester.pumpWidget(
          _buildTestApp(
            const GovernmentDocumentsScreen(initialMode: OfficialDocMode.compress),
            isDark: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('compression_studio')), findsOneWidget);
      });
    }

    testWidgets('Tapping on a preset switches the target KB cleanly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          const GovernmentDocumentsScreen(initialMode: OfficialDocMode.compress),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state is 200 KB
      expect(find.text('أقل من 200 ك.ب', skipOffstage: false), findsOneWidget);

      final presetFinder = find.text('بوابات التوظيف والجهات الرسمية', skipOffstage: false);
      expect(presetFinder, findsOneWidget);

      final verticalScrollable = find.descendant(
        of: find.byKey(const ValueKey('compression_studio')),
        matching: find.byType(Scrollable),
      );
      if (verticalScrollable.evaluate().isNotEmpty) {
        await tester.fling(verticalScrollable.first, const Offset(0, -150), 1000);
        await tester.pumpAndSettle();
      }

      await tester.tap(presetFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify the target badge updated to 500 ك.ب
      expect(find.text('أقل من 500 ك.ب', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
