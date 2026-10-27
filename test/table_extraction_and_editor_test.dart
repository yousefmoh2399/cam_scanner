import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/features/scanner/data/office_exporter_service.dart';
import 'package:cam_scanner/features/scanner/data/table_extraction_service.dart';
import 'package:cam_scanner/features/scanner/presentation/interactive_table_editor_screen.dart';

void main() {
  group('TableExtractionService: Physical Paper Layout Reconstruction', () {
    const service = TableExtractionService();

    test('Reconstructs Arabic RTL table geometry from physical OCR blocks', () {
      // Physical layout of an Arabic Paper Invoice (X ranges from 0 to 1000, Y ranges from 0 to 500)
      // Header row at top=100:
      // [الإجمالي: x=100-220], [السعر: x=350-450], [الكمية: x=580-680], [البيان: x=750-950]
      final blocks = <OcrBlockItem>[
        // Title block above table
        const OcrBlockItem(
          text: 'فاتورة مبيعات شركة الأمل',
          top: 30,
          left: 300,
          width: 400,
          height: 35,
          isRtl: true,
        ),

        // Header Row (RTL on paper)
        const OcrBlockItem(
          text: 'البيان',
          top: 100,
          left: 750,
          width: 200,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'الكمية',
          top: 100,
          left: 580,
          width: 100,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'السعر',
          top: 100,
          left: 350,
          width: 100,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'الإجمالي',
          top: 100,
          left: 100,
          width: 120,
          height: 30,
          isRtl: true,
        ),

        // Row 1: Full cells
        const OcrBlockItem(
          text: 'شاشات سامسونج',
          top: 160,
          left: 750,
          width: 200,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '5',
          top: 160,
          left: 580,
          width: 100,
          height: 30,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: '2000',
          top: 160,
          left: 350,
          width: 100,
          height: 30,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: '10000',
          top: 160,
          left: 100,
          width: 120,
          height: 30,
          isRtl: false,
        ),

        // Row 2: Empty quantity column on paper (should NOT shift price into quantity!)
        const OcrBlockItem(
          text: 'صيانة وتوصيل',
          top: 220,
          left: 750,
          width: 200,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '500',
          top: 220,
          left: 350,
          width: 100,
          height: 30,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: '500',
          top: 220,
          left: 100,
          width: 120,
          height: 30,
          isRtl: false,
        ),
      ];

      final result = service.extractTableFromBlocks(blocks: blocks);

      // Title must be identified cleanly
      expect(result.title, equals('فاتورة مبيعات شركة الأمل'));
      expect(result.isRtl, isTrue);

      // Headers must be ordered RTL (Right-to-Left):
      // Col 0: البيان (Rightmost)
      // Col 1: الكمية
      // Col 2: السعر
      // Col 3: الإجمالي (Leftmost)
      expect(result.headers.length, equals(4));
      expect(result.headers[0], contains('البيان'));
      expect(result.headers[1], contains('الكمية'));
      expect(result.headers[2], contains('السعر'));
      expect(result.headers[3], contains('الإجمالي'));

      // Row 1 verification
      expect(result.rows.length, equals(2));
      expect(result.rows[0][0], equals('شاشات سامسونج'));
      expect(result.rows[0][1], equals('5'));
      expect(result.rows[0][2], equals('2000'));
      expect(result.rows[0][3], equals('10000'));

      // Row 2 verification: Empty quantity column must remain empty!
      // Price '500' must stay in Col 2 (السعر) and Total '500' in Col 3 (الإجمالي)
      // It must NEVER be shifted into Col 1 (الكمية)!
      expect(result.rows[1][0], equals('صيانة وتوصيل'));
      expect(result.rows[1][1], isEmpty); // Quantity is empty!
      expect(result.rows[1][2], equals('500')); // Price stayed in Price column!
      expect(result.rows[1][3], equals('500')); // Total stayed in Total column!
    });

    test('Merges multi-line text falling into the same column without knocking subsequent columns', () {
      final blocks = <OcrBlockItem>[
        // Header
        const OcrBlockItem(
          text: 'Item',
          top: 50,
          left: 100,
          width: 200,
          height: 25,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: 'Amount',
          top: 50,
          left: 400,
          width: 100,
          height: 25,
          isRtl: false,
        ),

        // Row with multi-line item description: "Cloud Hosting" and "Enterprise Tier"
        const OcrBlockItem(
          text: 'Cloud Hosting',
          top: 100,
          left: 100,
          width: 180,
          height: 25,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: 'Enterprise Tier',
          top: 110,
          left: 105,
          width: 170,
          height: 25,
          isRtl: false,
        ),
        const OcrBlockItem(
          text: '750',
          top: 105,
          left: 400,
          width: 90,
          height: 25,
          isRtl: false,
        ),
      ];

      final result = service.extractTableFromBlocks(blocks: blocks);

      expect(result.headers.length, equals(2));
      expect(result.rows.length, equals(1));
      // Multi-line cell is joined cleanly in column 0
      expect(result.rows[0][0], contains('Cloud Hosting'));
      expect(result.rows[0][0], contains('Enterprise Tier'));
      // Amount stays in column 1
      expect(result.rows[0][1], equals('750'));
    });
  });

  group('InteractiveTableEditorScreen: UI & Zero Overflow Responsiveness', () {
    testWidgets('Renders Apple Bento Spreadsheet Grid with zero overflow on Small Phone (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InteractiveTableEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('جدول البيانات الذكي'), findsOneWidget);
      expect(find.byType(InteractiveTableEditorScreen), findsOneWidget);
      expect(find.text('صف جديد'), findsOneWidget);
      expect(find.text('عمود جديد'), findsOneWidget);
      expect(find.text('تصدير Excel (.xlsx)'), findsOneWidget);
      expect(find.text('تصدير PDF'), findsOneWidget);

      // Verify no RenderFlex errors were captured
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders Apple Bento Spreadsheet Grid with zero overflow on Standard Phone (390x844)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InteractiveTableEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveTableEditorScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders Apple Bento Spreadsheet Grid with zero overflow on Tablet Portrait (800x1280)', (tester) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InteractiveTableEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveTableEditorScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
