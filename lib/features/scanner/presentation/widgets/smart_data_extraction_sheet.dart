import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/pending_upload.dart';
import '../../../../shared/providers/providers.dart';
import '../../data/native_scanner_bridge.dart';
import '../../data/smart_field_extractor_service.dart';

/// Interactive modal sheet displaying smart extracted fields from OCR text:
/// - Egyptian National ID decoding (birth date, governorate, gender)
/// - Phone numbers with one-tap copy/call
/// - Emails, dates, and amounts
/// - vCard (.vcf) contact export
/// - Offline TTS speech reader
/// - Document auto-classification tags
class SmartDataExtractionSheet extends ConsumerStatefulWidget {
  const SmartDataExtractionSheet({
    super.key,
    required this.text,
    this.document,
  });

  final String text;
  final PendingUpload? document;

  static Future<void> show({
    required BuildContext context,
    required String text,
    PendingUpload? document,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SmartDataExtractionSheet(
        text: text,
        document: document,
      ),
    );
  }

  @override
  ConsumerState<SmartDataExtractionSheet> createState() =>
      _SmartDataExtractionSheetState();
}

class _SmartDataExtractionSheetState
    extends ConsumerState<SmartDataExtractionSheet> {
  late final ExtractedFields _fields;
  late final String _detectedCategory;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    final extractor = ref.read(smartFieldExtractorServiceProvider);
    _fields = extractor.extractFromText(widget.text);
    _detectedCategory = extractor.detectAutoCategory(widget.text);
  }

  @override
  void dispose() {
    NativeScannerBridge.stopSpeaking();
    super.dispose();
  }

  void _copyToClipboard(String val, String label) {
    Clipboard.setData(ClipboardData(text: val));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ $label: $val'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleSpeech() async {
    if (_isSpeaking) {
      await NativeScannerBridge.stopSpeaking();
      setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      final ok = await NativeScannerBridge.speakText(widget.text, lang: 'ar');
      if (!ok && mounted) {
        setState(() => _isSpeaking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('محرك النطق الصوتي غير متاح حالياً')),
        );
      }
    }
  }

  Future<void> _exportVCard(String phone) async {
    final extractor = ref.read(smartFieldExtractorServiceProvider);
    final name = widget.document?.title ?? 'جهة اتصال مستخرجة';
    final email = _fields.emails.isNotEmpty ? _fields.emails.first : null;
    final vcf = extractor.generateVCard(name, phone, email: email);
    final path = await extractor.saveVCard(vcf, name);
    await Share.shareXFiles([XFile(path)], subject: 'بطاقة جهة اتصال $name');
  }

  Future<void> _applyCategory(String category) async {
    if (widget.document == null) return;
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .updateCategory(widget.document!.id, category);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تصنيف المستند إلى: $category'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.psychology_rounded,
                        color: palette.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الاستخراج والتحليل الذكي',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'بيانات مستخرجة محلياً 100% بدون أي إنترنت',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _isSpeaking ? 'إيقاف النطق' : 'قراءة النص صوتياً (TTS)',
                    icon: Icon(
                      _isSpeaking
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      color: _isSpeaking ? palette.danger : palette.accent,
                    ),
                    onPressed: _toggleSpeech,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // Auto-Category suggestion
                  if (_detectedCategory.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: palette.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: palette.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.category_rounded,
                              color: palette.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'التصنيف التلقائي المقترح: $_detectedCategory',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: palette.success,
                              ),
                            ),
                          ),
                          if (widget.document != null)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _applyCategory(_detectedCategory),
                              child: const Text('تطبيق التصنيف'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. Egyptian National ID ──
                  if (_fields.nationalIds.isNotEmpty) ...[
                    _buildSectionHeader('الرقم القومي المصري (14 رقم)',
                        Icons.credit_card_rounded, const Color(0xFF2563EB)),
                    ..._fields.nationalIds.map((idInfo) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  idInfo.id,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'نسخ الرقم القومي',
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: () =>
                                      _copyToClipboard(idInfo.id, 'الرقم القومي'),
                                ),
                              ],
                            ),
                            const Divider(height: 14),
                            _buildInfoRow(
                              'تاريخ الميلاد:',
                              '${idInfo.birthDate.day}/${idInfo.birthDate.month}/${idInfo.birthDate.year}',
                            ),
                            _buildInfoRow('المحافظة:', idInfo.governorate),
                            _buildInfoRow('النوع:', idInfo.gender),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  // ── 2. Phone Numbers ──
                  if (_fields.phones.isNotEmpty) ...[
                    _buildSectionHeader('أرقام الهواتف', Icons.phone_rounded,
                        palette.success),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _fields.phones.map((phone) {
                        return Chip(
                          avatar: const Icon(Icons.call_rounded, size: 16),
                          label: Text(phone,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          deleteIcon: const Icon(Icons.copy_rounded, size: 16),
                          onDeleted: () =>
                              _copyToClipboard(phone, 'رقم الهاتف'),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.contact_page_rounded, size: 18),
                      label: const Text('تصدير كارت شخصي لجهات الاتصال (.vcf)'),
                      onPressed: () => _exportVCard(_fields.phones.first),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 3. Emails ──
                  if (_fields.emails.isNotEmpty) ...[
                    _buildSectionHeader(
                        'البريد الإلكتروني', Icons.email_rounded, palette.accent),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _fields.emails.map((email) {
                        return ActionChip(
                          avatar: const Icon(Icons.copy_rounded, size: 14),
                          label: Text(email),
                          onPressed: () =>
                              _copyToClipboard(email, 'البريد الإلكتروني'),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 4. Amounts & Totals ──
                  if (_fields.amounts.isNotEmpty) ...[
                    _buildSectionHeader('المبالغ والإجماليات المستخرجة',
                        Icons.payments_rounded, palette.warning),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _fields.amounts.map((amount) {
                        return Chip(
                          label: Text(amount,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          deleteIcon: const Icon(Icons.copy_rounded, size: 16),
                          onDeleted: () => _copyToClipboard(amount, 'المبلغ'),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 5. Dates ──
                  if (_fields.dates.isNotEmpty) ...[
                    _buildSectionHeader(
                        'التواريخ', Icons.calendar_today_rounded, Colors.teal),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _fields.dates.map((date) {
                        return ActionChip(
                          avatar: const Icon(Icons.copy_rounded, size: 14),
                          label: Text(date),
                          onPressed: () => _copyToClipboard(date, 'التاريخ'),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_fields.isEmpty && _detectedCategory.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'لم يتم العثور على أرقام هواتف أو أرقام قومية في النص الممسوح.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),

                  // Full Raw OCR Text viewer
                  ExpansionTile(
                    title: const Text(
                      'عرض النص الكامل المستخرج (OCR)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          widget.text,
                          style: const TextStyle(fontSize: 12.5, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_all_rounded, size: 18),
                        label: const Text('نسخ كامل النص'),
                        onPressed: () =>
                            _copyToClipboard(widget.text, 'النص الكامل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
