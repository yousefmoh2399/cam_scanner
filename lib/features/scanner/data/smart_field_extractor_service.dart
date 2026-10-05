import 'dart:io';

import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

/// Decoded information from a 14-digit Egyptian national ID number.
class EgyptianIdInfo {
  const EgyptianIdInfo({
    required this.id,
    required this.birthDate,
    required this.governorate,
    required this.gender,
    required this.isValid,
  });

  /// The raw 14-digit ID string.
  final String id;

  /// Date of birth decoded from the ID.
  final DateTime birthDate;

  /// Arabic name of the governorate encoded in digits 7-8 (1-indexed).
  final String governorate;

  /// `'ذكر'` or `'أنثى'`.
  final String gender;

  /// Whether the ID passed basic structural validation.
  final bool isValid;

  /// Full human-readable summary in Arabic.
  String get formatted {
    final day = birthDate.day.toString().padLeft(2, '0');
    final month = birthDate.month.toString().padLeft(2, '0');
    final year = birthDate.year.toString();
    return 'الرقم القومي: $id\n'
        'تاريخ الميلاد: $day/$month/$year\n'
        'المحافظة: $governorate\n'
        'النوع: $gender';
  }

  @override
  String toString() => formatted;
}

/// All fields extracted from a block of text.
class ExtractedFields {
  const ExtractedFields({
    required this.nationalIds,
    required this.phones,
    required this.emails,
    required this.dates,
    required this.amounts,
  });

  final List<EgyptianIdInfo> nationalIds;
  final List<String> phones;
  final List<String> emails;
  final List<String> dates;
  final List<String> amounts;

  /// Returns `true` when no fields of any kind were extracted.
  bool get isEmpty =>
      nationalIds.isEmpty &&
      phones.isEmpty &&
      emails.isEmpty &&
      dates.isEmpty &&
      amounts.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Offline field extractor. Requires no internet connection.
///
/// Uses regular expressions and Dart standard-library types only.
class SmartFieldExtractorService {
  const SmartFieldExtractorService();

  // ── Patterns ──────────────────────────────────────────────────────────────

  static final RegExp _nationalIdPattern = RegExp(r'\b[23]\d{13}\b');

  static final RegExp _phonePattern = RegExp(r'\b(01[0125])\d{8}\b');

  static final RegExp _emailPattern = RegExp(
    r'\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b',
  );

  static final RegExp _datePattern = RegExp(
    r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b',
  );

  static final RegExp _amountPattern = RegExp(
    r'\b(\d{1,3}(?:[,.]\d{3})*(?:\.\d{2})?\s*(?:جنيه|ج\.م|EGP|USD|\$|€)?)\b',
    unicode: true,
  );

  // ── Governorate table ─────────────────────────────────────────────────────

  static const Map<String, String> _governorates = {
    '01': 'القاهرة',
    '02': 'الإسكندرية',
    '03': 'بورسعيد',
    '04': 'السويس',
    '11': 'دمياط',
    '12': 'الدقهلية',
    '13': 'الشرقية',
    '14': 'القليوبية',
    '15': 'كفر الشيخ',
    '16': 'الغربية',
    '17': 'المنوفية',
    '18': 'البحيرة',
    '19': 'الإسماعيلية',
    '21': 'الجيزة',
    '22': 'بني سويف',
    '23': 'الفيوم',
    '24': 'المنيا',
    '25': 'أسيوط',
    '26': 'سوهاج',
    '27': 'قنا',
    '28': 'أسوان',
    '29': 'الأقصر',
    '31': 'البحر الأحمر',
    '32': 'الوادي الجديد',
    '33': 'مطروح',
    '34': 'شمال سيناء',
    '35': 'جنوب سيناء',
    '88': 'خارج الجمهورية',
  };

  // ── Public API ────────────────────────────────────────────────────────────

  /// Extracts all recognisable fields from [text].
  ExtractedFields extractFromText(String text) {
    // National IDs
    final rawIds = _nationalIdPattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet() // deduplicate
        .toList();
    final ids = rawIds
        .map(decodeNationalId)
        .whereType<EgyptianIdInfo>()
        .toList();

    // Phones
    final phones = _phonePattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();

    // E-mails
    final emails = _emailPattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();

    // Dates
    final dates = _datePattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();

    // Monetary amounts (filter out bare numbers with no currency hint to
    // reduce noise – keep only matches that contain a currency token or a
    // comma/period-separated group-of-thousands pattern).
    final amounts = _amountPattern
        .allMatches(text)
        .map((m) => m.group(0)!.trim())
        .where((s) =>
            s.contains(RegExp(r'جنيه|ج\.م|EGP|USD|\$|€')) ||
            s.contains(RegExp(r'\d{1,3}[,]\d{3}')))
        .toSet()
        .toList();

    return ExtractedFields(
      nationalIds: ids,
      phones: phones,
      emails: emails,
      dates: dates,
      amounts: amounts,
    );
  }

