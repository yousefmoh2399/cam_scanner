import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cam_scanner/features/scanner/data/smart_field_extractor_service.dart';
import 'package:cam_scanner/features/scanner/data/exif_scrubber_service.dart';
import 'package:cam_scanner/features/scanner/data/government_preset_service.dart';
import 'package:cam_scanner/shared/models/pending_upload.dart';

void main() {
  group('SmartFieldExtractorService Tests', () {
    const service = SmartFieldExtractorService();

    test('decodes valid Egyptian National ID (born 1995, Cairo, Male)', () {
      // 2: 1900s, 950815: 1995-08-15, 01: Cairo, 1235: serial (5 at index 12 is odd -> male), 5: check
      const id = '29508150112355';
      final info = service.decodeNationalId(id);

      expect(info, isNotNull);
      expect(info!.id, equals(id));
      expect(info.isValid, isTrue);
      expect(info.birthDate.year, equals(1995));
      expect(info.birthDate.month, equals(8));
      expect(info.birthDate.day, equals(15));
      expect(info.governorate, equals('القاهرة'));
      expect(info.gender, equals('ذكر'));
      expect(info.formatted, contains('القاهرة'));
      expect(info.formatted, contains('ذكر'));
    });

    test('decodes valid Egyptian National ID (born 2002, Alexandria, Female)', () {
      // 3: 2000s, 020320: 2002-03-20, 02: Alexandria, 564: serial (4 at index 12 is even -> female), 9: check
      const id = '30203200256489';
      final info = service.decodeNationalId(id);

      expect(info, isNotNull);
      expect(info!.id, equals(id));
      expect(info.isValid, isTrue);
      expect(info.birthDate.year, equals(2002));
      expect(info.birthDate.month, equals(3));
      expect(info.birthDate.day, equals(20));
      expect(info.governorate, equals('الإسكندرية'));
      expect(info.gender, equals('أنثى'));
    });

    test('rejects invalid national ID lengths and invalid governorates', () {
      expect(service.decodeNationalId('12345'), isNull);
      expect(service.decodeNationalId('49508150112345')?.isValid, isFalse); // Century 4 invalid
      expect(service.decodeNationalId('29508159912345')?.isValid, isFalse); // Gov 99 invalid
    });

    test('extracts multiple fields (national ID, Egyptian phone, email, date, amounts)', () {
      const sampleText = '''
جمهورية مصر العربية
بطاقة رقم قومي: 29508150112355
رقم المحمول للتواصل: 01012345678 أو 01198765432
البريد الإلكتروني: user@example.com
تاريخ التحرير: 15/08/2023
المبلغ الإجمالي المدفوع: 1,500.00 جنيه
''';

      final extracted = service.extractFromText(sampleText);
      expect(extracted.isEmpty, isFalse);
      expect(extracted.nationalIds.length, equals(1));
      expect(extracted.nationalIds.first.governorate, equals('القاهرة'));
      expect(extracted.phones, contains('01012345678'));
      expect(extracted.phones, contains('01198765432'));
      expect(extracted.emails, contains('user@example.com'));
      expect(extracted.dates, contains('15/08/2023'));
      expect(extracted.amounts.isNotEmpty, isTrue);
    });

    test('detectAutoCategory classifies documents properly', () {
      expect(service.detectAutoCategory('صورة بطاقة الرقم القومي'), equals('هوية وبطاقات'));
      expect(service.detectAutoCategory('إيصال سداد فاتورة كهرباء شهر مايو'), equals('فواتير وإيصالات'));
      expect(service.detectAutoCategory('عقد إيجار شقة سكنية وشروط الاتفاق'), equals('عقود ووثائق'));
      expect(service.detectAutoCategory('شهادة تخرج وبيان درجات معتمد'), equals('شهادات رسمية'));
      expect(service.detectAutoCategory('ملاحظات عامة وقائمة مهام يومية'), equals(''));
    });

    test('generateVCard creates valid 2.1 vCard', () {
      final vcard = service.generateVCard('أحمد محمد', '01012345678', email: 'ahmed@test.com');
      expect(vcard, contains('BEGIN:VCARD'));
      expect(vcard, contains('VERSION:2.1'));
      expect(vcard, contains('FN:أحمد محمد'));
      expect(vcard, contains('TEL;CELL:01012345678'));
      expect(vcard, contains('EMAIL;INTERNET:ahmed@test.com'));
      expect(vcard, contains('END:VCARD'));
    });
  });

  group('ExifScrubberService Tests', () {
    const scrubber = ExifScrubberService();

    test('isExifClean returns true when no GPS tags are present', () {
      final dummyBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
      expect(scrubber.isExifClean(dummyBytes), isTrue);
    });

    test('isExifClean returns false when GPS IFD tag is simulated', () {
      final gpsBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x20, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
        0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
        0x25, 0x88, 0x04, 0x00 // Tag 0x8825 GPS Info IFD
      ]);
      expect(scrubber.isExifClean(gpsBytes), isFalse);
    });
  });

  group('GovernmentPresetService Tests', () {
    test('portalPresets contains Egyptian governmental target sizes', () {
      expect(GovernmentPresetService.portalPresets.length, greaterThanOrEqualTo(4));
      expect(GovernmentPresetService.portalPresets.any((p) => p.kb == 100), isTrue);
      expect(GovernmentPresetService.portalPresets.any((p) => p.kb == 200), isTrue);
      expect(GovernmentPresetService.portalPresets.any((p) => p.kb == 500), isTrue);
      expect(GovernmentPresetService.portalPresets.any((p) => p.kb == 1024), isTrue);
    });
  });

  group('Trash & PendingUpload Model Tests', () {
    test('Soft-delete sets deletedAt and isDeleted correctly', () {
      final doc = PendingUpload(
        id: 'doc-123',
        fileName: 'وثيقة اختبار',
        filePath: '/tmp/test.pdf',
        createdAt: DateTime.now(),
        pageCount: 1,
      );

      expect(doc.isDeleted, isFalse);
      expect(doc.deletedAt, isNull);
      expect(doc.isFavorite, isFalse);

      final trashed = doc.copyWith(deletedAt: DateTime.now(), isFavorite: true, category: 'هوية وبطاقات');
      expect(trashed.isDeleted, isTrue);
      expect(trashed.deletedAt, isNotNull);
      expect(trashed.isFavorite, isTrue);
      expect(trashed.category, equals('هوية وبطاقات'));

      final restored = trashed.copyWith(clearDeletedAt: true);
      expect(restored.isDeleted, isFalse);
      expect(restored.deletedAt, isNull);
      expect(restored.isFavorite, isTrue); // Favorite preserved
    });
  });
}
