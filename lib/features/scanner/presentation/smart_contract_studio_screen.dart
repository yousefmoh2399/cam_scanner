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

  bool _isGenerating = false;
  String? _tafqeetPreview;

  @override
  void initState() {
    super.initState();
    _updateRoleDefaults();
    _updateTafqeet();
    _amountController.addListener(_updateTafqeet);
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
    super.dispose();
  }

  void _updateTafqeet() {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    setState(() {
      _tafqeetPreview = SmartContractService.numberToArabicWords(amt);
    });
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
  }

  Future<void> _generateAndExportContract({required bool saveToLibrary}) async {
    setState(() => _isGenerating = true);
    HapticFeedback.mediumImpact();

    try {
      final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;

      String roleA = 'الطرف الأول';
      String roleB = 'الطرف الثاني';
      switch (_selectedType) {
        case ContractType.residentialLease:
          roleA = 'الطرف الأول (المؤجر)';
          roleB = 'الطرف الثاني (المستأجر)';
          break;
        case ContractType.promissoryNote:
          roleA = 'المقر بما فيه (المستلم)';
          roleB = 'الدائن (المسلِّم)';
          break;
        case ContractType.vehicleSale:
        case ContractType.propertySale:
          roleA = 'الطرف الأول (البائع)';
          roleB = 'الطرف الثاني (المشتري)';
          break;
        case ContractType.nda:
          roleA = 'الطرف المفصح';
          roleB = 'الطرف المتلقي';
          break;
        case ContractType.freelanceService:
          roleA = 'الطرف الأول (العميل)';
          roleB = 'الطرف الثاني (مقدم الخدمة)';
          break;
      }

      final partyA = ContractParty(
        name: _partyAName.text.trim(),
        nationalId: _partyAId.text.trim(),
        phone: _partyAPhone.text.trim(),
        address: _partyAAddress.text.trim(),
        roleTitle: roleA,
      );

      final partyB = ContractParty(
        name: _partyBName.text.trim(),
        nationalId: _partyBId.text.trim(),
        phone: _partyBPhone.text.trim(),
        address: _partyBAddress.text.trim(),
        roleTitle: roleB,
      );

      final partyC = _selectedType == ContractType.promissoryNote &&
              _partyCName.text.trim().isNotEmpty
          ? ContractParty(
              name: _partyCName.text.trim(),
              roleTitle: 'الطرف الثالث (المستفيد)',
            )
          : null;

      final contractData = SmartContractFormData(
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
      );

      final pdfBytes = await _service.generateContractPdf(contractData);

      final dir = await getApplicationDocumentsDirectory();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${_selectedType.titleAr}_$timeStamp.pdf';
      final filePath = p.join(dir.path, fileName);
      final pdfFile = File(filePath);
      await pdfFile.writeAsBytes(pdfBytes, flush: true);

      if (saveToLibrary) {
        final doc = PendingUpload(
          id: 'contract_$timeStamp',
          fileName: fileName,
          filePath: filePath,
          fileSize: pdfBytes.length,
          createdAt: DateTime.now(),
          pageCount: 1,
          thumbnailPath: null,
          pages: [
            ScanPage(
              id: 'p_contract_0',
              imagePath: filePath,
            ),
          ],
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

            const SizedBox(height: 24),

            // ── Generate & Export Button ──
            FilledButton.icon(
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
                _isGenerating ? 'جاري توليد العقد والتوثيق...' : 'توليد وتصدير العقد (PDF قانوني)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
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
}
