import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ContractType {
  residentialLease('عقد إيجار شقة سكنية', 'عقد إيجار قانوني محدد المدة ومطابق للقانون المدني', 'lease'),
  promissoryNote('إيصال أمانة قانوني', 'صيغة إيصال أمانة جنائية معتمدة أمام المحاكم', 'note'),
  vehicleSale('عقد بيع سيارة نهائي', 'عقد بيع ونقل ملكية مركبة بالثمن والإقرار بالمعاينة', 'car'),
  propertySale('عقد بيع ابتدائي لعقار', 'عقد بيع شقة أو عقار مع الشرط الجزائي والأقساط', 'property'),
  nda('اتفاقية سرية وعدم إفشاء (NDA)', 'حماية الأفكار وبيانات المشاريع التجارية من التسريب', 'nda'),
  freelanceService('عقد تقديم خدمات وعمل حر', 'اتفاقية تسليم مراحل العمل وحفظ الحقوق المالية', 'freelance');

  const ContractType(this.titleAr, this.subtitleAr, this.id);
  final String titleAr;
  final String subtitleAr;
  final String id;
}

class ContractParty {
  ContractParty({
    this.name = '',
    this.nationalId = '',
    this.phone = '',
    this.address = '',
    this.roleTitle = 'الطرف الأول',
  });

  String name;
  String nationalId;
  String phone;
  String address;
  String roleTitle;
}

enum ContractPaperColor {
  white('أبيض رسمي ناصع', 0xFFFFFFFF, 0xFF111827, 0xFF374151, 0xFFF3F4F6),
  ivory('عاجي ملكي دافئ', 0xFFFCF9EE, 0xFF1C1917, 0xFF78716C, 0xFFF5EFE0),
  parchment('ورق قانوني بيج', 0xFFF7F2E4, 0xFF1F1D1A, 0xFF655F55, 0xFFECE3CE),
  softGrey('رمادي مكتبي ناعم', 0xFFF8F9FA, 0xFF1F2937, 0xFF4B5563, 0xFFE5E7EB);

  const ContractPaperColor(
    this.label,
    this.paperHex,
    this.textHex,
    this.borderHex,
    this.cardHex,
  );

  final String label;
  final int paperHex;
  final int textHex;
  final int borderHex;
  final int cardHex;

  PdfColor get pdfPaperColor => PdfColor.fromInt(paperHex);
  PdfColor get pdfTextColor => PdfColor.fromInt(textHex);
  PdfColor get pdfBorderColor => PdfColor.fromInt(borderHex);
  PdfColor get pdfCardColor => PdfColor.fromInt(cardHex);
}

class SmartContractFormData {
  SmartContractFormData({
    required this.type,
    required this.partyA,
    required this.partyB,
    this.partyC,
    this.city = 'القاهرة',
    this.amount = 0.0,
    this.currency = 'جنيه مصري',
    this.itemDescription = '',
    this.duration = 'سنة واحدة',
    DateTime? contractDate,
    DateTime? startDate,
    this.extraClauses = '',
    this.clauses = const [],
    this.paperColor = ContractPaperColor.white,
  })  : contractDate = contractDate ?? DateTime.now(),
        startDate = startDate ?? DateTime.now();

  final ContractType type;
  final ContractParty partyA;
  final ContractParty partyB;
  final ContractParty? partyC;
  final String city;
  final double amount;
  final String currency;
  final String itemDescription;
  final String duration;
  final DateTime contractDate;
  final DateTime startDate;
  final String extraClauses;
  final List<String> clauses;
  final ContractPaperColor paperColor;
}

class SmartContractService {
  static Uint8List? _cachedCairoFont;

  static Future<Uint8List?> _loadCairoFont() async {
    if (_cachedCairoFont != null) return _cachedCairoFont;
    try {
      final data = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _cachedCairoFont = data.buffer.asUint8List();
      return _cachedCairoFont;
    } catch (_) {
      return null;
    }
  }

