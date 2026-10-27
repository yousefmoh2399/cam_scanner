import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cam_scanner/core/theme/app_theme.dart';
import 'package:cam_scanner/features/scanner/presentation/tools_hub_screen.dart';

Widget _buildTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ToolsHubScreen Apple Bento Paper & Functionality Tests', () {
    testWidgets('renders Apple Bento Paper Categorized Sections directly without bloated banners',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const ToolsHubScreen()));
      await tester.pumpAndSettle();

      // Verify Header & Search
      expect(find.text('مركز الأدوات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify Category Section Header visible in viewport immediately
      expect(find.text('الهوية والمستندات الرسمية'), findsOneWidget);

      // Verify Clean Bento Paper Cards (without bloated banner duplicates)
      expect(find.text('تصوير البطاقة وش وضهر (A4)'), findsOneWidget);
      expect(find.text('مسح جواز السفر والشهادات'), findsOneWidget);
      expect(find.text('تجهيز صور شخصية 4×6'), findsOneWidget);

      // Scroll down to verify second category
      final scrollable = find.byType(CustomScrollView);
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('الذكاء الاصطناعي ومعالجة الورق'), findsOneWidget);
      expect(find.text('محرر ومستخرج الجداول (إكسل)'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('category filtering works smoothly', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const ToolsHubScreen()));
      await tester.pumpAndSettle();

      // Tap on Government category pill (immediately next to 'الكل')
      final govCategoryPill = find.text('هوية ومستندات');
      expect(govCategoryPill, findsOneWidget);
      await tester.tap(govCategoryPill);
      await tester.pumpAndSettle();

      // Header switches to filtered banner
      expect(find.text('الهوية والمستندات الرسمية'), findsOneWidget);
      expect(find.text('مسح جواز السفر والشهادات'), findsOneWidget);
      expect(find.text('تجهيز صور شخصية 4×6'), findsOneWidget);

      // Tap back on 'الكل'
      final allCategoryPill = find.text('الكل');
      expect(allCategoryPill, findsOneWidget);
      await tester.tap(allCategoryPill);
      await tester.pumpAndSettle();

      // Returns to all categories
      expect(find.text('الهوية والمستندات الرسمية'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('search query filters tools and handles empty state', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const ToolsHubScreen()));
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'إكسل');
      await tester.pumpAndSettle();

      // Verify filtered results
      expect(find.text('محرر ومستخرج الجداول (إكسل)'), findsOneWidget);
      expect(find.text('تحويل المستندات إلى Excel'), findsOneWidget);

      // Enter non-matching query
      await tester.enterText(searchField, 'غيرموجود99999');
      await tester.pumpAndSettle();

      expect(find.text('لا توجد أداة مطابقة لبحثك'), findsOneWidget);
      expect(find.text('عرض كافة الأدوات'), findsOneWidget);

      // Tap reset button
      await tester.tap(find.text('عرض كافة الأدوات'));
      await tester.pumpAndSettle();

      expect(find.text('تصوير البطاقة وش وضهر (A4)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggles between Grid View and Inset List View', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTestApp(const ToolsHubScreen()));
      await tester.pumpAndSettle();

      // Tap List View icon in AppBar
      final listModeButton = find.byTooltip('عرض ورقي مجمع');
      expect(listModeButton, findsOneWidget);
      await tester.tap(listModeButton);
      await tester.pumpAndSettle();

      // In list view, chevrons appear
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsWidgets);

      // Switch back to Grid View
      final gridModeButton = find.byTooltip('عرض بينتو شبكي');
      expect(gridModeButton, findsOneWidget);
      await tester.tap(gridModeButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