  /// Decodes a 14-digit Egyptian national ID.
  ///
  /// Returns `null` when [id14] is structurally invalid.
  EgyptianIdInfo? decodeNationalId(String id14) {
    if (id14.length != 14) return null;
    if (!RegExp(r'^\d{14}$').hasMatch(id14)) return null;

    // Century digit (index 0)
    final centuryDigit = int.parse(id14[0]);
    int century;
    if (centuryDigit == 2) {
      century = 1900;
    } else if (centuryDigit == 3) {
      century = 2000;
    } else {
      return EgyptianIdInfo(
        id: id14,
        birthDate: DateTime(1970),
        governorate: 'غير معروفة',
        gender: 'غير معروف',
        isValid: false,
      );
    }

    // Birth date (indices 1-6): YYMMDD
    final yy = int.tryParse(id14.substring(1, 3));
    final mm = int.tryParse(id14.substring(3, 5));
    final dd = int.tryParse(id14.substring(5, 7));

    if (yy == null || mm == null || dd == null) return null;
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
      return EgyptianIdInfo(
        id: id14,
        birthDate: DateTime(century + yy),
        governorate: 'غير معروفة',
        gender: 'غير معروف',
        isValid: false,
      );
    }

    final birthDate = DateTime(century + yy, mm, dd);

    // Governorate (indices 7-8)
    final govCode = id14.substring(7, 9);
    final governorate = _governorates[govCode] ?? 'غير معروفة';

    // Gender digit (index 12, 0-based): odd = male, even = female
    final genderDigit = int.parse(id14[12]);
    final gender = genderDigit.isOdd ? 'ذكر' : 'أنثى';

    return EgyptianIdInfo(
      id: id14,
      birthDate: birthDate,
      governorate: governorate,
      gender: gender,
      isValid: _governorates.containsKey(govCode),
    );
  }

  /// Generates a vCard 2.1 string.
  String generateVCard(
    String name,
    String phone, {
    String? email,
    String? company,
    String? title,
  }) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:2.1')
      ..writeln('N:$name;;;;')
      ..writeln('FN:$name')
      ..writeln('TEL;CELL:$phone');

    if (email != null && email.isNotEmpty) {
      buffer.writeln('EMAIL;INTERNET:$email');
    }
    if (company != null && company.isNotEmpty) {
      buffer.writeln('ORG:$company');
    }
    if (title != null && title.isNotEmpty) {
      buffer.writeln('TITLE:$title');
    }

    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  /// Saves [vcardContent] to the app documents directory as `<baseName>.vcf`
  /// and returns the saved file path.
  Future<String> saveVCard(String vcardContent, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeBase = baseName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final file = File('${dir.path}/$safeBase.vcf');
    await file.writeAsString(vcardContent, flush: true);
    return file.path;
  }

  /// Analyses [text] and returns the most likely Arabic document category.
  ///
  /// Returns an empty string when no category is confidently matched.
  String detectAutoCategory(String text) {
    // Keyword sets ordered by specificity (most specific first).
    final patterns = <String, RegExp>{
      'هوية وبطاقات': RegExp(
        r'هوية|بطاقة|رقم قومي|جواز|تصريح',
        unicode: true,
      ),
      'فواتير وإيصالات': RegExp(
        r'فاتورة|إيصال|مبلغ|إجمالي|رسوم|غاز|كهرباء|مياه',
        unicode: true,
      ),
      'عقود ووثائق': RegExp(
        r'عقد|اتفاقية|ملحق|شروط|أطراف',
        unicode: true,
      ),
      'شهادات رسمية': RegExp(
        r'شهادة|إفادة|درجات|نجاح|ميلاد|وفاة',
        unicode: true,
      ),
    };

    for (final entry in patterns.entries) {
      if (entry.value.hasMatch(text)) return entry.key;
    }
    return '';
  }
}
