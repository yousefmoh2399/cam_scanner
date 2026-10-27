import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/core/theme/app_theme.dart';
import 'package:cam_scanner/features/scanner/presentation/government_documents_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/id_card_a4_screen.dart';

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

  const deviceSizes = [
    (name: 'Small Phone (iPhone SE / Budget Android)', size: Size(320, 568)),
    (name: 'Standard Modern Phone', size: Size(390, 844)),
    (name: 'Large Flagship Phone (Pixel 9 Pro)', size: Size(412, 915)),
    (name: 'Tablet Portrait (Pixel Tablet)', size: Size(800, 1280)),
    (name: 'Tablet Landscape', size: Size(1280, 800)),
  ];

  group('IdCardA4Screen Responsive & Zero Overflow Tests across Device Dimensions', () {
    for (final device in deviceSizes) {
      testWidgets('IdCardA4Screen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const IdCardA4Screen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(IdCardA4Screen), findsOneWidget);
        expect(find.text('بطاقة وش وضهر'), findsOneWidget);
        expect(find.text('تصوير وجهي البطاقة'), findsOneWidget);

        // Test smooth scrolling down and up through all Bento Cards
        final scrollable = find.byType(ListView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable.first, const Offset(0, -500), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          await tester.fling(scrollable.first, const Offset(0, 500), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('IdCardA4Screen layout switching works smoothly without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const IdCardA4Screen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Side-by-Side Top layout
      final sideBySideTab = find.text('متجاوران بالأعلى');
      expect(sideBySideTab, findsOneWidget);
      await tester.tap(sideBySideTab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Foldable layout
      final foldableTab = find.text('تنسيق الطي');
      expect(foldableTab, findsOneWidget);
      await tester.tap(foldableTab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch back to Vertical Center
      final verticalTab = find.text('رأسي بالمنتصف');
      expect(verticalTab, findsOneWidget);
      await tester.tap(verticalTab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('GovernmentDocumentsScreen certificate mode renders with ZERO overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const GovernmentDocumentsScreen(
        initialMode: OfficialDocMode.certificate,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('الشهادات والمستندات والعقود الرسمية'), findsOneWidget);
      expect(find.text('مسرح الشهادة والمستند'), findsOneWidget);
      expect(find.text('عرضي (أفقي)'), findsOneWidget);
      expect(find.text('طولي (رأسي)'), findsOneWidget);
      final certListView = find.byKey(const ValueKey('certificate_studio'));
      expect(certListView, findsOneWidget);

      // Scroll down through certificate studio
      await tester.fling(certListView, const Offset(0, -300), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // Tap on Portrait
      final portraitBtn = find.text('طولي (رأسي)');
      if (portraitBtn.evaluate().isNotEmpty) {
        await tester.tap(portraitBtn, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // Tap on Borderless
      final borderlessBtn = find.text('بدون إطار إضافي');
      if (borderlessBtn.evaluate().isNotEmpty) {
        await tester.tap(borderlessBtn, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
