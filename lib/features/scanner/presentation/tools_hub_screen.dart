import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/document_paper_size.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../data/native_scanner_bridge.dart';
import '../data/office_exporter_service.dart';
import '../data/pdf_builder_service.dart';
import 'government_documents_screen.dart';
import 'pdf_tools_screen.dart';
import 'signature_bottom_sheet.dart';
import 'trash_screen.dart';
import 'vault_screen.dart';
import 'watermark_studio_screen.dart';
import 'auto_redaction_screen.dart';
import 'widgets/apple_bottom_nav_bar.dart';
import 'widgets/cloud_backup_sheet.dart';
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';
import 'document_diff_screen.dart';
import 'magic_clean_screen.dart';
import 'stamp_studio_screen.dart';
import 'web_drop_screen.dart';
import 'smart_contract_studio_screen.dart';
import 'widgets/pdf_security_sheet.dart';
import 'book_curve_flattener_screen.dart';
import 'smart_id_wallet_screen.dart';
import 'transferred_files_screen.dart';
import 'scan_review_screen.dart';
import 'id_card_a4_screen.dart';
import 'notebook_lines_remover_screen.dart';
import 'object_counter_screen.dart';
import 'package:path_provider/path_provider.dart';

import '../data/qr_scanner_service.dart';
import 'anti_moire_whiteboard_screen.dart';
import 'qr_studio_screen.dart';
import 'privacy_scrubber_screen.dart';
import 'interactive_table_editor_screen.dart';
import 'booklet_and_binding_screen.dart';
import 'legal_audit_studio_screen.dart';
import 'lanyard_id_badge_screen.dart';
import 'three_d_maker_studio_screen.dart';

/// Categories for organizing tools in the hub
enum ToolCategory {
  all('الكل', Icons.apps_rounded),
  government('هوية ومستندات', Icons.badge_rounded),
  intelligence('ذكاء ومعالجة', Icons.auto_awesome_rounded),
  pdf('أدوات PDF', Icons.picture_as_pdf_rounded),
  security('أمان وخصوصية', Icons.security_rounded);

  const ToolCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  String get sectionTitle {
    switch (this) {
      case ToolCategory.all:
        return 'جميع الأدوات الذكية';
      case ToolCategory.government:
        return 'الهوية والمستندات الرسمية';
      case ToolCategory.intelligence:
        return 'الذكاء الاصطناعي ومعالجة الورق';
      case ToolCategory.pdf:
        return 'أدوات وإدارة ملفات PDF';
      case ToolCategory.security:
        return 'الأمان والخصوصية وحماية الأوراق';
    }
  }

  String get sectionSubtitle {
    switch (this) {
      case ToolCategory.all:
        return 'تصفح كافة الأدوات المتوفرة واستخدمها بنقرة واحدة';
      case ToolCategory.government:
        return 'تصوير البطاقة وش وضهر، جواز السفر، الصور الشخصية، وكتابة العقود';
      case ToolCategory.intelligence:
        return 'تحويل الجداول لإكسل، مسح العيوب، فرد الكتب، وقراءة النصوص';
      case ToolCategory.pdf:
        return 'دمج وتقسيم الملفات، تصغير الحجم، والنقل للكمبيوتر بدون كابل';
      case ToolCategory.security:
        return 'الخزنة بالبصمة، توقيع العقود، تفريغ الأختام، والعلامة المائية';
    }
  }
}

/// Metadata item describing each tool
class ToolItem {
  const ToolItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.badge,
    required this.accentColor,
    required this.keywords,
  });

  final String id;
  final String title;
  final String subtitle;
  final ToolCategory category;
  final IconData icon;
  final String badge;
  final Color accentColor;
  final List<String> keywords;
}

/// A centralized, beautiful, all-in-one Smart Tools Hub screen.
/// Brings together every utility, scanner function, and document tool into one place.
class ToolsHubScreen extends ConsumerStatefulWidget {
  const ToolsHubScreen({super.key});

  @override
  ConsumerState<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends ConsumerState<ToolsHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  ToolCategory _selectedCategory = ToolCategory.all;
  String _searchQuery = '';
  bool _isProcessing = false;
  bool _isGridView = true;

