import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cam_scanner/features/scanner/data/office_exporter_service.dart';

void main() {
  group('Intelligent Excel Export: Arabic Digit Normalization & Number Parsing', () {
    test('normalizeArabicDigits converts Eastern Arabic numerals and separators', () {
      expect(
        OfficeExporterService.normalizeArabicDigits('٠١٢٣٤٥٦٧٨٩'),
        equals('0123456789'),
      );
      expect(
        OfficeExporterService.normalizeArabicDigits('١٥٫٧٥'),
        equals('15.75'),
      );
      expect(
        OfficeExporterService.normalizeArabicDigits('١٬٥٠٠'),
        equals('1500'),
      );
    });

    test('parseFlexibleNumber parses western and Eastern Arabic integers', () {
      expect(OfficeExporterService.parseFlexibleNumber('1250'), equals(1250));
      expect(OfficeExporterService.parseFlexibleNumber('١٢٥٠'), equals(1250));
      expect(OfficeExporterService.parseFlexibleNumber(' 42 '), equals(42));
    });

    test('parseFlexibleNumber parses western and Arabic decimal floats', () {
      expect(OfficeExporterService.parseFlexibleNumber('15.75'), equals(15.75));
      expect(OfficeExporterService.parseFlexibleNumber('١٥٫٧٥'), equals(15.75));
      expect(OfficeExporterService.parseFlexibleNumber('1500,50'), equals(1500.50));
    });

    test('parseFlexibleNumber parses currencies and percentages', () {
      expect(OfficeExporterService.parseFlexibleNumber('500 ج.م'), equals(500));
      expect(OfficeExporterService.parseFlexibleNumber('250 ر.س'), equals(250));
      expect(OfficeExporterService.parseFlexibleNumber('\$1,200'), equals(1200));
      expect(OfficeExporterService.parseFlexibleNumber('25%'), equals(25));
      expect(OfficeExporterService.parseFlexibleNumber('٢٥٪'), equals(25));
    });

    test('parseFlexibleNumber parses negative numbers (trailing minus, accounting parens)', () {
      expect(OfficeExporterService.parseFlexibleNumber('-150'), equals(-150));
      expect(OfficeExporterService.parseFlexibleNumber('150-'), equals(-150));
      expect(OfficeExporterService.parseFlexibleNumber('(250)'), equals(-250));
      expect(OfficeExporterService.parseFlexibleNumber('(٢٥٠)'), equals(-250));
    });

    test('parseFlexibleNumber preserves phone numbers, codes, dates, and text as null', () {
      // Phone numbers / codes with leading zeros must stay text so Excel does not drop the zero
      expect(OfficeExporterService.parseFlexibleNumber('01012345678'), isNull);
      expect(OfficeExporterService.parseFlexibleNumber('0042'), isNull);

      // Dates must stay text
      expect(OfficeExporterService.parseFlexibleNumber('2026/10/05'), isNull);
      expect(OfficeExporterService.parseFlexibleNumber('15-05-2024'), isNull);

      // Regular descriptions
      expect(OfficeExporterService.parseFlexibleNumber('طابعة ليزر ملونة'), isNull);
      expect(OfficeExporterService.parseFlexibleNumber('HP LaserJet Pro 400'), isNull);
    });
  });

  group('Intelligent Excel Export: Workbook Generation & Table Grid Structure', () {
    test('Builds professional Arabic RTL Excel workbook with cell borders and numbers', () {
      // Simulate OCR blocks of a scanned Arabic invoice table
      // Columns (RTL on paper):
      // [م: x=900], [اسم الصنف: x=700], [الكمية: x=500], [السعر: x=300], [الإجمالي: x=100]
      final blocks = <OcrBlockItem>[
        // Header row
        const OcrBlockItem(
          text: 'م',
          top: 100,
          left: 900,
          width: 40,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'اسم الصنف',
          top: 100,
          left: 650,
          width: 150,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'الكمية',
          top: 100,
          left: 480,
          width: 80,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'السعر',
          top: 100,
          left: 280,
          width: 80,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'الإجمالي',
          top: 100,
          left: 80,
          width: 100,
          height: 30,
          isRtl: true,
        ),

        // Row 1 (all columns filled)
        const OcrBlockItem(
          text: '١',
          top: 150,
          left: 900,
          width: 40,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'طابعة ليزر',
          top: 150,
          left: 650,
          width: 150,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '٢',
          top: 150,
          left: 480,
          width: 80,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '١٥٠٠',
          top: 150,
          left: 280,
          width: 80,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '٣٠٠٠',
          top: 150,
          left: 80,
          width: 100,
          height: 30,
          isRtl: true,
        ),

        // Row 2 (missing Qty cell: [Serial=2, Item="حبر أسود", Price=250, Total=250])
        const OcrBlockItem(
          text: '٢',
          top: 200,
          left: 900,
          width: 40,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'حبر أسود',
          top: 200,
          left: 650,
          width: 150,
          height: 30,
          isRtl: true,
        ),
        // Qty at 480 is missing on paper!
        const OcrBlockItem(
          text: '٢٥٠',
          top: 200,
          left: 280,
          width: 80,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '٢٥٠',
          top: 200,
          left: 80,
          width: 100,
          height: 30,
          isRtl: true,
        ),

        // Summary row (Total)
        const OcrBlockItem(
          text: 'المجموع الكلي',
          top: 260,
          left: 650,
          width: 200,
          height: 30,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: '٣٢٥٠ ج.م',
          top: 260,
          left: 80,
          width: 120,
          height: 30,
          isRtl: true,
        ),
      ];

      final page = PageOcrResult(
        pageIndex: 0,
        imagePath: '/tmp/test_invoice.jpg',
        imageBytes: Uint8List(0),
        imageWidth: 1000,
        imageHeight: 1400,
        blocks: blocks,
        fullText: blocks.map((b) => b.text).join('\n'),
      );

      // Verify format properties
      expect(ExportFormat.xlsx.extension, equals('xlsx'));
      expect(ExportFormat.xlsx.usesOcr, isTrue);
      expect(ExportFormat.xlsx.title, contains('Excel'));

      // Build the Excel workbook directly
      final excelBytes = OfficeExporterService.buildXlsxWorkbook(
        documentTitle: 'فاتورة تجريبية',
        pages: [page],
      );
      expect(excelBytes.isNotEmpty, isTrue);

      // Decode generated Excel workbook
      final excelFile = Excel.decodeBytes(excelBytes);
      expect(excelFile.tables.containsKey('صفحة 1'), isTrue);

      // Verify OpenXML sheet XML contains rightToLeft="1"
      final archive = ZipDecoder().decodeBytes(excelBytes);
      final sheetXmlFile = archive.files.firstWhere(
        (f) => f.name.endsWith('sheet1.xml'),
      );
      sheetXmlFile.decompress();
      final sheetXml = utf8.decode(sheetXmlFile.content as List<int>);
      expect(sheetXml.contains('rightToLeft="1"'), isTrue);

      final sheet = excelFile.tables['صفحة 1']!;

      // Verify Title Banner at Row 0
      final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      expect(titleCell.value.toString(), contains('فاتورة تجريبية'));

      // Verify Table Header at Row 3
      // In RTL sheet, Column 0 is the rightmost column on paper ("م")!
      final col0Header = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3));
      expect(col0Header.value.toString(), equals('م'));
      expect(col0Header.cellStyle?.isBold, isTrue);

      // Column 1 in Excel should be "اسم الصنف"
      final col1Header = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3));
      expect(col1Header.value.toString(), equals('اسم الصنف'));

      // Verify Data Row 1 (Row 4): Numbers must be parsed as IntCellValue / DoubleCellValue
      final serial1Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4));
      expect(serial1Cell.value, isA<IntCellValue>());
      expect((serial1Cell.value as IntCellValue).value, equals(1));

      final item1Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4));
      expect(item1Cell.value, isA<TextCellValue>());
      expect((item1Cell.value as TextCellValue).value.toString(), equals('طابعة ليزر'));

      final qty1Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 4));
      expect(qty1Cell.value, isA<IntCellValue>());
      expect((qty1Cell.value as IntCellValue).value, equals(2));

      final price1Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 4));
      expect(price1Cell.value, isA<IntCellValue>());
      expect((price1Cell.value as IntCellValue).value, equals(1500));

      final total1Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4));
      expect(total1Cell.value, isA<IntCellValue>());
      expect((total1Cell.value as IntCellValue).value, equals(3000));

      // Verify Data Row 2 (Row 5): Column Alignment with missing cell
      // Row 2 had no Qty cell at Column 2!
      // Serial=2, Item="حبر أسود", Price=250, Total=250
      final serial2Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5));
      expect((serial2Cell.value as IntCellValue).value, equals(2));

      final item2Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 5));
      expect((item2Cell.value as TextCellValue).value.toString(), equals('حبر أسود'));

      // Column 2 (Qty) should be EMPTY (null value or empty), NOT shifted with price!
      final qty2Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 5));
      expect(qty2Cell.value, isNull);

      // Column 3 (Price) must have 250!
      final price2Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 5));
      expect(price2Cell.value, isA<IntCellValue>());
      expect((price2Cell.value as IntCellValue).value, equals(250));

      // Column 4 (Total) must have 250!
      final total2Cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 5));
      expect(total2Cell.value, isA<IntCellValue>());
      expect((total2Cell.value as IntCellValue).value, equals(250));

      // Verify Summary Row (Row 6)
      final summaryTotalCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 6));
      expect(summaryTotalCell.value, isA<IntCellValue>());
      expect((summaryTotalCell.value as IntCellValue).value, equals(3250));
    });

    test('Splits single-line delimited blocks (pipes, multi-spaces) into discrete Excel cells', () {
      final blocks = <OcrBlockItem>[
        // Header line delimited by spaces
        const OcrBlockItem(
          text: 'Code    Product Name    Qty    Price    Total',
          top: 50,
          left: 50,
          width: 800,
          height: 25,
          isRtl: false,
        ),
        // Row 1 delimited by pipes
        const OcrBlockItem(
          text: 'P101 | Wireless Mouse | 10 | 25.50 | 255',
          top: 100,
          left: 50,
          width: 800,
          height: 25,
          isRtl: false,
        ),
        // Row 2 delimited by tabs
        const OcrBlockItem(
          text: 'P102\tMechanical Keyboard\t5\t80.00\t400',
          top: 150,
          left: 50,
          width: 800,
          height: 25,
          isRtl: false,
        ),
      ];

      final page = PageOcrResult(
        pageIndex: 0,
        imagePath: '/tmp/test_delimited.jpg',
        imageBytes: Uint8List(0),
        imageWidth: 900,
        imageHeight: 1200,
        blocks: blocks,
        fullText: blocks.map((b) => b.text).join('\n'),
      );

      final excelBytes = OfficeExporterService.buildXlsxWorkbook(
        documentTitle: 'Delimited Invoice',
        pages: [page],
      );

      final excelFile = Excel.decodeBytes(excelBytes);
      final sheet = excelFile.tables['صفحة 1']!;

      // Header row (Row 3)
      final col0Header = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3));
      expect(col0Header.value.toString(), equals('Code'));

      final col1Header = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3));
      expect(col1Header.value.toString(), equals('Product Name'));

      // Data Row 1 (Row 4)
      final p101Code = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4));
      expect(p101Code.value.toString(), equals('P101'));

      final p101Qty = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 4));
      expect(p101Qty.value, isA<IntCellValue>());
      expect((p101Qty.value as IntCellValue).value, equals(10));

      final p101Price = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 4));
      expect(p101Price.value, isA<DoubleCellValue>());
      expect((p101Price.value as DoubleCellValue).value, equals(25.5));

      final p101Total = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4));
      expect(p101Total.value, isA<IntCellValue>());
      expect((p101Total.value as IntCellValue).value, equals(255));

      // Data Row 2 (Row 5)
      final p102Total = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 5));
      expect(p102Total.value, isA<IntCellValue>());
      expect((p102Total.value as IntCellValue).value, equals(400));
    });

    test('Exports plain non-tabular document cleanly into Excel rows', () {
      final blocks = <OcrBlockItem>[
        const OcrBlockItem(
          text: 'شهادة تقدير وتكريم للموظف المثالي',
          top: 80,
          left: 100,
          width: 600,
          height: 35,
          isRtl: true,
        ),
        const OcrBlockItem(
          text: 'تتقدم إدارة الشركة بخالص الشكر والتقدير للجهود المبذولة خلال عام 2026',
          top: 150,
          left: 80,
          width: 640,
          height: 30,
          isRtl: true,
        ),
      ];

      final page = PageOcrResult(
        pageIndex: 0,
        imagePath: '/tmp/test_cert.jpg',
        imageBytes: Uint8List(0),
        imageWidth: 800,
        imageHeight: 1100,
        blocks: blocks,
        fullText: blocks.map((b) => b.text).join('\n'),
      );

      final excelBytes = OfficeExporterService.buildXlsxWorkbook(
        documentTitle: 'شهادة تقدير',
        pages: [page],
      );

      final excelFile = Excel.decodeBytes(excelBytes);
      final sheet = excelFile.tables['صفحة 1']!;

      final row0Text = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3));
      expect(row0Text.value.toString(), contains('شهادة تقدير'));

      final row1Text = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4));
      expect(row1Text.value.toString(), contains('تتقدم إدارة الشركة'));
    });
  });
}
