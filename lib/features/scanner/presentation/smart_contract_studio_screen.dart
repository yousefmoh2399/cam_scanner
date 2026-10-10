import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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
  int _currentStep = 0; // 0: Parties, 1: Details & Clauses, 2: Paper & Export

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
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(ctx);
                          OpenFilex.open(filePath);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          foregroundColor: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Theme.of(ctx).brightness == Brightness.dark
                                  ? Colors.white12
                                  : Colors.black12,
                              width: 0.8,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        label: const Text(
                          'معاينة العقد',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(ctx);
                          Share.shareXFiles([XFile(filePath)], subject: fileName);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text(
                          'مشاركة العقد',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                    Printing.layoutPdf(
                      name: fileName,
                      onLayout: (_) async => pdfBytes,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    foregroundColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1C1C1E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? Colors.white12
                            : Colors.black12,
                        width: 0.8,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text(
                    'طباعة العقد مباشرة (AirPrint)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getContractIcon(ContractType type) {
    switch (type) {
      case ContractType.residentialLease:
        return Icons.home_work_rounded;
      case ContractType.promissoryNote:
        return Icons.receipt_long_rounded;
      case ContractType.vehicleSale:
        return Icons.directions_car_rounded;
      case ContractType.propertySale:
        return Icons.domain_rounded;
      case ContractType.nda:
        return Icons.lock_person_rounded;
      case ContractType.freelanceService:
        return Icons.handshake_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'استوديو العقود والقوالب الذكية',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
            const Text(
              'صيغ قانونية محكمة • توثيق وتفقيد مالي 100% أوفلاين',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Apple 3-Step Wizard Indicator ──
          _buildStepIndicator(isDark),

          // ── Active Step Body ──
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildCurrentStepView(isDark),
              ),
            ),
          ),

          // ── Bottom Step Navigation Bar ──
          _buildBottomStepBar(isDark),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    final steps = [
      (0, 'أطراف العقد', Icons.group_rounded),
      (1, 'البيانات والبنود', Icons.description_rounded),
      (2, 'الورق والمعاينة', Icons.picture_as_pdf_rounded),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: steps.map((item) {
          final idx = item.$1;
          final title = item.$2;
          final icon = item.$3;
          final isActive = _currentStep == idx;
          final isPast = _currentStep > idx;

          return Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _currentStep = idx);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF007AFF).withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? const Color(0xFF007AFF)
                            : (isPast
                                ? const Color(0xFF34C759)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08))),
                      ),
                      child: Center(
                        child: isPast
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : Icon(
                                icon,
                                size: 13,
                                color: isActive
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black54),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              isActive ? FontWeight.w800 : FontWeight.w600,
                          color: isActive
                              ? const Color(0xFF007AFF)
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentStepView(bool isDark) {
    switch (_currentStep) {
      case 0:
        return KeyedSubtree(
          key: const ValueKey('step_0_parties'),
          child: _buildStepParties(isDark),
        );
      case 1:
        return KeyedSubtree(
          key: const ValueKey('step_1_details'),
          child: _buildStepDetailsAndClauses(isDark),
        );
      case 2:
      default:
        return KeyedSubtree(
          key: const ValueKey('step_2_export'),
          child: _buildStepPaperAndPreview(isDark),
        );
    }
  }

  Widget _buildStepParties(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Contract Type Selector Segmented Carousel ──
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            'نوع العقد أو النموذج القانوني',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: ContractType.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, idx) {
              final t = ContractType.values[idx];
              final isSelected = t == _selectedType;
              final icon = _getContractIcon(t);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedType = t;
                      _updateRoleDefaults();
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06)),
                        width: 0.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: isSelected ? Colors.white : const Color(0xFF007AFF),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          t.titleAr,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // ── Selected Contract Description Inset Card ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.gavel_rounded, color: Color(0xFF007AFF), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedType.titleAr,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedType.subtitleAr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

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

        const SizedBox(height: 14),

        // ── Party B Section ──
        _buildSectionCard(
          title: _selectedType == ContractType.residentialLease
              ? 'بيانات المستأجر (الطرف الثاني)'
              : (_selectedType == ContractType.promissoryNote
                  ? 'بيانات المسلِّم (الدائن)'
                  : 'بيانات الطرف الثاني (المشتري / مقدم الخدمة)'),
          icon: Icons.person_outline_rounded,
          color: const Color(0xFF007AFF),
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
          const SizedBox(height: 14),
          _buildSectionCard(
            title: 'الطرف الثالث (المستلم إليه النهائي)',
            icon: Icons.account_circle_outlined,
            color: const Color(0xFF007AFF),
            children: [
              _buildTextField(
                controller: _partyCName,
                label: 'اسم المستلم إليه (لتسليمه للسيد/ ...)',
                icon: Icons.person_add_alt_rounded,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStepDetailsAndClauses(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Contract Details & Financials ──
        _buildSectionCard(
          title: 'البيانات المالية وموضوع الاتفاق',
          icon: Icons.payments_rounded,
          color: const Color(0xFF007AFF),
          children: [
            _buildTextField(
              controller: _descriptionController,
              label: 'وصف العين / المبيع / نطاق العمل بالتفصيل',
              icon: Icons.description_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
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
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB45309).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 16, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تفقيد المبلغ: ${_tafqeetPreview!}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
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
              label: 'شروط أو بنود إضافية خاصة (اختياري)',
              icon: Icons.edit_note_rounded,
              maxLines: 2,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Editable Clauses Editor ──
        _buildClausesEditor(),
      ],
    );
  }

  Widget _buildStepPaperAndPreview(bool isDark) {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Paper Background Color Selector ──
        _buildPaperColorSelector(),

        const SizedBox(height: 14),

        // ── Quick Contract Summary Card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.fact_check_rounded,
                        size: 17, color: Color(0xFF34C759)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ملخص العقد الجاهز للتصدير',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSummaryRow('نوع النموذج:', _selectedType.titleAr),
              _buildSummaryRow(
                'الطرف الأول:',
                _partyAName.text.trim().isEmpty
                    ? 'لم يتم التحديد'
                    : _partyAName.text.trim(),
              ),
              _buildSummaryRow(
                'الطرف الثاني:',
                _partyBName.text.trim().isEmpty
                    ? 'لم يتم التحديد'
                    : _partyBName.text.trim(),
              ),
              if (_selectedType == ContractType.promissoryNote &&
                  _partyCName.text.trim().isNotEmpty)
                _buildSummaryRow('المستفيد النهائي:', _partyCName.text.trim()),
              _buildSummaryRow(
                'القيمة المالية:',
                amt > 0 ? '$amt ج.م (${_tafqeetPreview ?? ""})' : 'غير محدد',
              ),
              _buildSummaryRow('عدد البنود القانونية:',
                  '${_clauseControllers.length} بنداً معتمداً'),
              _buildSummaryRow('خلفية الورقة:', _selectedPaperColor.label),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Direct Actions Card ──
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _previewContractPdf,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    'معاينة العقد',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
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
                      : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text(
                    _isGenerating ? 'جارٍ التوليد...' : 'تصدير PDF وحفظ',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStepBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _currentStep--);
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text(
                      'السابق',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: _currentStep == 0 ? 1 : 1,
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    if (_currentStep < 2) {
                      setState(() => _currentStep++);
                    } else {
                      _generateAndExportContract(saveToLibrary: true);
                    }
                  },
                  icon: Icon(
                    _currentStep < 2
                        ? Icons.arrow_forward_rounded
                        : Icons.picture_as_pdf_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _currentStep == 0
                        ? 'متابعة إلى البيانات والبنود'
                        : (_currentStep == 1
                            ? 'متابعة إلى المعاينة والورق'
                            : (_isGenerating ? 'جارٍ التوليد...' : 'تصدير العقد (PDF)')),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: const Color(0xFF007AFF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  maxLines: 1,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8E8E93),
        ),
        prefixIcon: Icon(icon, size: 17, color: const Color(0xFF8E8E93)),
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.2),
        ),
      ),
    );
  }

  Widget _buildPaperColorSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.palette_outlined, size: 17, color: Color(0xFF007AFF)),
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
                      'اختر لون الورقة المناسب للطباعة والتوثيق',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF8E8E93)),
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
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.black.withValues(alpha: 0.12),
                        width: isSelected ? 2 : 0.8,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                              size: 16, color: Color(0xFF007AFF))
                        else
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        const SizedBox(height: 5),
                        Text(
                          color.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.format_list_numbered_rounded,
                    size: 17, color: Color(0xFF007AFF)),
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
                      'يمكنك تعديل أي بند أو حذفه أو إضافة بنود مخصصة',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF8E8E93)),
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
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF007AFF),
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
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _clauseControllers.add(TextEditingController(
                      text: 'البند ${(_clauseControllers.length + 1)}: اتفق الطرفان على ...'));
                });
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('إضافة بند جديد للعقد',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