  final List<ToolItem> _allTools = const [
    // ── Government & Official Category ──
    ToolItem(
      id: 'gov_id_card',
      title: 'تصوير البطاقة وش وضهر (A4)',
      subtitle: 'دمج وجهي بطاقة الرقم القومي أو الرخصة في ورقة A4 واحدة بحجمها الحقيقي 1:1 جاهزة للطباعة فوراً',
      category: ToolCategory.government,
      icon: Icons.badge_rounded,
      badge: 'طباعة 1:1 رسمية',
      accentColor: Color(0xFF007AFF),
      keywords: ['بطاقة', 'هوية', 'رخصة', 'قيادة', 'إقامة', 'id', 'وش وضهر', 'رسمي', 'a4', '1:1', 'طباعة'],
    ),
    ToolItem(
      id: 'gov_passport_cert',
      title: 'مسح جواز السفر والشهادات',
      subtitle: 'تصوير وثائق السفر وشهادات التخرج بأبعاد واضحة وجودة مقبولة لدى السفارات والجامعات',
      category: ToolCategory.government,
      icon: Icons.menu_book_rounded,
      badge: 'معتمد للسفارات',
      accentColor: Color(0xFF5856D6),
      keywords: ['جواز', 'سفر', 'شهادة', 'تخرج', 'عقد', 'رسمي', 'passport'],
    ),
    ToolItem(
      id: 'gov_photo_grid',
      title: 'تجهيز صور شخصية 4×6',
      subtitle: 'ترتيب وتكرار صورك الشخصية على ورقة A4 جاهزة للطباعة في الاستوديو لجواز السفر والتأشيرات',
      category: ToolCategory.government,
      icon: Icons.photo_camera_front_rounded,
      badge: 'مقاس 4×6 جاهز',
      accentColor: Color(0xFF34C759),
      keywords: ['صور', 'شخصية', 'تأشيرة', 'شنغن', 'امريكا', 'سفر', 'جواز', 'طباعة', 'visa'],
    ),
    ToolItem(
      id: 'gov_portal_compress',
      title: 'تصغير المستند للجهات الرسمية',
      subtitle: 'تقليص حجم الملف لأقل من 500 ك.ب أو 1 ميجابايت لرفعه على بوابات التوظيف ومواقع السفارات',
      category: ToolCategory.government,
      icon: Icons.speed_rounded,
      badge: 'مواقع التوظيف',
      accentColor: Color(0xFFFF2D55),
      keywords: ['ضغط', 'بوابات', 'تقديم', 'سفارات', 'توظيف', 'حجم', 'مستند'],
    ),
    ToolItem(
      id: 'gov_smart_contracts',
      title: 'صيغ العقود وإيصالات الأمانة',
      subtitle: 'نماذج قانونية موثقة لعقود الإيجار والبيع وإيصالات الأمانة مع تفقيط المبالغ المالية تلقائياً',
      category: ToolCategory.government,
      icon: Icons.gavel_rounded,
      badge: 'نماذج قانونية',
      accentColor: Color(0xFF5856D6),
      keywords: ['عقد', 'عقود', 'إيجار', 'بيع', 'أمانة', 'إيصال', 'شقة', 'سيارة', 'قانوني'],
    ),
    ToolItem(
      id: 'gov_smart_id_wallet',
      title: 'محفظة الهويات والكروت',
      subtitle: 'حفظ آمن لبطاقاتك وكروتك داخل هاتفك مع إمكانية تصديرها وطباعتها كروت بلاستيك جاهزة',
      category: ToolCategory.government,
      icon: Icons.credit_card_rounded,
      badge: 'كروت بلاستيك',
      accentColor: Color(0xFF007AFF),
      keywords: ['بطاقة', 'بلاستيك', 'pvc', 'cr80', 'محفظة', 'id', 'رخصة', 'كارنيه', 'طباعة'],
    ),
    ToolItem(
      id: 'gov_lanyard_badge',
      title: 'كارنيهات العمل والشركات',
      subtitle: 'تصميم وطباعة شارات وكارنيهات الموظفين والزوار بمقاس رسمي مع الصورة والباركود',
      category: ToolCategory.government,
      icon: Icons.contact_page_rounded,
      badge: 'كارنيه معتمد',
      accentColor: Color(0xFF0284C7),
      keywords: ['كارنيه', 'شارة', 'موظف', 'زائر', 'lanyard', 'badge', 'طباعة', '1:1', 'فعالية'],
    ),

    // ── Intelligence & Extraction Category ──
    ToolItem(
      id: 'ai_interactive_table',
      title: 'محرر ومستخرج الجداول (إكسل)',
      subtitle: 'تصوير أي جدول أو فاتورة على الورق وتعديل خلاياه وحساب المجاميع وتصديره Excel',
      category: ToolCategory.intelligence,
      icon: Icons.table_view_rounded,
      badge: 'Excel تفاعلي ∑',
      accentColor: Color(0xFF059669),
      keywords: ['جدول', 'جداول', 'محرر', 'تعديل', 'جمع', 'sum', 'excel', 'xlsx', 'درجات', 'فاتورة'],
    ),
    ToolItem(
      id: 'three_d_maker_studio',
      title: 'ماسح المجسمات 3D (STL)',
      subtitle: 'تصوير أي قطعة أو مجسم بالهاتف وتحويلها لملف مجسم 3D صلب (STL) جاهز للطباعة',
      category: ToolCategory.intelligence,
      icon: Icons.view_in_ar_rounded,
      badge: 'مجسم 3D STL',
      accentColor: Color(0xFF00C853),
      keywords: ['3d', 'stl', 'طباعة ثلاثية', 'مجسم', 'سكانر 3d', 'cura', 'slicer', 'فوتوغرامتري', 'طابعة', '3d printer'],
    ),
    ToolItem(
      id: 'ai_excel_converter',
      title: 'تحويل المستندات إلى Excel',
      subtitle: 'استخراج الأرقام والجداول والبيانات الورقية وتحويلها مباشرة لملف إكسل منسق وجاهز',
      category: ToolCategory.intelligence,
      icon: Icons.table_chart_rounded,
      badge: 'ملف XLSX',
      accentColor: Color(0xFF10B981),
      keywords: ['إكسل', 'excel', 'جدول', 'xlsx', 'أرقام', 'حسابات'],
    ),
    ToolItem(
      id: 'ai_smart_extraction',
      title: 'استخراج النصوص والأرقام (OCR)',
      subtitle: 'قراءة الأرقام القومية، وأرقام الهواتف، والبريد من الورقة ونسخها أو حفظها فوراً',
      category: ToolCategory.intelligence,
      icon: Icons.psychology_rounded,
      badge: 'نسخ فوري',
      accentColor: Color(0xFF8B5CF6),
      keywords: ['رقم قومي', 'هاتف', 'اتصال', 'vcard', 'تفريغ', 'صوت', 'tts'],
    ),
    ToolItem(
      id: 'ai_magic_clean',
      title: 'إزالة أصابع اليد وبقع الورق',
      subtitle: 'مسح أصابع اليد الظاهرة في الصورة، وثقوب الدباسة، وبقع القهوة بلمسة ذكية واحدة',
      category: ToolCategory.intelligence,
      icon: Icons.auto_fix_high_rounded,
      badge: 'تنظيف الورق',
      accentColor: Color(0xFFFF2D55),
      keywords: ['ممحاة', 'أصابع', 'ثقوب', 'دباسة', 'بقع', 'تنظيف', 'ورق', 'magic', 'clean'],
    ),
    ToolItem(
      id: 'ai_shadow_remover',
      title: 'إزالة ظلال اليد والهاتف',
      subtitle: 'التخلص التلقائي من ظل الموبايل واليد على الورقة لتصبح الخلفية بيضاء ناصعة ومتساوية',
      category: ToolCategory.intelligence,
      icon: Icons.wb_sunny_rounded,
      badge: 'ورق ناصع',
      accentColor: Color(0xFFFF9500),
      keywords: ['ظل', 'ظلال', 'إضاءة', 'هاتف', 'نور', 'فلاش', 'shadow', 'glare'],
    ),
    ToolItem(
      id: 'ai_book_split',
      title: 'تصوير الكتب صفحتين معاً',
      subtitle: 'تصوير كتاب مفتوح وفصل الصفحتين اليمنى واليسرى تلقائياً لصفحات منفصلة ومستوية',
      category: ToolCategory.intelligence,
      icon: Icons.menu_book_rounded,
      badge: 'فصل الصفحات',
      accentColor: Color(0xFFF59E0B),
      keywords: ['كتاب', 'صفحتين', 'فصل', 'منحنيات', 'مجلد', 'دراسة'],
    ),
    ToolItem(
      id: 'ai_book_curve_flattener',
      title: 'فرد تقوس صفحات الكتب',
      subtitle: 'تعديل انحناء صفحات الكتب والمجلدات السميكة وإزالة سواد كعب الكتاب تلقائياً',
      category: ToolCategory.intelligence,
      icon: Icons.auto_stories_rounded,
      badge: 'فرد التحدب',
      accentColor: Color(0xFFF59E0B),
      keywords: ['كتاب', 'مجلد', 'انحناء', 'تقوس', 'كعب', 'تسوية', 'مسطح', 'dewarp', 'curve', 'book'],
    ),
    ToolItem(
      id: 'ai_notebook_remover',
      title: 'إزالة أسطر الكشكول والدفتر',
      subtitle: 'حذف خطوط التسطير وشبكة المربعات من الكشكول والاحتفاظ بكتابة يدك فقط بخلفية بيضاء',
      category: ToolCategory.intelligence,
      icon: Icons.border_color_rounded,
      badge: 'حفظ خط يدك',
      accentColor: Color(0xFF007AFF),
      keywords: ['كشكول', 'دفتر', 'تسطير', 'خطوط', 'مربعات', 'رسم بياني', 'شبكة', 'notebook', 'grid', 'lines'],
    ),
    ToolItem(
      id: 'ai_object_counter',
      title: 'عدّ المنتجات والبضائع بالصورة',
      subtitle: 'إحصاء الكراتين أو الأنابيب أو البضائع في الصورة تلقائياً وإصدار تقرير جرد PDF',
      category: ToolCategory.intelligence,
      icon: Icons.pin_rounded,
      badge: 'جرد فوري',
      accentColor: Color(0xFFFF9500),
      keywords: ['عد', 'عداد', 'أنابيب', 'كراتين', 'بضائع', 'دواء', 'جرد', 'مخزن', 'counter', 'inventory', 'objects'],
    ),
    ToolItem(
      id: 'ai_doc_diff',
      title: 'مقارنة نسختين من عقد أو ورقة',
      subtitle: 'اكتشاف أي كلمة أو بند تم تعديله أو إضافته بين نسختين من نفس العقد أو الورقة',
      category: ToolCategory.intelligence,
      icon: Icons.splitscreen_rounded,
      badge: 'كشف التعديلات',
      accentColor: Color(0xFF8B5CF6),
      keywords: ['مقارنة', 'فروقات', 'عقود', 'تعديل', 'تزوير', 'diff', 'compare'],
    ),
    ToolItem(
      id: 'ai_anti_moire_glare',
      title: 'تصوير الشاشات والسبورة',
      subtitle: 'إزالة خطوط وتموجات شاشات الكمبيوتر ولمعان فلاش السبورة البيضاء للحصول على صورة نقية',
      category: ToolCategory.intelligence,
      icon: Icons.screenshot_monitor_rounded,
      badge: 'شاشة نقية',
      accentColor: Color(0xFF5856D6),
      keywords: ['شاشة', 'كمبيوتر', 'تلفزيون', 'تموج', 'سبورة', 'لمعان', 'فلاش', 'moire', 'glare', 'whiteboard'],
    ),
    ToolItem(
      id: 'ai_qr_studio',
      title: 'صانع باركود ورمز QR مخصص',
      subtitle: 'إنشاء رمز QR للواي فاي، أو رقم هاتفك، أو موقعك مع إمكانية إضافة شعارك وطباعته',
      category: ToolCategory.intelligence,
      icon: Icons.qr_code_2_rounded,
      badge: 'تصميم QR',
      accentColor: Color(0xFF007AFF),
      keywords: ['qr', 'باركود', 'كود', 'واي فاي', 'wifi', 'vcard', 'كارت', 'رابط', 'url', 'طباعة', 'واتساب', 'barcode'],
    ),
    ToolItem(
      id: 'ai_qr_scanner',
      title: 'قارئ وماسح الباركود و QR',
      subtitle: 'مسح فوري لأي باركود بالكاميرا أو من الصور وفتح الروابط وشبكات الواي فاي مباشرة',
      category: ToolCategory.intelligence,
      icon: Icons.qr_code_scanner_rounded,
      badge: 'مسح فوري',
      accentColor: Color(0xFF34C759),
      keywords: ['qr', 'باركود', 'مسح', 'scanner', 'كاميرا', 'سيرفر', 'barcode', 'كود', 'شاشة'],
    ),

    // ── PDF Tools Category ──
    ToolItem(
      id: 'pdf_merge',
      title: 'تجميع عدة ملفات في ملف واحد',
      subtitle: 'دمج عدة أوراق وملفات PDF منفصلة في ملف واحد مرتب وسهل المشاركة والإرسال',
      category: ToolCategory.pdf,
      icon: Icons.merge_type_rounded,
      badge: 'دمج ملفات',
      accentColor: Color(0xFF2563EB),
      keywords: ['دمج', 'تجميع', 'pdf', 'ملفات', 'ترتيب'],
    ),
    ToolItem(
      id: 'pdf_split',
      title: 'تقسيم واستخراج صفحات PDF',
      subtitle: 'فصل صفحات معينة من كتاب أو مستند كبير وحفظها كملف PDF مستقل بضغطة زر',
      category: ToolCategory.pdf,
      icon: Icons.call_split_rounded,
      badge: 'استخراج صفحات',
      accentColor: Color(0xFF0D9488),
      keywords: ['تقسيم', 'فصل', 'استخراج', 'صفحات', 'pdf'],
    ),
    ToolItem(
      id: 'pdf_target_compress',
      title: 'تقليص حجم ملفات PDF',
      subtitle: 'تصغير حجم الملف إلى 500 ك.ب أو الحجم المطلوب مع الحفاظ على وضوح الخطوط ودقة النصوص',
      category: ToolCategory.pdf,
      icon: Icons.compress_rounded,
      badge: 'تقليل الحجم',
      accentColor: Color(0xFF4F46E5),
      keywords: ['ضغط', 'حجم', 'pdf', 'تقليل', 'كيلوبايت'],
    ),
    ToolItem(
      id: 'pdf_import',
      title: 'استيراد مستندات وصور من الهاتف',
      subtitle: 'جلب ملفات PDF أو صور من ذاكرة هاتفك لحفظها وتعديلها وتحويلها داخل التطبيق',
      category: ToolCategory.pdf,
      icon: Icons.file_download_rounded,
      badge: 'استيراد فوري',
      accentColor: Color(0xFF059669),
      keywords: ['استيراد', 'جلب', 'ملف', 'صورة', 'تنزيل'],
    ),
    ToolItem(
      id: 'transfer_web_drop',
      title: 'إرسال الملفات للكمبيوتر بدون كابل',
      subtitle: 'فتح رابط فوري في متصفح اللابتوب واستلام وإرسال الملفات مباشرة عبر الواي فاي بسرعة',
      category: ToolCategory.pdf,
      icon: Icons.wifi_tethering_rounded,
      badge: 'بدون كابل ⚡',
      accentColor: Color(0xFF007AFF),
      keywords: ['كمبيوتر', 'ماك', 'wifi', 'نقل', 'متصفح', 'airdrop', 'drop', 'شير'],
    ),
    ToolItem(
      id: 'transfer_files_hub',
      title: 'الملفات المستلمة من الكمبيوتر',
      subtitle: 'عرض وإدارة كافة المستندات والملفات التي تم نقلها بين الهاتف والكمبيوتر بسهولة',
      category: ToolCategory.pdf,
      icon: Icons.folder_shared_rounded,
      badge: 'ملفات منقولة',
      accentColor: Color(0xFF0D9488),
      keywords: ['ملفات', 'منقولة', 'مستلمة', 'مرسلة', 'كمبيوتر', 'web drop', 'تنزيلات', 'transferred'],
    ),
    ToolItem(
      id: 'pdf_booklet_imposition',
      title: 'طباعة ملازم وكتيبات مطوية',
      subtitle: 'ترتيب صفحات المذكرات تلقائياً لتطبع وش وضهر وتنثني ككتيب أو مذكرة A5 مرتبة',
      category: ToolCategory.pdf,
      icon: Icons.auto_stories_rounded,
      badge: 'كتيب مطوي',
      accentColor: Color(0xFF7C3AED),
      keywords: ['كتيب', 'ملزمة', 'booklet', 'طي', 'دوبلكس', 'كتاب', 'طباعة'],
    ),
    ToolItem(
      id: 'pdf_gutter_margin',
      title: 'توسيع هامش التجليد والتخريم',
      subtitle: 'إبعاد النصوص عن حافة الورقة حتى لا تتلفها خرامة الأوراق أو سلك التجليد الحلزوني',
      category: ToolCategory.pdf,
      icon: Icons.margin_rounded,
      badge: 'حماية التجليد',
      accentColor: Color(0xFFEA580C),
      keywords: ['هامش', 'تجليد', 'خرامة', 'ثقوب', 'سلك', 'حلزوني', 'gutter', 'تخريم'],
    ),

    // ── Security, Privacy & Maintenance Category ──
    ToolItem(
      id: 'legal_audit_studio',
      title: 'مراجعة وتدقيق العقود والشيكات',
      subtitle: 'كشف الصفحات المفقودة في العقود، كتابة المبالغ بالحروف، وترقيم أوراق القضايا',
      category: ToolCategory.security,
      icon: Icons.gavel_rounded,
      badge: 'تدقيق قانوني',
      accentColor: Color(0xFFB45309),
      keywords: ['شيك', 'تفقيط', 'أرقام', 'عقد', 'صفحة مفقودة', 'bates', 'قضية', 'محكمة', 'تدقيق'],
    ),
    ToolItem(
      id: 'sec_vault',
      title: 'الخزنة السرية المقفولة بالبصمة',
      subtitle: 'مساحة خاصة مشفرة لحفظ أوراقك ومستنداتك الحساسة لا تفتح إلا ببصمة إصبعك أو رمزك السري',
      category: ToolCategory.security,
      icon: Icons.enhanced_encryption_rounded,
      badge: 'حماية بالبصمة',
      accentColor: Color(0xFF059669),
      keywords: ['خزنة', 'قفل', 'بصمة', 'تشفير', 'سري', 'pin', 'حماية'],
    ),
    ToolItem(
      id: 'sec_exif_scrub',
      title: 'حذف موقع وتاريخ التقاط الصور',
      subtitle: 'مسح بيانات الـ GPS ومعلومات الهاتف من صور المستندات قبل إرسالها لحماية خصوصيتك',
      category: ToolCategory.security,
      icon: Icons.location_off_rounded,
      badge: 'حماية الخصوصية',
      accentColor: Color(0xFFE11D48),
      keywords: ['موقع', 'gps', 'exif', 'خصوصية', 'تنظيف', 'حذف'],
    ),
    ToolItem(
      id: 'sec_signatures',
      title: 'توقيع العقود وإضافة ختمك',
      subtitle: 'ارسم توقيعك بيدك وضعه على أي عقد أو مستند مع إمكانية حفظه لإعادة استخدامه فوراً',
      category: ToolCategory.security,
      icon: Icons.draw_rounded,
      badge: 'توقيع يدوي',
      accentColor: Color(0xFF6366F1),
      keywords: ['توقيع', 'ختم', 'عقد', 'توقيعات', 'بصمة'],
    ),
    ToolItem(
      id: 'sec_trash',
      title: 'سلة المحذوفات واسترجاع الأوراق',
      subtitle: 'استعادة أي مستند قمت بحذفه بالخطأ خلال 30 يوماً قبل حذفه النهائي من الهاتف',
      category: ToolCategory.security,
      icon: Icons.delete_sweep_rounded,
      badge: 'استرجاع 30 يوم',
      accentColor: Color(0xFFDC2626),
      keywords: ['سلة', 'حذف', 'محذوفات', 'استرجاع', 'مهملات'],
    ),
    ToolItem(
      id: 'sec_watermark',
      title: 'إضافة علامة مائية لحماية الورق',
      subtitle: 'كتابة اسمك أو عبارة "سري / معتمد" مائلة فوق الورقة لحمايتها من السرقة والتزوير',
      category: ToolCategory.security,
      icon: Icons.verified_user_rounded,
      badge: 'منع التزوير',
      accentColor: Color(0xFFDC2626),
      keywords: ['علامة', 'مائية', 'ختم', 'أمان', 'بنك', 'بطاقة', 'تزوير', 'watermark'],
    ),
    ToolItem(
      id: 'sec_smart_redaction',
      title: 'طمس وحجب البيانات الحساسة',
      subtitle: 'تسويد نهائي لأرقام الحسابات والبيانات السرية بمستطيل أسود لا يمكن إزالته أو كشفه',
      category: ToolCategory.security,
      icon: Icons.visibility_off_rounded,
      badge: 'تسويد نهائي',
      accentColor: Color(0xFF334155),
      keywords: ['حجب', 'تسويد', 'رقم قومي', 'خصوصية', 'redact', 'تشفير'],
    ),
    ToolItem(
      id: 'sec_backup_zip',
      title: 'نسخ احتياطي على جوجل درايف',
      subtitle: 'حفظ نسخة سحابية مشفرة من كافة مستنداتك على حسابك السحابي حتى لا تفقدها أبداً',
      category: ToolCategory.security,
      icon: Icons.cloud_sync_rounded,
      badge: 'حفظ سحابي',
      accentColor: Color(0xFF007AFF),
      keywords: ['نسخ', 'احتياطي', 'استعادة', 'سحابي', 'drive', 'icloud', 'zero-knowledge', 'تشفير', 'google', 'apple', 'أرشيف', 'تصدير'],
    ),
    ToolItem(
      id: 'sec_digital_stamp',
      title: 'استخراج وتفريغ الختم الرسمي',
      subtitle: 'قص الختم الرسمي وتفريغ حبره بخلفية شفافة تماماً لوضعه على أي مستند أو ورقة رسمية',
      category: ToolCategory.security,
      icon: Icons.verified_rounded,
      badge: 'ختم مفرغ شفاف',
      accentColor: Color(0xFFD62B2B),
      keywords: ['ختم', 'أختام', 'توقيع', 'رسمي', 'معتمد', 'مدفوع', 'شفافية'],
    ),
    ToolItem(
      id: 'sec_pdf_lock',
      title: 'قفل ملف PDF بكلمة سر',
      subtitle: 'تشفير المستند بكلمة مرور قوية (AES) لمنع أي شخص من فتحه أو طباعته بدون إذنك',
      category: ToolCategory.security,
      icon: Icons.lock_rounded,
      badge: 'تشفير قوي',
      accentColor: Color(0xFF059669),
      keywords: ['قفل', 'تشفير', 'كلمة سر', 'باسورد', 'بصمة', 'aes', 'حماية', 'pdf'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isGrid = prefs.getBool('tools_hub_grid_view');
      if (isGrid != null && mounted) {
        setState(() => _isGridView = isGrid);
      }
    } catch (_) {}
  }

  Future<void> _setViewMode(bool isGrid) async {
    setState(() => _isGridView = isGrid);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tools_hub_grid_view', isGrid);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ToolItem> get _filteredTools {
    return _allTools.where((tool) {
      final matchesCategory = _selectedCategory == ToolCategory.all ||
          tool.category == _selectedCategory;
      if (!matchesCategory) return false;

      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;

      final inTitle = tool.title.toLowerCase().contains(query);
      final inSub = tool.subtitle.toLowerCase().contains(query);
      final inKeywords =
          tool.keywords.any((k) => k.toLowerCase().contains(query));
      return inTitle || inSub || inKeywords;
    }).toList();
  }

  void _onToolSelected(ToolItem tool) {
    switch (tool.id) {
      case 'three_d_maker_studio':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ThreeDMakerStudioScreen(),
          ),
        );
        break;

      case 'gov_id_card':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const IdCardA4Screen(),
          ),
        );
        break;

      case 'gov_passport_cert':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GovernmentDocumentsScreen(
              initialMode: OfficialDocMode.passport,
            ),
          ),
        );
        break;

      case 'gov_photo_grid':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GovernmentDocumentsScreen(
              initialMode: OfficialDocMode.photos,
            ),
          ),
        );
        break;

      case 'gov_portal_compress':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GovernmentDocumentsScreen(
              initialMode: OfficialDocMode.compress,
            ),
          ),
        );
        break;

      case 'gov_lanyard_badge':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LanyardIdBadgeScreen(),
          ),
        );
        break;

      case 'ai_interactive_table':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const InteractiveTableEditorScreen(),
          ),
        );
        break;

      case 'pdf_booklet_imposition':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const BookletAndBindingScreen(initialTabIndex: 0),
          ),
        );
        break;

      case 'pdf_gutter_margin':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const BookletAndBindingScreen(initialTabIndex: 1),
          ),
        );
        break;

      case 'legal_audit_studio':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LegalAuditStudioScreen(),
          ),
        );
        break;

      case 'ai_excel_converter':
        _showExcelActionDialog();
        break;

      case 'ai_smart_extraction':
        _showSmartExtractionLauncher();
        break;

      case 'ai_book_split':
        _showBookSplitterDialog();
        break;

      case 'pdf_merge':
      case 'pdf_split':
      case 'pdf_target_compress':
      case 'pdf_import':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PdfToolsScreen(),
          ),
        );
        break;

      case 'sec_vault':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const VaultScreen(),
          ),
        );
        break;

      case 'sec_exif_scrub':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PrivacyScrubberScreen(),
          ),
        );
        break;

      case 'sec_signatures':
        _openSignaturesSheet();
        break;

      case 'sec_watermark':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WatermarkStudioScreen(),
          ),
        );
        break;

      case 'sec_smart_redaction':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AutoRedactionScreen(),
          ),
        );
        break;

      case 'sec_trash':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TrashScreen(),
          ),
        );
        break;

      case 'sec_backup_zip':
        CloudBackupSheet.show(context);
        break;

      case 'ai_magic_clean':
        _showMagicCleanLauncher();
        break;

      case 'ai_doc_diff':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DocumentDiffScreen(),
          ),
        );
        break;

      case 'transfer_web_drop':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WebDropScreen(),
          ),
        );
        break;

      case 'sec_digital_stamp':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const StampStudioScreen(),
          ),
        );
        break;

      case 'sec_pdf_lock':
        _showPdfSecurityLauncher();
        break;

      case 'gov_smart_contracts':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SmartContractStudioScreen(),
          ),
        );
        break;

      case 'ai_shadow_remover':
        _showShadowRemoverLauncher();
        break;

      case 'gov_smart_id_wallet':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SmartIdWalletScreen(),
          ),
        );
        break;

      case 'ai_book_curve_flattener':
        _showBookCurveLauncher();
        break;

      case 'transfer_files_hub':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransferredFilesScreen(),
          ),
        );
        break;

      case 'ai_notebook_remover':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const NotebookLinesRemoverScreen(),
          ),
        );
        break;

      case 'ai_object_counter':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ObjectCounterScreen(),
          ),
        );
        break;

      case 'ai_anti_moire_glare':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AntiMoireWhiteboardScreen(),
          ),
        );
        break;

      case 'ai_qr_studio':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const QrStudioScreen(),
          ),
        );
        break;

      case 'ai_qr_scanner':
        _launchQrScannerTool();
        break;
    }
  }

  Future<void> _launchQrScannerTool() async {
    HapticFeedback.mediumImpact();
    final source = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: Color(0xFF34C759), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ماسح رموز QR والباركود الذكي',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('اختر طريقة المسح والقراءة الفورية',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Color(0xFF34C759)),
                ),
                title: const Text('فتح الكاميرا للمسح فوراً',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: const Text('توجيه الكاميرا إلى أي كود لمسحه بدقة وسرعة',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5856D6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Color(0xFF5856D6)),
                ),
                title: const Text('اختيار صورة من المعرض',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: const Text('قراءة رمز من لقطة شاشة أو صورة محفوظة',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    String? targetPath;
    if (source == 'camera') {
      try {
        final tmpDir = await getTemporaryDirectory();
        final res = await NativeScannerBridge.startSingleScan(
          destDir: tmpDir.path,
        );
        if (res == null || !mounted) return;
        targetPath = res.path;
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) await showScannerPermissionDialog(context, e);
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
        return;
      }
    } else if (source == 'gallery') {
      try {
        final res = await FilePicker.platform.pickFiles(type: FileType.image);
        if (res == null ||
            res.files.isEmpty ||
            res.files.first.path == null ||
            !mounted) {
          return;
        }
        targetPath = res.files.first.path!;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر اختيار الصورة: $e')),
          );
        }
        return;
      }
    }

    if (targetPath == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(width: 16),
                Text('جارٍ فحص الرمز...',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ],
            ),
          ),
        ),
      ),
    );

    final payload = await QrScannerService.instance.scanImage(targetPath);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (payload == null || payload.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child:
                      Text('لم يتم العثور على رمز QR أو باركود واضح في الصورة.'),
                ),
              ],
            ),
            backgroundColor: Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    await QrScannerService.instance.handleScannedPayload(
      context: context,
      payload: payload,
    );
  }

  // ── Action Handlers ──

  Future<void> _showBookCurveLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];

    final choice = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'تسوية انحناء الكتب: اختر صفحة لمعالجتها',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF007AFF)),
                title: const Text('تصوير صفحة كتاب بالكاميرا'),
                subtitle: const Text('التقاط فوري لصفحة منحنية وضبط حوافها'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFFF59E0B)),
                title: const Text('اختيار صورة من معرض الصور'),
                onTap: () => Navigator.pop(ctx, 'pick_external'),
              ),
              if (docs.isNotEmpty) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'أو اختر من مستنداتك الممسوحة مسبقاً:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (c, idx) {
                      final d = docs[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.auto_stories_rounded),
                        title: Text(d.fileName, maxLines: 1),
                        subtitle: Text('${d.pageCount} صفحة'),
                        onTap: () => Navigator.pop(ctx, d.id),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'camera') {
      try {
        final draftsDir = await ref.read(localDocumentStoreProvider).getDraftsDirectory();
        final results = await NativeScannerBridge.startScan(
          destDir: draftsDir.path,
          batch: false,
        );
        if (results.isNotEmpty && mounted) {
          final res = results.first;
          final processedPath = await openScanReviewScreen(
            context,
            rawImagePath: res.path,
            initialCorners: res.corners,
            imageWidth: res.width,
            imageHeight: res.height,
          );
          if (processedPath != null && File(processedPath).existsSync() && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookCurveFlattenerScreen(imagePath: processedPath),
              ),
            );
          }
        }
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) {
          await showScannerPermissionDialog(context, e);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
          );
        }
      }
    } else if (choice == 'pick_external') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        final rawPath = res.files.single.path!;
        final processedPath = await openScanReviewScreen(
          context,
          rawImagePath: rawPath,
        );
        if (processedPath != null && File(processedPath).existsSync() && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookCurveFlattenerScreen(imagePath: processedPath),
            ),
          );
        }
      }
    } else {
      final doc = docs.firstWhere((d) => d.id == choice);
      if (doc.pages.isNotEmpty && mounted) {
        final path = doc.pages.first.imagePath;
        if (File(path).existsSync()) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookCurveFlattenerScreen(imagePath: path),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ملف الصفحة غير موجود على الجهاز')),
          );
        }
      }
    }
  }

  Future<void> _showMagicCleanLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];
    if (docs.isEmpty) {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(imagePath: res.files.single.path!),
          ),
        );
      }
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'الممحاة الذكية: اختر المستند لتنظيفه',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFFFF2D55)),
                title: const Text('اختيار صورة من معرض الصور'),
                onTap: () => Navigator.pop(ctx, 'pick_external'),
              ),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, idx) {
                    final d = docs[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_rounded),
                      title: Text(d.fileName, maxLines: 1),
                      subtitle: Text('${d.pageCount} صفحة'),
                      onTap: () => Navigator.pop(ctx, d.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'pick_external') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(imagePath: res.files.single.path!),
          ),
        );
      }
    } else {
      final doc = docs.firstWhere((d) => d.id == choice);
      if (doc.pages.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(imagePath: doc.pages.first.imagePath),
          ),
        );
      }
    }
  }

  Future<void> _showShadowRemoverLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];
    if (docs.isEmpty) {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(
              imagePath: res.files.single.path!,
              autoRemoveShadow: true,
            ),
          ),
        );
      }
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'إزالة ظل الهاتف: اختر مستند لتسوية إضاءته',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFFFF9500)),
                title: const Text('اختيار صورة من معرض الصور'),
                onTap: () => Navigator.pop(ctx, 'pick_external'),
              ),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, idx) {
                    final d = docs[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFF9500)),
                      title: Text(d.fileName, maxLines: 1),
                      subtitle: Text('${d.pageCount} صفحة'),
                      onTap: () => Navigator.pop(ctx, d.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'pick_external') {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res != null && res.files.single.path != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(
              imagePath: res.files.single.path!,
              autoRemoveShadow: true,
            ),
          ),
        );
      }
    } else {
      final doc = docs.firstWhere((d) => d.id == choice);
      if (doc.pages.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MagicCleanScreen(
              imagePath: doc.pages.first.imagePath,
              autoRemoveShadow: true,
            ),
          ),
        );
      }
    }
  }

  Future<void> _showPdfSecurityLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات محفوظة لقفلها في المكتبة')),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'اختر المستند لتشفيره وقفله بكلمة سر',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const Divider(),
            SizedBox(
              height: 240,
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (c, idx) {
                  final d = docs[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.enhanced_encryption_rounded, color: Color(0xFF059669)),
                    title: Text(d.fileName, maxLines: 1),
                    subtitle: Text('${d.pageCount} صفحة • ${(d.fileSize / 1024).toStringAsFixed(1)} KB'),
                    onTap: () => Navigator.pop(ctx, d.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedId == null || !mounted) return;
    final doc = docs.firstWhere((d) => d.id == selectedId);

    final securityResult = await showModalBottomSheet<PdfSecurityOptions>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PdfSecuritySheet(document: doc),
    );

    if (securityResult != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔒 تم قفل وتأمين مستند "${doc.fileName}" بنجاح'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openSignaturesSheet() async {
    final storage = ref.read(signatureStorageServiceProvider);
    await showSignatureBottomSheet(
      context: context,
      storageService: storage,
    );
  }

  Future<void> _processImageToExcel(String imagePath, String title) async {
    final now = DateTime.now();
    final tempDoc = PendingUpload(
      id: 'excel_temp_${now.millisecondsSinceEpoch}',
      filePath: imagePath,
      fileName: '$title.jpg',
      fileType: 'image',
      createdAt: now,
      pageCount: 1,
      thumbnailPath: imagePath,
      pages: [
        ScannedPage(
          imagePath: imagePath,
          originalImagePath: imagePath,
          filterName: 'original',
          paperSize: DocumentPaperSize.a4,
        ),
      ],
    );

    await executeDocumentExportWithUi(
      context: context,
      ref: ref,
      document: tempDoc,
      format: ExportFormat.xlsx,
    );
  }

  Future<void> _showExcelActionDialog() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];

    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.table_chart_rounded,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تحويل الجداول إلى Excel احترافي',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'استخراج الجداول بصيغة .xlsx مع شبكة خلايا ودعم RTL',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                ),
                title: const Text('تصوير جدول جديد بالكاميرا الآن',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('التقاط فوري لجدول مطبوع وتحويله لإكسل'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    final draftsDir = await ref.read(localDocumentStoreProvider).getDraftsDirectory();
                    final scanResults = await NativeScannerBridge.startScan(
                      destDir: draftsDir.path,
                      batch: false,
                    );
                    if (scanResults.isNotEmpty && mounted) {
                      final res = scanResults.first;
                      final enhancedPath = await openScanReviewScreen(
                        context,
                        rawImagePath: res.path,
                        initialCorners: res.corners,
                        imageWidth: res.width,
                        imageHeight: res.height,
                        initialFilter: 'bw',
                      );
                      if (enhancedPath != null) {
                        await _processImageToExcel(enhancedPath, 'جدول_ممسوح');
                      }
                    }
                  } on ScannerPermissionDeniedException catch (e) {
                    if (mounted) {
                      await showScannerPermissionDialog(context, e);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
                      );
                    }
                  }
                },
              ),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.purple),
                ),
                title: const Text('اختيار صورة جدول من المعرض أو الجهاز',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('اختيار ملف صورة JPG أو PNG يحتوي على جدول'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
                    await _processImageToExcel(
                      result.files.first.path!,
                      stripFileExtension(result.files.first.name),
                    );
                  }
                },
              ),

              if (docs.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'أو اختر من مستندات المكتبة:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (_, idx) {
                      final d = docs[idx];
                      return ListTile(
                        leading: const Icon(
                          Icons.description_rounded,
                          color: Color(0xFF10B981),
                        ),
                        title: Text(
                          d.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${formatPageCount(d.pageCount)} • ${formatDate(d.createdAt)}',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();
                          await executeDocumentExportWithUi(
                            context: context,
                            ref: ref,
                            document: d,
                            format: ExportFormat.xlsx,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _extractFromImagePath(String imagePath, String title) async {
    setState(() => _isProcessing = true);
    try {
      final ocr = ref.read(ocrServiceProvider);
      final res = await ocr.recognizeDocument(
        documentId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        imagePaths: [imagePath],
      );
      if (!mounted) return;
      setState(() => _isProcessing = false);

      SmartDataExtractionSheet.show(
        context: context,
        text: res.fullText.isNotEmpty
            ? res.fullText
            : 'لم يتم العثور على نصوص واضحة في الصورة.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الاستخراج: $e')),
        );
      }
    }
  }

  Future<void> _showManualTextExtractionDialog() async {
    final textCtrl = TextEditingController(
      text: 'بطاقة رقم قومي: 29805120102345\nرقم الهاتف: 01098765432\nالمبلغ المطلوب: 3500 جنيه مصري',
    );
    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text(
          'تجربة الاستخراج الذكي (OCR)',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل أو الصق نصاً يحتوي على رقم قومي أو هاتف لاختبار التحليل الذكي محلياً:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final txt = textCtrl.text.trim();
              Navigator.pop(dlgCtx);
              if (txt.isNotEmpty) {
                SmartDataExtractionSheet.show(
                  context: context,
                  text: txt,
                );
              }
            },
            child: const Text('تحليل النص'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSmartExtractionLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];

    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الاستخراج الذكي وتحليل المستندات',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'تفكيك بيانات الرقم القومي، الهواتف، vCard، والقراءة الصوتية',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                ),
                title: const Text('تصوير بطاقة أو وثيقة بالكاميرا',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('التقاط صورة وتحليل حقولها فوراً'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    final draftsDir = await ref.read(localDocumentStoreProvider).getDraftsDirectory();
                    final scanResults = await NativeScannerBridge.startScan(
                      destDir: draftsDir.path,
                      batch: false,
                    );
                    if (scanResults.isNotEmpty && mounted) {
                      final res = scanResults.first;
                      final enhancedPath = await openScanReviewScreen(
                        context,
                        rawImagePath: res.path,
                        initialCorners: res.corners,
                        imageWidth: res.width,
                        imageHeight: res.height,
                      );
                      if (enhancedPath != null) {
                        await _extractFromImagePath(enhancedPath, 'وثيقة_ممسوحة');
                      }
                    }
                  } on ScannerPermissionDeniedException catch (e) {
                    if (mounted) {
                      await showScannerPermissionDialog(context, e);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر تشغيل الكاميرا: $e')),
                      );
                    }
                  }
                },
              ),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.purple),
                ),
                title: const Text('اختيار صورة من المعرض أو الجهاز',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('فحص صورة بطاقة أو فاتورة محفوظة'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
                    await _extractFromImagePath(
                      result.files.first.path!,
                      stripFileExtension(result.files.first.name),
                    );
                  }
                },
              ),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.text_fields_rounded, color: Colors.teal),
                ),
                title: const Text('كتابة أو لصق نص يدوي للتحليل',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('فحص فوري لأي رقم قومي أو هاتف نصياً'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showManualTextExtractionDialog();
                },
              ),

              if (docs.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'أو اختر من مستندات المكتبة:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (_, idx) {
                      final d = docs[idx];
                      return ListTile(
                        leading: const Icon(
                          Icons.psychology_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                        title: Text(
                          d.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${formatPageCount(d.pageCount)} صفحة'),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();
                          _extractFromDocument(d);
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  }

  Future<void> _extractFromDocument(PendingUpload doc) async {
    setState(() => _isProcessing = true);
    try {
      final searchSvc = ref.read(documentSearchServiceProvider);
      var text = (await searchSvc.getIndexedOcrText(doc.id)) ?? '';

      if (text.isEmpty && doc.pages.isNotEmpty) {
        final imgPath = doc.pages.first.imagePath;
        if (File(imgPath).existsSync()) {
          final ocr = ref.read(ocrServiceProvider);
          final res = await ocr.recognizeDocument(
            documentId: doc.id,
            imagePaths: [imgPath],
          );
          text = res.fullText;
        }
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);

      SmartDataExtractionSheet.show(
        context: context,
        text: text.isNotEmpty
            ? text
            : 'مستند: ${doc.title}\nلا توجد نصوص مكتشفة حالياً، يمكنك فحص مستند آخر.',
        document: doc,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الاستخراج: $e')),
        );
      }
    }
  }

  Future<void> _showBookSplitterDialog() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'مسح وفصل صفحات الكتب المزدوجة (Book Mode)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'التقط صورة لصفحتين متقابلتين في لقطة واحدة وسيقوم التطبيق بفصلهما وتسوية انحناءات الورق.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.amber),
                  ),
                  title: const Text('تصوير كتاب مفتوح بالكاميرا الآن',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: Colors.blue),
                  ),
                  title: const Text('اختيار صورة كتاب من الجهاز',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (source == null) return;

    String? path;
    if (source == 'camera') {
      try {
        final draftsDir = await ref.read(localDocumentStoreProvider).getDraftsDirectory();
        final scanResults = await NativeScannerBridge.startScan(
          destDir: draftsDir.path,
          batch: false,
        );
        if (scanResults.isNotEmpty && mounted) {
          final res = scanResults.first;
          path = await openScanReviewScreen(
            context,
            rawImagePath: res.path,
            initialCorners: res.corners,
            imageWidth: res.width,
            imageHeight: res.height,
          );
        }
      } on ScannerPermissionDeniedException catch (e) {
        if (mounted) {
          await showScannerPermissionDialog(context, e);
        }
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')),
          );
        }
        return;
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.firstOrNull?.path != null && mounted) {
        path = await openScanReviewScreen(
          context,
          rawImagePath: result.files.firstOrNull!.path!,
        );
      }
    }

    if (path == null) return;

    setState(() => _isProcessing = true);
    try {
      const storage = LocalMediaStorageService();
      final pagesDir = await storage.pagesDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final outRight = p.join(pagesDir.path, 'book_${now}_right.jpg');
      final outLeft = p.join(pagesDir.path, 'book_${now}_left.jpg');

      final splitRes = await NativeScannerBridge.splitBookPage(
        path: path,
        outRightPath: outRight,
        outLeftPath: outLeft,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (splitRes != null &&
          File(splitRes.pageRight).existsSync() &&
          File(splitRes.pageLeft).existsSync()) {
        await _showBookSplitResultDialog(splitRes.pageRight, splitRes.pageLeft);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فصل الكتاب. تأكد من وضوح الصورة وتوسط منحنى الكتاب.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
    }
  }

  Future<void> _showBookSplitResultDialog(String rightPath, String leftPath) async {
    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text(
          'تم فصل صفحتين الكتاب وتسوية الانحناءات',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'الصفحة اليمنى (1)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(rightPath),
                          cacheWidth: 400,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'الصفحة اليسرى (2)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(leftPath),
                          cacheWidth: 400,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.library_add_rounded, size: 18),
            label: const Text('حفظ كمستند في المكتبة'),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              await _saveSplitBookPagesToLibrary(rightPath, leftPath);
            },
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة الصفحتين'),
            onPressed: () {
              Navigator.pop(dlgCtx);
              Share.shareXFiles([XFile(rightPath), XFile(leftPath)]);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveSplitBookPagesToLibrary(String rightPath, String leftPath) async {
    setState(() => _isProcessing = true);
    try {
      const storage = LocalMediaStorageService();
      final docsDir = await storage.documentsDirectory();
      final pdfBuilder = ref.read(pdfBuilderServiceProvider);
      final now = DateTime.now();
      final docId = 'book_${now.millisecondsSinceEpoch}';
      final title = 'كتاب_مفصول_${now.millisecondsSinceEpoch % 10000}';

      final pages = [
        ScannedPage(
          imagePath: rightPath,
          originalImagePath: rightPath,
          filterName: 'original',
          paperSize: DocumentPaperSize.a4,
        ),
        ScannedPage(
          imagePath: leftPath,
          originalImagePath: leftPath,
          filterName: 'original',
          paperSize: DocumentPaperSize.a4,
        ),
      ];

      final pdfBytes = await pdfBuilder.buildPdf(
        imagePaths: [rightPath, leftPath],
        paperSizes: [DocumentPaperSize.a4, DocumentPaperSize.a4],
      );
      final outPath = p.join(docsDir.path, '${docId}_$title.pdf');
      await File(outPath).writeAsBytes(pdfBytes, flush: true);

      final doc = PendingUpload(
        id: docId,
        filePath: outPath,
        fileName: '$title.pdf',
        fileType: 'pdf',
        createdAt: now,
        status: 'saved',
        pageCount: 2,
        thumbnailPath: rightPath,
        pages: pages,
      );

      await ref.read(pendingUploadsControllerProvider.notifier).addDocument(doc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الصفحتين كمستند "$title" في المكتبة بنجاح!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── UI Build ──

  @override
  // ── UI Build (Apple Minimalist / Bento Paper Design) ──

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tools = _filteredTools;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final isWideTablet = screenWidth > 900;
    final isSmallPhone = screenWidth < 360;

    final int crossAxisCount = isWideTablet ? 4 : (isTablet ? 3 : 2);
    final double childAspectRatio = isWideTablet
        ? 1.35
        : (isTablet
            ? 1.18
            : (isSmallPhone ? 0.83 : 0.87));

    final isDefaultGroupedView =
        _selectedCategory == ToolCategory.all && _searchQuery.trim().isEmpty;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'مركز الأدوات',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 21,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              '${_allTools.length} أداة ذكية • معالجة وطباعة وحماية فورية',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              ),
            ),
          ],
        ),
        actions: [
          // Cupertino Segmented View Switcher (Grid / List)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: Container(
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E)
                    : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildViewSegmentItem(
                    icon: Icons.grid_view_rounded,
                    isSelected: _isGridView,
                    tooltip: 'عرض بينتو شبكي',
                    onTap: () => _setViewMode(true),
                    isDark: isDark,
                    palette: palette,
                  ),
                  _buildViewSegmentItem(
                    icon: Icons.view_agenda_rounded,
                    isSelected: !_isGridView,
                    tooltip: 'عرض ورقي مجمع',
                    onTap: () => _setViewMode(false),
                    isDark: isDark,
                    palette: palette,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Apple Inset Search Bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن أداة (بطاقة، إكسل، ضغط، بصمة...)...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? const Color(0xFF8E8E93)
                              : const Color(0xFF8E8E93),
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF8E8E93),
                          size: 19,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.cancel_rounded,
                                  color: Color(0xFF8E8E93),
                                  size: 18,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1C1C1E)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                            width: 0.6,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                            width: 0.6,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide(
                            color: palette.accent,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Apple Category Filter Segmented Pills ──
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: ToolCategory.values.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      final count = cat == ToolCategory.all
                          ? _allTools.length
                          : _allTools.where((t) => t.category == cat).length;

                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = cat);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? palette.accent
                                    : (isDark
                                        ? const Color(0xFF1C1C1E)
                                        : Colors.white),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? palette.accent
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(alpha: 0.06)),
                                  width: 0.6,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: palette.accent
                                              .withValues(alpha: 0.28),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                              alpha: isDark ? 0.2 : 0.025),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    cat.icon,
                                    size: 15,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? const Color(0xFF8E8E93)
                                            : const Color(0xFF636366)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat.label,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      fontSize: 12,
                                      color: isSelected
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white
                                              : const Color(0xFF1C1C1E)),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.22)
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : Colors.black.withValues(alpha: 0.05)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Tool Items Content
              if (tools.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1C1C1E)
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                              ),
                            ),
                            child: const Icon(
                              Icons.search_off_rounded,
                              size: 44,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد أداة مطابقة لبحثك',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'جرب كلمات أخرى مثل: بطاقة، إكسل، ضغط، بصمة، توقيع',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF8E8E93)
                                  : const Color(0xFF6C6C70),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedCategory = ToolCategory.all;
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text(
                              'عرض كافة الأدوات',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isDefaultGroupedView)
                // Default View: Bento Hero Card + Bento Quick Action Spotlight + Inset Categorized Groups
                ...[
                  // 1. Flagship Apple Bento Hero Card
                  SliverToBoxAdapter(
                    child: _buildAppleBentoHeroCard(
                      heroTool: _allTools.firstWhere(
                        (t) => t.id == 'gov_id_card',
                        orElse: () => _allTools.first,
                      ),
                      isDark: isDark,
                      palette: palette,
                      screenWidth: screenWidth,
                    ),
                  ),

                  // 2. Bento Asymmetric Spotlight Dual Cards
                  SliverToBoxAdapter(
                    child: _buildBentoSpotlightRow(
                      isDark: isDark,
                      palette: palette,
                      screenWidth: screenWidth,
                    ),
                  ),

                  // 3. Inset Grouped Categories
                  for (final cat in [
                    ToolCategory.government,
                    ToolCategory.intelligence,
                    ToolCategory.pdf,
                    ToolCategory.security,
                  ]) ...[
                    () {
                      final categoryTools = _allTools
                          .where((t) => t.category == cat)
                          .toList();
                      if (categoryTools.isEmpty) {
                        return const SliverToBoxAdapter(
                            child: SizedBox.shrink());
                      }

                      return SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              category: cat,
                              count: categoryTools.length,
                              isDark: isDark,
                              palette: palette,
                            ),
                          ),
                          if (_isGridView)
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    return _buildGridCard(
                                      context: context,
                                      tool: categoryTools[index],
                                      isDark: isDark,
                                      palette: palette,
                                    );
                                  },
                                  childCount: categoryTools.length,
                                ),
                              ),
                            )
                          else
                            SliverToBoxAdapter(
                              child: _buildInsetGroupedCategoryList(
                                context: context,
                                tools: categoryTools,
                                isDark: isDark,
                                palette: palette,
                              ),
                            ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 18),
                          ),
                        ],
                      );
                    }(),
                  ],
                ]
              else
                // Filtered or Search Mode: Flat list/grid with Header
                ...[
                  SliverToBoxAdapter(
                    child: _buildFilteredHeader(
                      toolsCount: tools.length,
                      isDark: isDark,
                      palette: palette,
                    ),
                  ),
                  if (_isGridView)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: childAspectRatio,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildGridCard(
                              context: context,
                              tool: tools[index],
                              isDark: isDark,
                              palette: palette,
                            );
                          },
                          childCount: tools.length,
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: _buildInsetGroupedCategoryList(
                        context: context,
                        tools: tools,
                        isDark: isDark,
                        palette: palette,
                      ),
                    ),
                ],

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'جارٍ معالجة الأداة محلياً 100%...',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppleBottomNavBar(currentIndex: 1),
    );
  }

  // ── Helper Widgets ──

  Widget _buildViewSegmentItem({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: MotionTokens.chipSelection,
          curve: MotionTokens.easeOutStrong,
          width: 32,
          height: 28,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected
                ? palette.accent
                : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
          ),
        ),
      ),
    );
  }

  // ── Apple Bento Hero Card ──

  Widget _buildAppleBentoHeroCard({
    required ToolItem heroTool,
    required bool isDark,
    required AppThemePalette palette,
    required double screenWidth,
  }) {
    final isSmallPhone = screenWidth < 360;
    final isTablet = screenWidth > 600;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _onToolSelected(heroTool);
          },
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: EdgeInsets.all(isSmallPhone ? 14 : (isTablet ? 20 : 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Eyebrow & Status Row
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 12.5,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'الأداة الأكثر طلباً ✦ طباعة فورية',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34C759),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'دقة 100% بحجم 1:1',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF98989D)
                                  : const Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Headline & Squircle Icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            heroTool.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallPhone ? 15 : (isTablet ? 18 : 16.5),
                              letterSpacing: -0.3,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            heroTool.subtitle,
                            style: TextStyle(
                              fontSize: isSmallPhone ? 11 : 12,
                              color: isDark
                                  ? const Color(0xFFA1A1A6)
                                  : const Color(0xFF636366),
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Paper Squircle Icon
                    Container(
                      width: isSmallPhone ? 46 : (isTablet ? 54 : 48),
                      height: isSmallPhone ? 46 : (isTablet ? 54 : 48),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent,
                            palette.accent.withValues(alpha: 0.82),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          heroTool.icon,
                          color: Colors.white,
                          size: isSmallPhone ? 24 : (isTablet ? 28 : 26),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Bento Feature Pills
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildBentoMiniPill(
                      icon: Icons.straighten_rounded,
                      label: 'مقياس 1:1 حقيقي',
                      isDark: isDark,
                    ),
                    _buildBentoMiniPill(
                      icon: Icons.description_rounded,
                      label: 'ورقة A4 رسمية',
                      isDark: isDark,
                    ),
                    _buildBentoMiniPill(
                      icon: Icons.security_rounded,
                      label: 'حماية وعلامة مائية',
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. Bottom Action Row
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallPhone ? 12 : 15,
                        vertical: 8.5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ابدأ تصوير البطاقة الآن',
                              style: TextStyle(
                                fontSize: isSmallPhone ? 11.5 : 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      'جاهز للطباعة والجهات الرسمية ⚡',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFA1A1A6)
                            : const Color(0xFF636366),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bento Spotlight Dual Row (Fast Quick Tools) ──

  Widget _buildBentoSpotlightRow({
    required bool isDark,
    required AppThemePalette palette,
    required double screenWidth,
  }) {
    final toolExcel = _allTools.firstWhere(
      (t) => t.id == 'ai_interactive_table',
      orElse: () => _allTools.first,
    );
    final toolWebDrop = _allTools.firstWhere(
      (t) => t.id == 'transfer_web_drop',
      orElse: () => _allTools.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 14,
                  color: Color(0xFFFF9500),
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'أدوات بينتو الذكية السريعة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'فوري ⚡',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF9500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSpotlightCard(
                  tool: toolExcel,
                  isDark: isDark,
                  palette: palette,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSpotlightCard(
                  tool: toolWebDrop,
                  isDark: isDark,
                  palette: palette,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightCard({
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _onToolSelected(tool);
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tool.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Icon(
                          tool.icon,
                          color: tool.accentColor,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tool.accentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tool.badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: tool.accentColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tool.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  tool.subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFFA1A1A6)
                        : const Color(0xFF48484A),
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBentoMiniPill({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11.5,
              color: isDark ? const Color(0xFF98989D) : const Color(0xFF636366),
            ),
            const SizedBox(width: 4.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filtered Search & Category Banner ──

  Widget _buildFilteredHeader({
    required int toolsCount,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    final title = _searchQuery.trim().isNotEmpty
        ? 'نتائج البحث عن "$_searchQuery"'
        : _selectedCategory.sectionTitle;
    final subtitle = _searchQuery.trim().isNotEmpty
        ? 'تم العثور على $toolsCount نتيجة مطابقة'
        : _selectedCategory.sectionSubtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.6,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.025),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _searchQuery.trim().isNotEmpty
                    ? Icons.search_rounded
                    : _selectedCategory.icon,
                size: 18,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFA1A1A6)
                          : const Color(0xFF636366),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$toolsCount أداة',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section Header ──

  Widget _buildSectionHeader({
    required ToolCategory category,
    required int count,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              category.icon,
              size: 15,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.sectionTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  category.sectionSubtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFFA1A1A6)
                        : const Color(0xFF636366),
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count أدوات',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Inset Grouped List Design (Apple iOS Settings Style) ──

  Widget _buildInsetGroupedCategoryList({
    required BuildContext context,
    required List<ToolItem> tools,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.035),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            for (int i = 0; i < tools.length; i++) ...[
              _buildInsetGroupRow(
                context: context,
                tool: tools[i],
                isDark: isDark,
                palette: palette,
              ),
              if (i < tools.length - 1)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 62,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsetGroupRow({
    required BuildContext context,
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _onToolSelected(tool);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Squircle App Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tool.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  tool.icon,
                  color: tool.accentColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),

              // Title, Badge, Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tool.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tool.accentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tool.badge,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: tool.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tool.subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFFA1A1A6)
                            : const Color(0xFF48484A),
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Color(0xFF8E8E93),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Grid Card Design (Apple Bento Paper Grid Style) ──

  Widget _buildGridCard({
    required BuildContext context,
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            _onToolSelected(tool);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Squircle App Icon + Discrete Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tool.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Icon(
                          tool.icon,
                          color: tool.accentColor,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tool.accentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tool.badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: tool.accentColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Title
                Text(
                  tool.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Subtitle
                Expanded(
                  child: Text(
                    tool.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFA1A1A6)
                          : const Color(0xFF48484A),
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
