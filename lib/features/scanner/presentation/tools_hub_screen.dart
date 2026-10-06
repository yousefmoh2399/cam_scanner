import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
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
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';
import 'widgets/theme_selection_sheet.dart';
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
import 'anti_moire_whiteboard_screen.dart';

/// Categories for organizing tools in the hub
enum ToolCategory {
  all('الكل', Icons.apps_rounded),
  government('هوية ووثائق', Icons.badge_rounded),
  intelligence('استخراج وذكاء', Icons.auto_awesome_rounded),
  pdf('أدوات PDF', Icons.picture_as_pdf_rounded),
  security('أمان وخصوصية', Icons.security_rounded);

  const ToolCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  String get sectionTitle {
    switch (this) {
      case ToolCategory.all:
        return 'جميع الأدوات';
      case ToolCategory.government:
        return 'الهوية والمستندات الرسمية';
      case ToolCategory.intelligence:
        return 'الذكاء الاصطناعي والاستخراج';
      case ToolCategory.pdf:
        return 'أدوات وإدارة ملفات PDF';
      case ToolCategory.security:
        return 'الأمان والحماية والخصوصية';
    }
  }

  String get sectionSubtitle {
    switch (this) {
      case ToolCategory.all:
        return 'تصفح كافة الأدوات المتوفرة';
      case ToolCategory.government:
        return 'قوالب مطابقة للمواصفات الدولية ISO وضغط بوابات التقديم والسفارات';
      case ToolCategory.intelligence:
        return 'تحويل الجداول لإكسل، استخراج بيانات الرقم القومي، وفصل الكتب';
      case ToolCategory.pdf:
        return 'دمج، تقسيم، وضغط ملفات الـ PDF مع الحفاظ على دقة النص';
      case ToolCategory.security:
        return 'تشفير عسكري بالخزنة، العلامة المائية، والحجب الأمني الفوري';
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
      title: 'بطاقة وش وظهر A4 (مقياس 1:1)',
      subtitle: 'دمج وجهي البطاقة في A4 بالأبعاد الحقيقية 1:1 مع علامة أمنية وطباعة فورية',
      category: ToolCategory.government,
      icon: Icons.badge_rounded,
      badge: 'مقياس 1:1',
      accentColor: Color(0xFF007AFF),
      keywords: ['بطاقة', 'هوية', 'رخصة', 'قيادة', 'إقامة', 'id', 'وش وضهر', 'رسمي', 'a4', '1:1', 'طباعة'],
    ),
    ToolItem(
      id: 'gov_passport_cert',
      title: 'جواز السفر والشهادات',
      subtitle: 'تنسيق عالي الدقة لوثائق السفر والعقود الرسمية',
      category: ToolCategory.government,
      icon: Icons.menu_book_rounded,
      badge: 'ICAO',
      accentColor: Color(0xFF5856D6),
      keywords: ['جواز', 'سفر', 'شهادة', 'تخرج', 'عقد', 'رسمي', 'passport'],
    ),
    ToolItem(
      id: 'gov_photo_grid',
      title: 'استوديو الصور الشخصية',
      subtitle: 'شبكة صور A4 جاهزة للطباعة والتأشيرات',
      category: ToolCategory.government,
      icon: Icons.photo_camera_front_rounded,
      badge: 'تأشيرات',
      accentColor: Color(0xFF34C759),
      keywords: ['صور', 'شخصية', 'تأشيرة', 'شنغن', 'امريكا', 'سفر', 'جواز', 'طباعة', 'visa'],
    ),
    ToolItem(
      id: 'gov_portal_compress',
      title: 'ضغط بوابات التقديم',
      subtitle: 'تقليص الحجم للقبول في السفارات والمواقع',
      category: ToolCategory.government,
      icon: Icons.speed_rounded,
      badge: 'ضغط دقيق',
      accentColor: Color(0xFFFF2D55),
      keywords: ['ضغط', 'بوابات', 'تقديم', 'سفارات', 'توظيف', 'حجم', 'مستند'],
    ),
    ToolItem(
      id: 'gov_smart_contracts',
      title: 'استوديو العقود والقوالب الذكية',
      subtitle: 'توليد عقود بيع وإيجار وإيصالات أمانة وتفقيط المبالغ',
      category: ToolCategory.government,
      icon: Icons.gavel_rounded,
      badge: 'قوالب قانونية',
      accentColor: Color(0xFF5856D6),
      keywords: ['عقد', 'عقود', 'إيجار', 'بيع', 'أمانة', 'إيصال', 'شقة', 'سيارة', 'قانوني'],
    ),
    ToolItem(
      id: 'gov_smart_id_wallet',
      title: 'محفظة البطاقات وطباعة PVC',
      subtitle: 'حفظ الهويات برؤية 3D وطباعة كروت بلاستيكية CR-80 بمقياس 1:1',
      category: ToolCategory.government,
      icon: Icons.credit_card_rounded,
      badge: 'CR-80 PVC',
      accentColor: Color(0xFF007AFF),
      keywords: ['بطاقة', 'بلاستيك', 'pvc', 'cr80', 'محفظة', 'id', 'رخصة', 'كارنيه', 'طباعة'],
    ),

    // ── Intelligence & Extraction Category ──
    ToolItem(
      id: 'ai_excel_converter',
      title: 'تحويل الجداول إلى Excel',
      subtitle: 'استخراج الجداول بدقة لملفات .xlsx حقيقية',
      category: ToolCategory.intelligence,
      icon: Icons.table_chart_rounded,
      badge: 'ذكاء اصطناعي',
      accentColor: Color(0xFF10B981),
      keywords: ['إكسل', 'excel', 'جدول', 'xlsx', 'أرقام', 'حسابات'],
    ),
    ToolItem(
      id: 'ai_smart_extraction',
      title: 'الاستخراج الذكي والتحليل',
      subtitle: 'تفكيك البيانات وجهات الاتصال وقراءة النصوص',
      category: ToolCategory.intelligence,
      icon: Icons.psychology_rounded,
      badge: 'Smart OCR',
      accentColor: Color(0xFF8B5CF6),
      keywords: ['رقم قومي', 'هاتف', 'اتصال', 'vcard', 'تفريغ', 'صوت', 'tts'],
    ),
    ToolItem(
      id: 'ai_book_split',
      title: 'مسح وفصل صفحات الكتب',
      subtitle: 'فصل وتعديل الصفحتين المتقابلتين تلقائياً',
      category: ToolCategory.intelligence,
      icon: Icons.menu_book_rounded,
      badge: 'Book Mode',
      accentColor: Color(0xFFF59E0B),
      keywords: ['كتاب', 'صفحتين', 'فصل', 'منحنيات', 'مجلد', 'دراسة'],
    ),
    ToolItem(
      id: 'ai_magic_clean',
      title: 'الممحاة الذكية وتنظيف الورق',
      subtitle: 'إزالة أصابع اليد، ثقوب الدباسة، وبقع القهوة بدون إنترنت',
      category: ToolCategory.intelligence,
      icon: Icons.auto_fix_high_rounded,
      badge: 'ذكاء محلي',
      accentColor: Color(0xFFFF2D55),
      keywords: ['ممحاة', 'أصابع', 'ثقوب', 'دباسة', 'بقع', 'تنظيف', 'ورق', 'magic', 'clean'],
    ),
    ToolItem(
      id: 'ai_shadow_remover',
      title: 'إزالة ظل الهاتف وضبط الإضاءة',
      subtitle: 'معادلة الإضاءة وإزالة ظلال اليد لتسوية خلفية الورقة',
      category: ToolCategory.intelligence,
      icon: Icons.wb_sunny_rounded,
      badge: 'Shadow Killer',
      accentColor: Color(0xFFFF9500),
      keywords: ['ظل', 'ظلال', 'إضاءة', 'هاتف', 'نور', 'فلاش', 'shadow', 'glare'],
    ),
    ToolItem(
      id: 'ai_doc_diff',
      title: 'مقارنة المستندات واكتشاف الفروقات',
      subtitle: 'منزلق بصري وكشف الكلمات المضافة والمحذوفة في العقود',
      category: ToolCategory.intelligence,
      icon: Icons.splitscreen_rounded,
      badge: 'Diff & Compare',
      accentColor: Color(0xFF8B5CF6),
      keywords: ['مقارنة', 'فروقات', 'عقود', 'تعديل', 'تزوير', 'diff', 'compare'],
    ),
    ToolItem(
      id: 'ai_book_curve_flattener',
      title: 'تسوية انحناء الكتب ثلاثي الأبعاد',
      subtitle: 'معالجة تقوس صفحات المجلدات والكتب وإزالة ظل الكعب',
      category: ToolCategory.intelligence,
      icon: Icons.auto_stories_rounded,
      badge: '3D Dewarp',
      accentColor: Color(0xFFF59E0B),
      keywords: ['كتاب', 'مجلد', 'انحناء', 'تقوس', 'كعب', 'تسوية', 'مسطح', 'dewarp', 'curve', 'book'],
    ),
    ToolItem(
      id: 'ai_notebook_remover',
      title: 'إزالة خطوط الدفاتر والشبكات',
      subtitle: 'إزالة خطوط التسطير الأفقية وشبكات الرسم البياني مع الحفاظ على الكتابة اليدوية',
      category: ToolCategory.intelligence,
      icon: Icons.border_color_rounded,
      badge: 'جديد • كشكول 📓',
      accentColor: Color(0xFF007AFF),
      keywords: ['كشكول', 'دفتر', 'تسطير', 'خطوط', 'مربعات', 'رسم بياني', 'شبكة', 'notebook', 'grid', 'lines'],
    ),
    ToolItem(
      id: 'ai_object_counter',
      title: 'عداد العناصر والأشياء التلقائي',
      subtitle: 'عد الأنابيب، الكراتين، حبات الدواء، والمستندات بنقاط مرقمة وتقرير جرد PDF',
      category: ToolCategory.intelligence,
      icon: Icons.pin_rounded,
      badge: 'عداد AI 🔢',
      accentColor: Color(0xFFFF9500),
      keywords: ['عد', 'عداد', 'أنابيب', 'كراتين', 'بضائع', 'دواء', 'جرد', 'مخزن', 'counter', 'inventory', 'objects'],
    ),
    ToolItem(
      id: 'ai_anti_moire_glare',
      title: 'مزيل تموجات الشاشات والسبورة',
      subtitle: 'إزالة تموجات Moiré من شاشات الحواسيب ولمعان إضاءة السبورة كلقطة شاشة رقمية',
      category: ToolCategory.intelligence,
      icon: Icons.screenshot_monitor_rounded,
      badge: 'شاشات وسبورة 🖥️',
      accentColor: Color(0xFF5856D6),
      keywords: ['شاشة', 'كمبيوتر', 'تلفزيون', 'تموج', 'سبورة', 'لمعان', 'فلاش', 'moire', 'glare', 'whiteboard'],
    ),

    // ── PDF Tools Category ──
    ToolItem(
      id: 'pdf_merge',
      title: 'دمج مستندات PDF',
      subtitle: 'تجميع عدة ملفات في مستند واحد منظم',
      category: ToolCategory.pdf,
      icon: Icons.merge_type_rounded,
      badge: 'دمج فوري',
      accentColor: Color(0xFF2563EB),
      keywords: ['دمج', 'تجميع', 'pdf', 'ملفات', 'ترتيب'],
    ),
    ToolItem(
      id: 'pdf_split',
      title: 'تقسيم واستخراج الصفحات',
      subtitle: 'فصل وتصدير صفحات محددة من مستند PDF',
      category: ToolCategory.pdf,
      icon: Icons.call_split_rounded,
      badge: 'تقسيم',
      accentColor: Color(0xFF0D9488),
      keywords: ['تقسيم', 'فصل', 'استخراج', 'صفحات', 'pdf'],
    ),
    ToolItem(
      id: 'pdf_target_compress',
      title: 'ضغط PDF لحجم محدد',
      subtitle: 'تقليص حجم المستند مع الحفاظ على الوضوح',
      category: ToolCategory.pdf,
      icon: Icons.compress_rounded,
      badge: 'حجم مخصص',
      accentColor: Color(0xFF4F46E5),
      keywords: ['ضغط', 'حجم', 'pdf', 'تقليل', 'كيلوبايت'],
    ),
    ToolItem(
      id: 'pdf_import',
      title: 'استيراد مستندات وصور',
      subtitle: 'جلب ملفات PDF وصور خارجية إلى مكتبتك',
      category: ToolCategory.pdf,
      icon: Icons.file_download_rounded,
      badge: 'استيراد',
      accentColor: Color(0xFF059669),
      keywords: ['استيراد', 'جلب', 'ملف', 'صورة', 'تنزيل'],
    ),
    ToolItem(
      id: 'transfer_web_drop',
      title: 'نقل للكمبيوتر محلياً (Web Drop)',
      subtitle: 'إرسال وتنزيل الملفات عبر المتصفح بدون كابلات أو إنترنت',
      category: ToolCategory.pdf,
      icon: Icons.wifi_tethering_rounded,
      badge: 'AirDrop محلي',
      accentColor: Color(0xFF007AFF),
      keywords: ['كمبيوتر', 'ماك', 'wifi', 'نقل', 'متصفح', 'airdrop', 'drop', 'شير'],
    ),
    ToolItem(
      id: 'transfer_files_hub',
      title: 'مركز الملفات المنقولة',
      subtitle: 'إدارة الملفات المستلمة والمرسلة مع الكمبيوتر وحفظها وتنزيلها',
      category: ToolCategory.pdf,
      icon: Icons.folder_shared_rounded,
      badge: 'مستندات النقل',
      accentColor: Color(0xFF0D9488),
      keywords: ['ملفات', 'منقولة', 'مستلمة', 'مرسلة', 'كمبيوتر', 'web drop', 'تنزيلات', 'transferred'],
    ),

    // ── Security, Privacy & Maintenance Category ──
    ToolItem(
      id: 'sec_vault',
      title: 'الخزنة السرية المشفرة',
      subtitle: 'حماية وتشفير المستندات بالبصمة ورمز المرور',
      category: ToolCategory.security,
      icon: Icons.enhanced_encryption_rounded,
      badge: 'AES-256',
      accentColor: Color(0xFF059669),
      keywords: ['خزنة', 'قفل', 'بصمة', 'تشفير', 'سري', 'pin', 'حماية'],
    ),
    ToolItem(
      id: 'sec_exif_scrub',
      title: 'تنظيف بيانات الخصوصية',
      subtitle: 'إزالة الموقع الجغرافي وبيانات الكاميرا نهائياً',
      category: ToolCategory.security,
      icon: Icons.location_off_rounded,
      badge: 'خصوصية',
      accentColor: Color(0xFFE11D48),
      keywords: ['موقع', 'gps', 'exif', 'خصوصية', 'تنظيف', 'حذف'],
    ),
    ToolItem(
      id: 'sec_signatures',
      title: 'التوقيعات الرقمية والأختام',
      subtitle: 'توقيع العقود والمستندات بلمسة واحدة',
      category: ToolCategory.security,
      icon: Icons.draw_rounded,
      badge: 'توقيع',
      accentColor: Color(0xFF6366F1),
      keywords: ['توقيع', 'ختم', 'عقد', 'توقيعات', 'بصمة'],
    ),
    ToolItem(
      id: 'sec_trash',
      title: 'سلة المحذوفات',
      subtitle: 'استرجاع المستندات المحذوفة خلال 30 يوماً',
      category: ToolCategory.security,
      icon: Icons.delete_sweep_rounded,
      badge: 'حماية 30 يوم',
      accentColor: Color(0xFFDC2626),
      keywords: ['سلة', 'حذف', 'محذوفات', 'استرجاع', 'مهملات'],
    ),
    ToolItem(
      id: 'sec_watermark',
      title: 'العلامة المائية والأختام',
      subtitle: 'إضافة نصوص وأختام أمنية لمنع التزوير',
      category: ToolCategory.security,
      icon: Icons.verified_user_rounded,
      badge: 'أمان',
      accentColor: Color(0xFFDC2626),
      keywords: ['علامة', 'مائية', 'ختم', 'أمان', 'بنك', 'بطاقة', 'تزوير', 'watermark'],
    ),
    ToolItem(
      id: 'sec_smart_redaction',
      title: 'الحجب الأمني وتسويد البيانات',
      subtitle: 'حجب الأرقام والبيانات الحساسة بشكل نهائي',
      category: ToolCategory.security,
      icon: Icons.visibility_off_rounded,
      badge: 'حماية الهوية',
      accentColor: Color(0xFF334155),
      keywords: ['حجب', 'تسويد', 'رقم قومي', 'خصوصية', 'redact', 'تشفير'],
    ),
    ToolItem(
      id: 'sec_backup_zip',
      title: 'النسخ الاحتياطي (.ZIP)',
      subtitle: 'تصدير واستعادة مكتبتك بالكامل بدون إنترنت',
      category: ToolCategory.security,
      icon: Icons.folder_zip_rounded,
      badge: 'نسخ محلي',
      accentColor: Color(0xFF9333EA),
      keywords: ['نسخ', 'احتياطي', 'استعادة', 'zip', 'أرشيف', 'تصدير'],
    ),
    ToolItem(
      id: 'sec_digital_stamp',
      title: 'استوديو الأختام والتواقيع',
      subtitle: 'أختام رسمية وتفريغ الحبر والشفافية بلمسة واحدة',
      category: ToolCategory.security,
      icon: Icons.verified_rounded,
      badge: 'أختام رسمية',
      accentColor: Color(0xFFD62B2B),
      keywords: ['ختم', 'أختام', 'توقيع', 'رسمي', 'معتمد', 'مدفوع', 'شفافية'],
    ),
    ToolItem(
      id: 'sec_pdf_lock',
      title: 'قفل وتشفير المستندات (AES-256)',
      subtitle: 'حماية وتشفير ملفات الـ PDF بكلمة مرور وقفل بالبصمة',
      category: ToolCategory.security,
      icon: Icons.lock_rounded,
      badge: 'تشفير عسكري',
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
        _showExifScrubberAction();
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
        _showBackupRestoreLauncher();
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
    }
  }

