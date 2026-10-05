import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/core/theme/app_theme.dart';
import 'package:cam_scanner/features/scanner/data/native_scanner_bridge.dart';
import 'package:cam_scanner/features/scanner/presentation/government_documents_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/library_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/tools_hub_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/trash_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/watermark_studio_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/auto_redaction_screen.dart';
import 'package:cam_scanner/features/scanner/presentation/widgets/smart_data_extraction_sheet.dart';

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

  // Mock native channels
  const scannerChannel = MethodChannel('com.yourname.docscanner/scanner');
  const bridgeChannel = MethodChannel('ismart/doc_scanner');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (MethodCall methodCall) async {
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'checkBlur':
          final path = methodCall.arguments['path'] as String;
          if (path.contains('blurry')) {
            return {'isBlurry': true, 'variance': 34.5};
          }
          return {'isBlurry': false, 'variance': 142.8};
        case 'splitBookPage':
          final outRight = methodCall.arguments['outRightPath'] as String;
          final outLeft = methodCall.arguments['outLeftPath'] as String;
          return {'pageRight': outRight, 'pageLeft': outLeft};
        case 'speakText':
          return true;
        case 'stopSpeaking':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, null);
  });

  const deviceSizes = [
    (name: 'Small Phone (iPhone SE / Budget Android)', size: Size(320, 568)),
    (name: 'Standard Modern Phone', size: Size(390, 844)),
    (name: 'Large Flagship Phone (Pixel 9 Pro)', size: Size(412, 915)),
    (name: 'Tablet Portrait (Pixel Tablet)', size: Size(800, 1280)),
    (name: 'Tablet Landscape', size: Size(1280, 800)),
  ];

  group('Responsive UI & Zero Overflow Tests across Device Dimensions', () {
    for (final device in deviceSizes) {
      testWidgets('LibraryScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const LibraryScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(LibraryScreen), findsOneWidget);

        // Test smooth scrolling down and up
        final scrollable = find.byType(CustomScrollView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable, const Offset(0, -300), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          await tester.fling(scrollable, const Offset(0, 300), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets(
          'GovernmentDocumentsScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester
            .pumpWidget(_buildTestApp(const GovernmentDocumentsScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(GovernmentDocumentsScreen), findsOneWidget);

        // Test smooth scrolling through cards
        final scrollable = find.byType(SingleChildScrollView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable, const Offset(0, -400), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          await tester.fling(scrollable, const Offset(0, 400), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('TrashScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const TrashScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(TrashScreen), findsOneWidget);
      });

      testWidgets(
          'SmartDataExtractionSheet renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          _buildTestApp(
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      SmartDataExtractionSheet.show(
                        context: context,
                        text:
                            'بطاقة رقم قومي: 29508150112355\nرقم الهاتف: 01012345678\nالمبلغ: 1500 جنيه',
                      );
                    },
                    child: const Text('افتح'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Tap open button to show modal sheet
        await tester.tap(find.text('افتح'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(find.byType(SmartDataExtractionSheet), findsOneWidget);
        expect(find.text('29508150112355'), findsOneWidget);

        // Smoothly scroll down the sheet to inspect the rest of extracted items
        final sheetScrollable = find.descendant(
          of: find.byType(SmartDataExtractionSheet),
          matching: find.byType(Scrollable),
        );
        if (sheetScrollable.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            find.text('01012345678'),
            150,
            scrollable: sheetScrollable.first,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(tester.takeException(), isNull);
        expect(find.text('01012345678'), findsOneWidget);
      });

      testWidgets('ToolsHubScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const ToolsHubScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(ToolsHubScreen), findsOneWidget);
        expect(find.text('مركز الأدوات'), findsOneWidget);

        // Test smooth scrolling down and up through tools
        final scrollable = find.byType(CustomScrollView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable, const Offset(0, -400), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          await tester.fling(scrollable, const Offset(0, 400), 1000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }

        // Tap on a category filter chip
        final govChip = find.text('أوراق حكومية');
        if (govChip.evaluate().isNotEmpty) {
          await tester.tap(govChip, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets(
          'WatermarkStudioScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const WatermarkStudioScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.text('العلامة المائية والأختام الأمنية'), findsOneWidget);
      });

      testWidgets(
          'AutoRedactionScreen renders with ZERO overflow on ${device.name}',
          (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildTestApp(const AutoRedactionScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.text('الحجب الأمني وتسويد البيانات'), findsOneWidget);
      });
    }
  });

  group('NativeScannerBridge Platform Channel Unit Tests', () {
    test('checkBlur correctly queries native blur detection', () async {
      final sharpResult = await NativeScannerBridge.checkBlur('test/sharp.jpg');
      expect(sharpResult.isBlurry, isFalse);
      expect(sharpResult.variance, equals(142.8));

      final blurryResult =
          await NativeScannerBridge.checkBlur('test/blurry.jpg');
      expect(blurryResult.isBlurry, isTrue);
      expect(blurryResult.variance, equals(34.5));
    });

    test('splitBookPage routes parameters and returns RTL page pair', () async {
      final result = await NativeScannerBridge.splitBookPage(
        path: '/tmp/book.jpg',
        outRightPath: '/tmp/book_right.jpg',
        outLeftPath: '/tmp/book_left.jpg',
      );

      expect(result, isNotNull);
      expect(result!.pageRight, equals('/tmp/book_right.jpg'));
      expect(result.pageLeft, equals('/tmp/book_left.jpg'));
    });

    test('speakText and stopSpeaking execute cleanly', () async {
      final spoken = await NativeScannerBridge.speakText('بسم الله الرحمن الرحيم');
      expect(spoken, isTrue);

      await expectLater(NativeScannerBridge.stopSpeaking(), completes);
    });
  });
}