  /// Converts a numeric amount into formal Arabic words (Tafqeet)
  static String numberToArabicWords(double amount, [String currency = 'جنيه مصري']) {
    final intPart = amount.toInt();
    if (intPart == 0) return 'صفر $currency';

    final ones = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة'];
    final tens = ['', 'عشرة', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
    final hundreds = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];
    final thousands = ['', 'ألف', 'ألفان', 'ثلاثة آلاف', 'أربعة آلاف', 'خمسة آلاف', 'ستة آلاف', 'سبعة آلاف', 'ثمانية آلاف', 'تسعة آلاف'];

    String result = '';
    if (intPart >= 1000) {
      final th = (intPart ~/ 1000).clamp(0, 9);
      result += '${thousands[th]} ';
    }
    final rem1000 = intPart % 1000;
    if (rem1000 >= 100) {
      final h = (rem1000 ~/ 100).clamp(0, 9);
      if (result.isNotEmpty) result += 'و';
      result += '${hundreds[h]} ';
    }
    final rem100 = rem1000 % 100;
    if (rem100 > 0) {
      if (result.isNotEmpty) result += 'و';
      if (rem100 < 10) {
        result += '${ones[rem100]} ';
      } else if (rem100 == 10) {
        result += 'عشرة ';
      } else if (rem100 == 11) {
        result += 'أحد عشر ';
      } else if (rem100 == 12) {
        result += 'اثنا عشر ';
      } else if (rem100 < 20) {
        result += '${ones[rem100 % 10]} عشر ';
      } else {
        final o = rem100 % 10;
        final t = rem100 ~/ 10;
        if (o > 0) result += '${ones[o]} و';
        result += '${tens[t]} ';
      }
    }

    return 'فقط وقدره ${result.trim()} $currency لا غير';
  }

  /// Builds a high-quality, legally formatted PDF contract
  Future<Uint8List> generateContractPdf(SmartContractFormData data) async {
    final pdf = pw.Document();
    final fontBytes = await _loadCairoFont();
    final cairo = fontBytes != null ? pw.Font.ttf(fontBytes.buffer.asByteData()) : null;

    final paperBg = data.paperColor.pdfPaperColor;
    final textColor = data.paperColor.pdfTextColor;
    final borderColor = data.paperColor.pdfBorderColor;
    final cardBg = data.paperColor.pdfCardColor;

    final baseStyle = pw.TextStyle(font: cairo, fontSize: 10, color: textColor);
    final boldStyle = pw.TextStyle(font: cairo, fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: textColor);
    final headerStyle = pw.TextStyle(font: cairo, fontSize: 16.5, fontWeight: pw.FontWeight.bold, color: textColor);

    final clauses = data.clauses.isNotEmpty ? data.clauses : generateDefaultClauses(data);
    final dateStr = '${data.contractDate.year}/${data.contractDate.month.toString().padLeft(2, '0')}/${data.contractDate.day.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        theme: pw.ThemeData.withFont(base: cairo, bold: cairo),
        build: (pw.Context ctx) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: paperBg, // Guaranteed solid opaque paper background
                border: pw.Border.all(color: borderColor, width: 1.5),
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Title & Emblem
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(data.type.titleAr, style: headerStyle),
                        pw.SizedBox(height: 4),
                        pw.Container(width: 140, height: 1.5, color: borderColor),
                        pw.SizedBox(height: 2),
                        pw.Container(width: 80, height: 0.5, color: borderColor),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),

                  // Introduction Line
                  pw.Text(
                    'إنه في يوم ${_arabicDayName(data.contractDate.weekday)} الموافق $dateStr ميلادية، في مدينة ${data.city}، تم الاتفاق والتراضي بين كلٍ من:',
                    style: baseStyle,
                  ),
                  pw.SizedBox(height: 8),

                  // Party A Box
                  _buildPartyBox(
                    title: 'أولاً: ${data.partyA.roleTitle}',
                    party: data.partyA,
                    baseStyle: baseStyle,
                    boldStyle: boldStyle,
                    bgColor: cardBg,
                  ),
                  pw.SizedBox(height: 6),

                  // Party B Box
                  _buildPartyBox(
                    title: 'ثانياً: ${data.partyB.roleTitle}',
                    party: data.partyB,
                    baseStyle: baseStyle,
                    boldStyle: boldStyle,
                    bgColor: cardBg,
                  ),

