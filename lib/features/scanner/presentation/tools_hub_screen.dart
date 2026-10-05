import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/local_media_storage_service.dart';
import '../data/native_scanner_bridge.dart';
import '../data/office_exporter_service.dart';
import 'government_documents_screen.dart';
import 'pdf_tools_screen.dart';
import 'signature_bottom_sheet.dart';
import 'trash_screen.dart';
import 'vault_screen.dart';
import 'widgets/export_format_sheet.dart';
import 'widgets/smart_data_extraction_sheet.dart';

/// Categories for organizing tools in the hub
enum ToolCategory {
  all('الكل', Icons.apps_rounded),
  government('أوراق حكومية', Icons.account_balance_rounded),
  intelligence('استخراج وذكاء', Icons.auto_awesome_rounded),
  pdf('أدوات PDF', Icons.picture_as_pdf_rounded),
  security('أمان وخصوصية', Icons.security_rounded);

  const ToolCategory(this.label, this.icon);
  final String label;
  final IconData icon;
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

  final List<ToolItem> _allTools = const [
    // ── Government & Official Category ──
    ToolItem(
      id: 'gov_id_card',
      title: 'بطاقة الرقم القومي (وش وضهر A4)',
      subtitle:
          'دمج وجه وظهر البطاقة في ورقة A4 واحدة بالأبعاد الرسمية القياسية ID-1 للتقديم في البوابات والجهات الرسمية.',
      category: ToolCategory.government,
      icon: Icons.badge_rounded,
      badge: 'رسمي مصري',
      accentColor: Color(0xFFD97706),
      keywords: ['بطاقة', 'رقم قومي', 'حكومي', 'وش وضهر', 'id', 'مصر'],
    ),
    ToolItem(
      id: 'gov_portal_compress',
      title: 'ضغط مخصص للبوابات الحكومية',
      subtitle:
          'تقليص حجم المستندات بدقة متناهية لأقل من (100KB أو 200KB أو 500KB أو 1MB) لتوافق مواقع التقديم والوظائف.',
      category: ToolCategory.government,
      icon: Icons.speed_rounded,
      badge: 'أقل من 200KB',
      accentColor: Color(0xFFEA580C),
      keywords: ['ضغط', 'حكومي', 'بوابات', 'حجم', 'ميزانية', 'بريد'],
    ),
    ToolItem(
      id: 'gov_photo_grid',
      title: 'تخطيط الصور الشخصية (3×4 و 4×6)',
      subtitle:
          'تجهيز شبكة صور شخصية متعددة (8 صور 3×4 أو 4 صور 4×6) على ورقة A4 واحدة جاهزة للطباعة والتسليم فوراً.',
      category: ToolCategory.government,
      icon: Icons.photo_library_rounded,
      badge: 'طباعة فورية',
      accentColor: Color(0xFF0284C7),
      keywords: ['صور', 'شخصية', '3x4', '4x6', 'جواز', 'كارنيه', 'طباعة'],
    ),
    ToolItem(
      id: 'gov_passport_cert',
      title: 'جواز السفر والشهادات الرسمية',
      subtitle:
          'توسيط دقيق وتنسيق عالي الجودة للشهادات وجوازات السفر على صفحة A4 طولياً أو عرضياً بدون تشويه.',
      category: ToolCategory.government,
      icon: Icons.workspace_premium_rounded,
      badge: 'A4 معتمد',
      accentColor: Color(0xFF7C3AED),
      keywords: ['جواز', 'شهادة', 'تخرج', 'ميلاد', 'رسمي'],
    ),

    // ── Intelligence & Extraction Category ──
    ToolItem(
      id: 'ai_excel_converter',
      title: 'تحويل الجداول إلى Excel احترافي (.xlsx)',
      subtitle:
          'إعادة بناء الجداول المطبوعة والممسوحة ضوئياً داخل ملف إكسل حقيقي مع شبكة خلايا وتنسيق ودعم العربي RTL.',
      category: ToolCategory.intelligence,
      icon: Icons.table_chart_rounded,
      badge: 'جديد ومميز',
      accentColor: Color(0xFF10B981),
      keywords: ['إكسل', 'excel', 'جدول', 'xlsx', 'أرقام', 'حسابات'],
    ),
    ToolItem(
      id: 'ai_smart_extraction',
      title: 'الاستخراج الذكي والتحليل (Smart OCR)',
      subtitle:
          'تفكيك بيانات الرقم القومي (تاريخ الميلاد، المحافظة، النوع)، استخراج الهواتف، تصدير جهات الاتصال vCard، والقراءة الصوتية.',
      category: ToolCategory.intelligence,
      icon: Icons.psychology_rounded,
      badge: 'تحليل فوري',
      accentColor: Color(0xFF8B5CF6),
      keywords: ['رقم قومي', 'هاتف', 'اتصال', 'vcard', 'تفريغ', 'صوت', 'tts'],
    ),
    ToolItem(
      id: 'ai_book_split',
      title: 'مسح وفصل صفحات الكتب (Book Mode)',
      subtitle:
          'تصوير صفحتين متقابلتين في لقطة واحدة وفصل الصفحة اليمنى واليسرى تلقائياً مع تسوية الانحناءات.',
      category: ToolCategory.intelligence,
      icon: Icons.menu_book_rounded,
      badge: 'للطلبة والباحثين',
      accentColor: Color(0xFFF59E0B),
      keywords: ['كتاب', 'صفحتين', 'فصل', 'منحنيات', 'مجلد', 'دراسة'],
    ),

    // ── PDF Tools Category ──
    ToolItem(
      id: 'pdf_merge',
      title: 'دمج ملفات PDF متعددة',
      subtitle:
          'دمج عدة ملفات ومستندات في ملف PDF واحد متكامل مع إمكانية ترتيب الصفحات وضغط الملف الناتج.',
      category: ToolCategory.pdf,
      icon: Icons.merge_type_rounded,
      badge: 'بدون إنترنت',
      accentColor: Color(0xFF2563EB),
      keywords: ['دمج', 'تجميع', 'pdf', 'ملفات', 'ترتيب'],
    ),
    ToolItem(
      id: 'pdf_split',
      title: 'تقسيم واستخراج صفحات PDF',
      subtitle:
          'فصل صفحات محددة من مستند PDF وتصديرها كملف مستقل أو حفظ كل صفحة على حدة.',
      category: ToolCategory.pdf,
      icon: Icons.call_split_rounded,
      badge: 'استخراج سريع',
      accentColor: Color(0xFF0D9488),
      keywords: ['تقسيم', 'فصل', 'استخراج', 'صفحات', 'pdf'],
    ),
    ToolItem(
      id: 'pdf_target_compress',
      title: 'ضغط PDF إلى حجم محدد',
      subtitle:
          'تقليص حجم ملف PDF ليصل لأقل من حجم مستهدف بالكيلوبايت تحدده بنفسك مع الحفاظ على المقروءية.',
      category: ToolCategory.pdf,
      icon: Icons.compress_rounded,
      badge: 'حجم مخصص',
      accentColor: Color(0xFF4F46E5),
      keywords: ['ضغط', 'حجم', 'pdf', 'تقليل', 'كيلوبايت'],
    ),
    ToolItem(
      id: 'pdf_import',
      title: 'استيراد ملفات PDF وصور خارجية',
      subtitle:
          'جلب مستندات PDF أو صور من ذاكرة الجهاز أو التحميلات ودمجها داخل مكتبتك الممسوحة.',
      category: ToolCategory.pdf,
      icon: Icons.file_download_rounded,
      badge: 'استيراد',
      accentColor: Color(0xFF059669),
      keywords: ['استيراد', 'جلب', 'ملف', 'صورة', 'تنزيل'],
    ),

    // ── Security, Privacy & Maintenance Category ──
    ToolItem(
      id: 'sec_vault',
      title: 'الخزنة السرية المشفرة (AES-256-GCM)',
      subtitle:
          'تشفير وحماية المستندات الهامة على القرص بكلمة سر وبصمة الإصبع وحجبها تماماً عن المعرض والمكتبة العامة.',
      category: ToolCategory.security,
      icon: Icons.enhanced_encryption_rounded,
      badge: 'تشفير عسكري',
      accentColor: Color(0xFF059669),
      keywords: ['خزنة', 'قفل', 'بصمة', 'تشفير', 'سري', 'pin', 'حماية'],
    ),
    ToolItem(
      id: 'sec_exif_scrub',
      title: 'تنظيف بيانات الخصوصية والموقع (EXIF/GPS)',
      subtitle:
          'حذف بيانات الموقع الجغرافي ومعلومات الكاميرا تلقائياً من الصور والمستندات قبل مشاركتها، لتظل خصوصيتك محفوظة.',
      category: ToolCategory.security,
      icon: Icons.location_off_rounded,
      badge: 'خصوصية تامة',
      accentColor: Color(0xFFE11D48),
      keywords: ['موقع', 'gps', 'exif', 'خصوصية', 'تنظيف', 'حذف'],
    ),
    ToolItem(
      id: 'sec_signatures',
      title: 'التوقيعات الرقمية والأختام',
      subtitle:
          'رسم وتخزين توقيعاتك الشخصية أو استيراد الأختام الرسمية لتوقيع العقود والمستندات بلمسة واحدة.',
      category: ToolCategory.security,
      icon: Icons.draw_rounded,
      badge: 'توقيع معتمد',
      accentColor: Color(0xFF6366F1),
      keywords: ['توقيع', 'ختم', 'عقد', 'توقيعات', 'بصمة'],
    ),
    ToolItem(
      id: 'sec_trash',
      title: 'سلة المحذوفات الذكية (Trash)',
      subtitle:
          'حماية ملفاتك من الحذف بالخطأ؛ يتم حفظ المستندات المحذوفة لمدة 30 يوماً مع إمكانية استرجاعها فوراً.',
      category: ToolCategory.security,
      icon: Icons.delete_sweep_rounded,
      badge: 'استرجاع 30 يوم',
      accentColor: Color(0xFFDC2626),
      keywords: ['سلة', 'حذف', 'محذوفات', 'استرجاع', 'مهملات'],
    ),
    ToolItem(
      id: 'sec_backup_zip',
      title: 'النسخ الاحتياطي والاستعادة (.ZIP)',
      subtitle:
          'تصدير مكتبتك كاملة بالمجلدات وفهرس البحث في ملف مضغوط محلياً أو استعادتها بدون إنترنت مع خيار التشفير.',
      category: ToolCategory.security,
      icon: Icons.folder_zip_rounded,
      badge: 'أرشيف كامل',
      accentColor: Color(0xFF9333EA),
      keywords: ['نسخ', 'احتياطي', 'استعادة', 'zip', 'أرشيف', 'تصدير'],
    ),
  ];

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
      case 'gov_portal_compress':
      case 'gov_photo_grid':
      case 'gov_passport_cert':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GovernmentDocumentsScreen(),
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
    }
  }

  // ── Action Handlers ──

  Future<void> _openSignaturesSheet() async {
    final storage = ref.read(signatureStorageServiceProvider);
    await showSignatureBottomSheet(
      context: context,
      storageService: storage,
    );
  }

  Future<void> _showExcelActionDialog() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      _showSimpleInfoDialog(
        title: 'تحويل الجداول إلى Excel (.xlsx)',
        message:
            'لا توجد مستندات ممسوحة ضوئياً بعد في مكتبتك.\nقم بمسح ورقة تحتوي على جدول بالكاميرا أولاً، أو استورد ملفاً من قائمة الأدوات لتصديره فوراً إلى ملف Excel احترافي.',
      );
      return;
    }

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
                          'اختر المستند المراد تحويله إلى جدول .xlsx يدعم العربية RTL',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
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
                      trailing: const Icon(Icons.arrow_forward_ios_rounded,
                          size: 14),
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
          ),
        ),
      ),
    );
  }

  Future<void> _showSmartExtractionLauncher() async {
    final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      // Allow user to test with custom text directly!
      final textCtrl = TextEditingController(
        text:
            'بطاقة رقم قومي: 29805120102345\nرقم الهاتف: 01098765432\nالمبلغ المطلوب: 3500 جنيه مصري',
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
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
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
              const Text(
                'الاستخراج الذكي والقراءة الصوتية',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'اختر مستنداً لاستخراج بيانات الرقم القومي المصري، الهواتف، وتوليد جهات الاتصال vCard:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
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
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        _extractFromDocument(d);
                      },
                    );
                  },
                ),
              ),
            ],
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.firstOrNull?.path;
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

      if (splitRes != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم فصل صفحتين بنجاح (يمين ويسار) وتسوية الانحناءات محلياً!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فصل الكتاب. تأكد من وضوح الصورة وتوسط الكتاب.'),
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

  void _showSimpleInfoDialog({
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ── UI Build ──

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tools = _filteredTools;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مركز الأدوات',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'تبديل الوضع الليلي',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () => ref
                .read(userPreferencesControllerProvider.notifier)
                .toggleDarkMode(),
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Search Input
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'ابحث في الأدوات (حكومي، إكسل، pdf، خزنة...)...',
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

              // Filter Category Chips
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: ToolCategory.values.map((cat) {
                      final isSelected = _selectedCategory == cat;
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
                            cat.label,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
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

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // Tool Cards
              if (tools.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 56,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد أداة مطابقة لكلمات البحث',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final tool = tools[index];
                        return _buildToolCard(
                          context: context,
                          tool: tool,
                          isDark: isDark,
                          palette: palette,
                        );
                      },
                      childCount: tools.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),

          if (_isProcessing)
            Container(
              color: Colors.black45,
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
    );
  }

  Widget _buildToolCard({
    required BuildContext context,
    required ToolItem tool,
    required bool isDark,
    required AppThemePalette palette,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _onToolSelected(tool),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tool Icon Box
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: tool.accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    tool.icon,
                    color: tool.accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Tool Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: tool.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tool.badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: tool.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tool.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tool.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.68),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
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