  // ── Action Handlers ──

  Future<void> _showBookCurveLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];

    final choice = await showModalBottomSheet<String>(
      context: context,
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
          final path = results.first.path;
          if (File(path).existsSync()) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookCurveFlattenerScreen(imagePath: path),
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
        final path = res.files.single.path!;
        if (File(path).existsSync()) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookCurveFlattenerScreen(imagePath: path),
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
        if (scanResults.isNotEmpty) {
          path = scanResults.first.path;
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
      path = result?.files.firstOrNull?.path;
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

  Future<void> _showExifScrubberAction() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;

    setState(() => _isProcessing = true);
    try {
      final scrubber = ref.read(exifScrubberServiceProvider);
      final cleanPath = await scrubber.scrubFile(path);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF10B981),
            size: 40,
          ),
          title: const Text(
            'تم تنظيف بيانات الخصوصية بنجاح!',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'تمت إزالة كافة بيانات الموقع الجغرافي (GPS) ومعلومات الكاميرا والجهاز والبيانات الوصفية (EXIF).\n\nملفك نظيف وخصوصيتك محفوظة 100%.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Share.shareXFiles([XFile(cleanPath)],
                    subject: 'صورة نظيفة بدون بيانات موقع');
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('مشاركة الصورة النظيفة'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تنظيف البيانات: $e')),
        );
      }
    }
  }

  Future<void> _showBackupRestoreLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    final folders =
        await ref.read(documentFolderServiceProvider).loadFolders();
    final pwdCtrl = TextEditingController();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'النسخ الاحتياطي والاستعادة الشاملة (.ZIP)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'تصدير كل المستندات والمجلدات وفهرس البحث في ملف .zip محلي أو استعادتها بدون تكرار.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText:
                      'كلمة مرور لتشفير النسخة الاحتياطية (اختياري AES-256)',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final pwd = pwdCtrl.text.trim();
                  Navigator.of(sheetCtx).pop();
                  try {
                    final backupSvc = ref.read(backupRestoreServiceProvider);
                    final zipPath = await backupSvc.createBackupZip(
                      documents: docs,
                      folders: folders,
                      password: pwd.isEmpty ? null : pwd,
                    );
                    if (mounted) {
                      await Share.shareXFiles(
                        [XFile(zipPath)],
                        subject: 'نسخة احتياطية للمستندات',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل إنشاء النسخة: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.archive_rounded),
                label: Text('تصدير ومشاركة نسخة احتياطية (${docs.length} مستند)'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final pwd = pwdCtrl.text.trim();
                  Navigator.of(sheetCtx).pop();
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['zip'],
                  );
                  final path = picked?.files.firstOrNull?.path;
                  if (path == null) return;

                  try {
                    final backupSvc = ref.read(backupRestoreServiceProvider);
                    final res = await backupSvc.restoreFromBackupFile(
                      zipFilePath: path,
                      currentDocuments: docs,
                      currentFolders: folders,
                      password: pwd.isEmpty ? null : pwd,
                    );
                    await ref
                        .read(documentFolderServiceProvider)
                        .saveFolders(res.mergedFolders);
                    await ref
                        .read(pendingUploadsControllerProvider.notifier)
                        .replaceAllDocuments(res.mergedDocuments);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تمت الاستعادة بنجاح! (${res.stats.restoredDocuments} مستند، ${res.stats.restoredFolders} مجلد)',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل الاستعادة: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.unarchive_rounded),
                label: const Text('استعادة من ملف .ZIP'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── UI Build ──

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tools = _filteredTools;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final childAspectRatio =
        isTablet ? 1.55 : (screenWidth < 370 ? 1.30 : 1.42);

    final isDefaultGroupedView =
        _selectedCategory == ToolCategory.all && _searchQuery.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الأدوات',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              '${_allTools.length} أداة • أوفلاين 100%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
        actions: [
          // View Mode Switcher (Grid vs List toggle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                _setViewMode(!_isGridView);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF242426)
                      : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isGridView
                      ? Icons.view_agenda_rounded
                      : Icons.grid_view_rounded,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFE5E5EA)
                      : const Color(0xFF1C1C1E),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => showThemeSelectionSheet(context, ref),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF242426)
                      : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.palette_outlined,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFE5E5EA)
                      : const Color(0xFF1C1C1E),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                ref
                    .read(userPreferencesControllerProvider.notifier)
                    .toggleDarkMode();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF242426)
                      : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFE5E5EA)
                      : const Color(0xFF1C1C1E),
                ),
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
              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText:
                          'ابحث في الأدوات (رقم قومي، إكسل، pdf، علامة مائية...)...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: palette.accent,
                      ),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1E22)
                          : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),

              // Category Filter Chips
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: ToolCategory.values.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      final count = cat == ToolCategory.all
                          ? _allTools.length
                          : _allTools.where((t) => t.category == cat).length;

                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FilterChip(
                          selected: isSelected,
                          avatar: Icon(
                            cat.icon,
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          label: Text(
                            '${cat.label} ($count)',
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 12.5,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          selectedColor: palette.accent,
                          checkmarkColor: Colors.white,
                          onSelected: (_) {
                            setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Section Header / Quick Summary Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        _searchQuery.trim().isNotEmpty
                            ? 'نتائج البحث (${tools.length} أداة)'
                            : (_selectedCategory == ToolCategory.all
                                ? 'جميع الأقسام المنظمة (${_allTools.length} أداة)'
                                : '${_selectedCategory.sectionTitle} (${tools.length})'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const Spacer(),
                      // Layout indication pill
                      InkWell(
                        onTap: () => _setViewMode(!_isGridView),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isGridView
                                    ? Icons.grid_view_rounded
                                    : Icons.view_agenda_rounded,
                                size: 14,
                                color: palette.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isGridView ? 'عرض شبكي' : 'عرض قائمة',
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
                    ],
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد أداة مطابقة لكلمات البحث',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'جرب البحث بكلمات أخرى مثل: بطاقة، إكسل، PDF، خزنة',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
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
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('عرض جميع الأدوات'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isDefaultGroupedView)
                // Grouped by Category when viewing All and no search query
                ...[
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
                                  crossAxisCount: isTablet ? 3 : 2,
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
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    return _buildListCard(
                                      context: context,
                                      tool: categoryTools[index],
                                      isDark: isDark,
                                      palette: palette,
                                    );
                                  },
                                  childCount: categoryTools.length,
                                ),
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
                // Filtered or Search Mode: Flat list/grid
                ...[
                  if (_isGridView)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 3 : 2,
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
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildListCard(
                              context: context,
                              tool: tools[index],
                              isDark: isDark,
                              palette: palette,
                            );
                          },
                          childCount: tools.length,
                        ),
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
                          style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _buildSectionHeader({
    required ToolCategory category,
    required int count,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              category.icon,
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
                  category.sectionTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  category.sectionSubtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count أدوات',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid Card Design ──

  Widget _buildGridCard({
    required BuildContext context,
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.07),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            _onToolSelected(tool);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Icon + Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: tool.accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        tool.icon,
                        color: tool.accentColor,
                        size: 18,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: tool.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tool.badge,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: tool.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Title
                Text(
                  tool.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),

                // Subtitle
                Expanded(
                  child: Text(
                    tool.subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.60),
                      height: 1.25,
                    ),
                    maxLines: 2,
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

  // ── List Card Design ──

  Widget _buildListCard({
    required BuildContext context,
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.lightImpact();
            _onToolSelected(tool);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Tool Icon Box
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tool.accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    tool.icon,
                    color: tool.accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Tool Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tool.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tool.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              tool.badge,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: tool.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tool.subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.60),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