                  // Party C Box (If Trust Receipt)
                  if (data.partyC != null && data.partyC!.name.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    _buildPartyBox(
                      title: 'ثالثاً: ${data.partyC!.roleTitle}',
                      party: data.partyC!,
                      baseStyle: baseStyle,
                      boldStyle: boldStyle,
                      bgColor: cardBg,
                    ),
                  ],

                  pw.SizedBox(height: 10),
                  pw.Text('وبعد أن أقر أطراف هذا الاتفاق بكامل أهليتهم القانونية والتصرف، اتفقوا على البنود الآتية:', style: baseStyle),
                  pw.SizedBox(height: 8),

                  // Numbered Clauses
                  ...clauses.map((clause) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• ', style: boldStyle),
                            pw.Expanded(child: pw.Text(clause, style: baseStyle)),
                          ],
                        ),
                      )),

                  if (data.extraClauses.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('شروط إضافية: ${data.extraClauses.trim()}', style: baseStyle),
                  ],

                  pw.Spacer(),

                  // Signatures Footer
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: borderColor, width: 0.8)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _buildSignatureBox(title: data.partyA.roleTitle, name: data.partyA.name, style: boldStyle),
                        _buildSealBox(style: boldStyle, borderColor: borderColor),
                        _buildSignatureBox(title: data.partyB.roleTitle, name: data.partyB.name, style: boldStyle),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPartyBox({
    required String title,
    required ContractParty party,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
    required PdfColor bgColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: boldStyle),
          pw.SizedBox(height: 2),
          pw.Text(
            'السيد/ ${party.name.isEmpty ? "........................................" : party.name} • الرقم القومي: ${party.nationalId.isEmpty ? "...................." : party.nationalId} • المقيم في: ${party.address.isEmpty ? "...................." : party.address} • الهاتف: ${party.phone.isEmpty ? "...................." : party.phone}',
            style: baseStyle,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureBox({
    required String title,
    required String name,
    required pw.TextStyle style,
  }) {
    return pw.Column(
      children: [
        pw.Text(title, style: style),
        pw.SizedBox(height: 4),
        pw.Text(name.isEmpty ? 'التوقيع: .................' : name, style: style),
        pw.SizedBox(height: 24),
        pw.Text('التوقيع / البصمة: .......................', style: style),
      ],
    );
  }

  static pw.Widget _buildSealBox({
    required pw.TextStyle style,
    required PdfColor borderColor,
  }) {
    return pw.Container(
      width: 70,
      height: 70,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, style: pw.BorderStyle.dashed),
        shape: pw.BoxShape.circle,
      ),
      child: pw.Center(
        child: pw.Text('موضع الختم الرسمي', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8, color: borderColor)),
      ),
    );
  }

  static List<String> generateDefaultClauses(SmartContractFormData d) {
    final moneyWord = numberToArabicWords(d.amount, d.currency);

    switch (d.type) {
      case ContractType.residentialLease:
        return [
          'البند الأول (موضوع العقد): أجر الطرف الأول للطرف الثاني الشقة / العين الكائنة في: (${d.itemDescription.isEmpty ? "العنوان المحدد أعلاه" : d.itemDescription}) بغرض السكن العائلي فقط.',
          'البند الثاني (المدة): مدة هذا الإيجار هي (${d.duration}) تبدأ من تاريخ ${d.startDate.year}/${d.startDate.month}/${d.startDate.day} وتنتهي تلقائياً دون حاجة لتنبيه أو إنذار.',
          'البند الثالث (القيمة الإيجارية): اتفق الطرفان على أن تكون الأجرة الشهرية مبلغ وقدره (${d.amount.toStringAsFixed(0)} ${d.currency}) ($moneyWord) تدفع مقدماً في أول كل شهر.',
          'البند الرابع (التأمين): دفع الطرف الثاني للطرف الأول مبلغ تأمين لضمان سلامة العين يسترده عند انتهاء العقد بعد تسليم الشقة وسداد فواتير المرافق.',
          'البند الخامس: لا يجوز للمستأجر التنازل عن الإيجار أو التأجير من الباطن كلياً أو جزئياً إلا بإذن كتابي صريح من المؤجر.',
        ];

      case ContractType.promissoryNote:
        return [
          'أقر أنا الموقع أدناه (${d.partyA.name}) المقيم في (${d.partyA.address}) وبطاقتي رقم (${d.partyA.nationalId})، بأنني تسلمت من السيد (${d.partyB.name}) مبلغاً وقدره (${d.amount.toStringAsFixed(0)} ${d.currency}) ($moneyWord).',
          'وذلك على سبيل الأمانة لتسليمه للسيد (${d.partyC?.name.isNotEmpty == true ? d.partyC!.name : "الطرف الثاني نفسه"}).',
          'وإذا لم أقم بتسليم هذا المبلغ أكون خائناً للأمانة ومبدداً للمبلغ، وأتحمل المسؤولية الجنائية والمدنية المنصوص عليها بالمادة 341 من قانون العقوبات.',
        ];

      case ContractType.vehicleSale:
        return [
          'البند الأول (المبيع): باع وأسقط وتنازل الطرف الأول بكافة الضمانات الفعلية والقانونية للطرف الثاني القابل لذلك المركبة المبينة بالمواصفات الآتية: (${d.itemDescription.isEmpty ? "سيارة ملاكي كاملة الأوصاف" : d.itemDescription}).',
          'البند الثاني (الثمن): تم هذا البيع برضاء وقبول نظير ثمن إجمالي قدره (${d.amount.toStringAsFixed(0)} ${d.currency}) ($moneyWord) سدده الطرف الثاني بالكامل ليد الطرف الأول وقت توقيع هذا العقد ويعتبر توقيعه مخالصة تامة.',
          'البند الثالث (المعاينة والتسليم): أقر الطرف الثاني بأنه عاين السيارة موضوع العقد المعاينة التامة النافية للجهالة وقبل شرائها بحالتها الراهنة وتسلم حيازتها ورخصتها.',
        ];

      case ContractType.propertySale:
        return [
          'البند الأول (المبيع): باع الطرف الأول وأسقط وتنازل للطرف الثاني العقار / الوحدة الكائنة في: (${d.itemDescription}) والمحددة بالحدود والمعالم الرسمية.',
          'البند الثاني (الثمن): الثمن المتفق عليه إجمالاً هو (${d.amount.toStringAsFixed(0)} ${d.currency}) ($moneyWord).',
          'البند الثالث (الملكية): يقر الطرف الأول بأن ملكية المبيع آلت إليه بطريق قانوني صحيح، وأنه خالٍ من أية ديون أو حقوق عينية للغير.',
          'البند الرابع (الشرط الجزائي): اتفق الطرفان على شرط جزائي قدره 10% من قيمة العقد في حال إخلال أي طرف بالتزاماته التعاقدية.',
        ];

      case ContractType.nda:
        return [
          'البند الأول (الهدف): يتبادل الطرفان معلومات سرية تخص مشروع (${d.itemDescription.isEmpty ? "التعاون المشترك" : d.itemDescription}).',
          'البند الثاني (الالتزام بالسرية): يتعهد الطرف المتلقي بالحفاظ على سرية كافة البيانات الفنية، التجارية، والشفرات البرمجية وعدم إفشائها لأي طرف ثالث.',
          'البند الثالث (المدة): يسري هذا الالتزام بالسرية طوال فترة التفاوض ولمدة (${d.duration}) من تاريخ التوقيع.',
        ];

      case ContractType.freelanceService:
        return [
          'البند الأول (نطاق العمل): كلف الطرف الأول الطرف الثاني بالقيام بمهام: (${d.itemDescription}).',
          'البند الثاني (الأتعاب): يلتزم الطرف الأول بسداد أتعاب إجمالية قدرها (${d.amount.toStringAsFixed(0)} ${d.currency}) ($moneyWord) وفق مراحل الإنجاز المحددة.',
          'البند الثالث (حقوق الملكية الفكرية): تنتقل كافة حقوق الملكية الفكرية للمخرجات للطرف الأول فور سداد كامل الأتعاب المتفق عليها.',
        ];
    }
  }

  static String _arabicDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      default:
        return '';
    }
  }
}
