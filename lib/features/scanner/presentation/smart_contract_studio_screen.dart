import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/smart_contract_service.dart';

class SmartContractStudioScreen extends ConsumerStatefulWidget {
  const SmartContractStudioScreen({super.key});

  @override
  ConsumerState<SmartContractStudioScreen> createState() =>
      _SmartContractStudioScreenState();
}

class _SmartContractStudioScreenState
    extends ConsumerState<SmartContractStudioScreen> {
  final SmartContractService _service = SmartContractService();

  ContractType _selectedType = ContractType.residentialLease;

  // Party A Controllers
  final _partyAName = TextEditingController();
  final _partyAId = TextEditingController();
  final _partyAPhone = TextEditingController();
  final _partyAAddress = TextEditingController();

  // Party B Controllers
  final _partyBName = TextEditingController();
  final _partyBId = TextEditingController();
  final _partyBPhone = TextEditingController();
  final _partyBAddress = TextEditingController();

  // Party C Controller (For Promissory Note)
  final _partyCName = TextEditingController();

  // Contract Details
  final _amountController = TextEditingController(text: '5000');
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(text: 'سنة واحدة');
  final _cityController = TextEditingController(text: 'القاهرة');
  final _extraClausesController = TextEditingController();

  ContractPaperColor _selectedPaperColor = ContractPaperColor.white;
  final List<TextEditingController> _clauseControllers = [];

  bool _isGenerating = false;
  String? _tafqeetPreview;

  @override
  void initState() {
    super.initState();
    _updateRoleDefaults();
    _initClausesFromTemplate();
    _updateTafqeet();
    _amountController.addListener(_updateTafqeet);
    _amountController.addListener(_onFinancialsChanged);
    _durationController.addListener(_onFinancialsChanged);
  }

  @override
  void dispose() {
    _partyAName.dispose();
    _partyAId.dispose();
    _partyAPhone.dispose();
    _partyAAddress.dispose();
    _partyBName.dispose();
    _partyBId.dispose();
    _partyBPhone.dispose();
    _partyBAddress.dispose();
    _partyCName.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _cityController.dispose();
    _extraClausesController.dispose();
    for (final c in _clauseControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFinancialsChanged() {
    // If clauses are still unmodified defaults, refresh them with updated numbers
    if (_clauseControllers.isEmpty) {
      _initClausesFromTemplate();
    }
  }

  void _updateTafqeet() {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    setState(() {
      _tafqeetPreview = SmartContractService.numberToArabicWords(amt);
    });
  }

  String _getPartyARole() {
    switch (_selectedType) {
      case ContractType.residentialLease:
        return 'الطرف الأول (المؤجر)';
      case ContractType.promissoryNote:
        return 'المقر بما فيه (المستلم)';
      case ContractType.vehicleSale:
      case ContractType.propertySale:
        return 'الطرف الأول (البائع)';
      case ContractType.nda:
        return 'الطرف المفصح';
      case ContractType.freelanceService:
        return 'الطرف الأول (العميل)';
    }
  }

  String _getPartyBRole() {
    switch (_selectedType) {
      case ContractType.residentialLease:
        return 'الطرف الثاني (المستأجر)';
      case ContractType.promissoryNote:
        return 'الدائن (المسلِّم)';
      case ContractType.vehicleSale:
      case ContractType.propertySale:
        return 'الطرف الثاني (المشتري)';
      case ContractType.nda:
        return 'الطرف المتلقي';
      case ContractType.freelanceService:
        return 'الطرف الثاني (مقدم الخدمة)';
    }
  }

  void _initClausesFromTemplate() {
    for (final c in _clauseControllers) {
      c.dispose();
    }
    _clauseControllers.clear();

    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final dummyData = SmartContractFormData(
      type: _selectedType,
      partyA: ContractParty(
        name: _partyAName.text.trim(),
        nationalId: _partyAId.text.trim(),
        phone: _partyAPhone.text.trim(),
        address: _partyAAddress.text.trim(),
        roleTitle: _getPartyARole(),
      ),
      partyB: ContractParty(
        name: _partyBName.text.trim(),
        nationalId: _partyBId.text.trim(),
        phone: _partyBPhone.text.trim(),
        address: _partyBAddress.text.trim(),
        roleTitle: _getPartyBRole(),
      ),
      partyC: _selectedType == ContractType.promissoryNote
          ? ContractParty(
              name: _partyCName.text.trim(),
              roleTitle: 'الطرف الثالث (المستفيد)',
            )
          : null,
      city: _cityController.text.trim().isEmpty ? 'القاهرة' : _cityController.text.trim(),
      amount: amt,
      currency: 'جنيه مصري',
      itemDescription: _descriptionController.text.trim(),
      duration: _durationController.text.trim(),
    );

    final defaults = SmartContractService.generateDefaultClauses(dummyData);
    for (final clause in defaults) {
      _clauseControllers.add(TextEditingController(text: clause));
    }
  }

  void _updateRoleDefaults() {
    switch (_selectedType) {
      case ContractType.residentialLease:
        _descriptionController.text = 'شقة سكنية بالدور الثالث بالعقار رقم ...';
        break;
      case ContractType.promissoryNote:
        _descriptionController.text = '';
        break;
      case ContractType.vehicleSale:
        _descriptionController.text = 'سيارة ملاكي ماركة ... موديل ... شاسيه ... موتور ... لوحات رقم ...';
        break;
      case ContractType.propertySale:
        _descriptionController.text = 'عقار سكني مكون من ... كائن في ... بمساحة إجمالية ... متراً مربعاً';
        break;
      case ContractType.nda:
        _descriptionController.text = 'مشروع تطوير تقني وتجاري مشترك';
        break;
      case ContractType.freelanceService:
        _descriptionController.text = 'تصميم وبرمجة منصة إلكترونية وتطبيقات هواتف';
        break;
    }
    _initClausesFromTemplate();
  }

  SmartContractFormData _buildContractFormData() {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final partyA = ContractParty(
      name: _partyAName.text.trim(),
      nationalId: _partyAId.text.trim(),
      phone: _partyAPhone.text.trim(),
      address: _partyAAddress.text.trim(),
      roleTitle: _getPartyARole(),
    );

    final partyB = ContractParty(
      name: _partyBName.text.trim(),
      nationalId: _partyBId.text.trim(),
      phone: _partyBPhone.text.trim(),
      address: _partyBAddress.text.trim(),
      roleTitle: _getPartyBRole(),
    );

    final partyC = _selectedType == ContractType.promissoryNote &&
            _partyCName.text.trim().isNotEmpty
        ? ContractParty(
            name: _partyCName.text.trim(),
            roleTitle: 'الطرف الثالث (المستفيد)',
          )
        : null;

    final clauses = _clauseControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return SmartContractFormData(
      type: _selectedType,
      partyA: partyA,
      partyB: partyB,
      partyC: partyC,
      city: _cityController.text.trim().isEmpty ? 'القاهرة' : _cityController.text.trim(),
      amount: amt,
      currency: 'جنيه مصري',
      itemDescription: _descriptionController.text.trim(),
      duration: _durationController.text.trim(),
      extraClauses: _extraClausesController.text.trim(),
      clauses: clauses,
      paperColor: _selectedPaperColor,
    );
  }

  Future<void> _previewContractPdf() async {
    setState(() => _isGenerating = true);
    HapticFeedback.lightImpact();

    try {
      final contractData = _buildContractFormData();
      final pdfBytes = await _service.generateContractPdf(contractData);
      if (!mounted) return;

      await Printing.layoutPdf(
        name: '${_selectedType.titleAr}.pdf',
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء معاينة العقد: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateAndExportContract({required bool saveToLibrary}) async {
    setState(() => _isGenerating = true);
    HapticFeedback.mediumImpact();

    try {
      final contractData = _buildContractFormData();
      final pdfBytes = await _service.generateContractPdf(contractData);

      final dir = await getApplicationDocumentsDirectory();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${_selectedType.titleAr}_$timeStamp.pdf';
      final filePath = p.join(dir.path, fileName);
      final pdfFile = File(filePath);
      await pdfFile.writeAsBytes(pdfBytes, flush: true);

      String? thumbPath;
      try {
        final rasterStream = Printing.raster(pdfBytes, pages: const [0], dpi: 100);
        await for (final rasterPage in rasterStream) {
          final pngBytes = await rasterPage.toPng();
          final thumbFile = File(p.join(dir.path, 'thumb_contract_$timeStamp.png'));
          await thumbFile.writeAsBytes(pngBytes, flush: true);
          thumbPath = thumbFile.path;
          break;
        }
      } catch (e) {
        debugPrint('Could not render contract thumbnail: $e');
      }

      if (saveToLibrary) {
        final doc = PendingUpload(
          id: 'contract_$timeStamp',
          fileName: fileName,
          filePath: filePath,
          fileSize: pdfBytes.length,
          createdAt: DateTime.now(),
          pageCount: 1,
          thumbnailPath: thumbPath,
          pages: thumbPath != null
              ? [
                  ScanPage(
                    id: 'p_contract_0',
                    imagePath: thumbPath,
                  ),
                ]
              : const [],
        );

        await ref.read(pendingUploadsControllerProvider.notifier).addDocument(doc);
      }

      if (!mounted) return;

      _showSuccessDialog(filePath, fileName, pdfBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء إنشاء العقد: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showSuccessDialog(String filePath, String fileName, Uint8List pdfBytes) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.check_circle_rounded, size: 48, color: Color(0xFF34C759)),
              ),
              const SizedBox(height: 14),
              const Text(
                'تم توليد العقد بنجاح بتنسيق قانوني معتمد',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'تم حفظ ملف الـ PDF بمكتبة مستنداتك محلياً 100%',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        OpenFilex.open(filePath);
                      },
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('معاينة العقد'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Share.shareXFiles([XFile(filePath)], subject: fileName);
                      },
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('مشاركة العقد'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Printing.layoutPdf(
                    name: fileName,
                    onLayout: (_) async => pdfBytes,
                  );
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('طباعة العقد مباشرة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.appThemePalette;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'استوديو العقود والقوالب الذكية',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Contract Type Selector Carousel ──
            const Text(
              'اختر نوع العقد أو الاتفاقية:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: ContractType.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, idx) {
                  final t = ContractType.values[idx];
                  final isSelected = t == _selectedType;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedType = t;
                        _updateRoleDefaults();
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? palette.accent
                            : (isDark ? const Color(0xFF1E1E24) : Colors.white),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? palette.accent
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          t.titleAr,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? Colors.white : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 18),

            // ── Selected Contract Description Card ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.gavel_rounded, color: palette.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedType.subtitleAr,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.accent),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── Party A Section ──
            _buildSectionCard(
              title: _selectedType == ContractType.residentialLease
                  ? 'بيانات المؤجر (الطرف الأول)'
                  : (_selectedType == ContractType.promissoryNote
                      ? 'بيانات المستلم (المقر بما فيه)'
                      : 'بيانات الطرف الأول (البائع / العميل)'),
              icon: Icons.person_rounded,
              color: const Color(0xFF007AFF),
              children: [
                _buildTextField(controller: _partyAName, label: 'الاسم بالكامل رباعي', icon: Icons.badge_outlined),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildTextField(controller: _partyAId, label: 'الرقم القومي (14 رقم)', icon: Icons.credit_card_rounded, keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTextField(controller: _partyAPhone, label: 'رقم الهاتف', icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone)),
                  ],
                ),
                const SizedBox(height: 10),
                _buildTextField(controller: _partyAAddress, label: 'محل الإقامة / العنوان بالتفصيل', icon: Icons.home_work_outlined),
              ],
            ),

            const SizedBox(height: 16),

            // ── Party B Section ──
            _buildSectionCard(
              title: _selectedType == ContractType.residentialLease
                  ? 'بيانات المستأجر (الطرف الثاني)'
                  : (_selectedType == ContractType.promissoryNote
                      ? 'بيانات المسلِّم (الدائن)'
                      : 'بيانات الطرف الثاني (المشتري / مقدم الخدمة)'),
              icon: Icons.person_outline_rounded,
              color: const Color(0xFF34C759),
              children: [
                _buildTextField(controller: _partyBName, label: 'الاسم بالكامل رباعي', icon: Icons.badge_outlined),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildTextField(controller: _partyBId, label: 'الرقم القومي', icon: Icons.credit_card_rounded, keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTextField(controller: _partyBPhone, label: 'رقم الهاتف', icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone)),
                  ],
                ),
                const SizedBox(height: 10),
                _buildTextField(controller: _partyBAddress, label: 'محل الإقامة / العنوان بالتفصيل', icon: Icons.home_work_outlined),
              ],
            ),

            // ── Party C (If Promissory Note) ──
            if (_selectedType == ContractType.promissoryNote) ...[
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'الطرف الثالث (المستلم إليه النهائي)',
                icon: Icons.account_circle_outlined,
                color: const Color(0xFFFF9500),
                children: [
                  _buildTextField(
                    controller: _partyCName,
                    label: 'اسم المستلم إليه (لتسليمه للسيد/ ...)',
                    icon: Icons.person_add_alt_rounded,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // ── Contract Details & Financials ──
            _buildSectionCard(
              title: 'البيانات المالية وموضوع الاتفاق',
              icon: Icons.payments_rounded,
              color: const Color(0xFF5856D6),
              children: [
                _buildTextField(
                  controller: _descriptionController,
                  label: 'وصف العين / المبيع / نطاق العمل بالتفصيل',
                  icon: Icons.description_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _amountController,
                        label: 'المبلغ المالي (بالأرقام)',
                        icon: Icons.attach_money_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _durationController,
                        label: 'المدة',
                        icon: Icons.timelapse_rounded,
                      ),
                    ),
                  ],
                ),
                // Auto Tafqeet Preview Badge
                if (_tafqeetPreview != null && _tafqeetPreview!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _tafqeetPreview!,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _cityController,
                  label: 'المدينة / المحافظة',
                  icon: Icons.location_city_rounded,
                ),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _extraClausesController,
                  label: 'بنود أو شروط خاصة إضافية (اختياري)',
                  icon: Icons.edit_note_rounded,
                  maxLines: 2,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Paper Background Color Selector ──
            _buildPaperColorSelector(),

            const SizedBox(height: 16),

            // ── Editable Clauses Editor ──
            _buildClausesEditor(),

            const SizedBox(height: 24),

            // ── Action Buttons (Preview & Generate) ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGenerating ? null : _previewContractPdf,
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('معاينة العقد'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _isGenerating
                        ? null
                        : () => _generateAndExportContract(saveToLibrary: true),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(
                      _isGenerating ? 'جاري توليد العقد...' : 'توليد وتصدير (PDF)',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPaperColorSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF007AFF).withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.palette_outlined, size: 18, color: Color(0xFF007AFF)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لون خلفية ورقة العقد (Paper Background)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      'اختر لون الورقة المناسب لطبيعة العقد والطباعة',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: ContractPaperColor.values.map((color) {
              final isSelected = color == _selectedPaperColor;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPaperColor = color);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Color(color.paperHex),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.black.withValues(alpha: 0.18),
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? const Color(0xFF007AFF).withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.05),
                          blurRadius: isSelected ? 6 : 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                              size: 18, color: Color(0xFF007AFF))
                        else
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          color.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            color: Color(color.textHex),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildClausesEditor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF34C759).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.gavel_rounded,
                    size: 18, color: Color(0xFF34C759)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'بنود وشروط العقد (قابلة للتعديل بالكامل)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      'يمكنك تعديل أي بند أو حذفه أو إضافة بنودك الخاصة',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                tooltip: 'استعادة بنود القالب الافتراضية',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _initClausesFromTemplate());
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._clauseControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final controller = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF34C759),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      maxLines: null,
                      style: const TextStyle(fontSize: 12.5, height: 1.45),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.redAccent),
                    tooltip: 'حذف هذا البند',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        controller.dispose();
                        _clauseControllers.removeAt(idx);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _clauseControllers.add(TextEditingController(
                    text: 'البند ${(_clauseControllers.length + 1)}: اتفق الطرفان على ...'));
              });
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('إضافة بند جديد للعقد'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
