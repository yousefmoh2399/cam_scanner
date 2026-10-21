import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/motion_tokens.dart';

/// نافذة سياسة الخصوصية والأمان المدمجة داخل التطبيق (In-App Privacy Policy)
/// متوافقة 100% مع متطلبات Google Play Data Safety و Apple App Store Review
class InAppPrivacySheet extends StatelessWidget {
  const InAppPrivacySheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const InAppPrivacySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryBg = isDark ? const Color(0xFF14171F) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1C2230) : const Color(0xFFF6F8FA);
    final borderColor = isDark ? const Color(0xFF2D3548) : const Color(0xFFE5E9F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: primaryBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Handle Bar ──
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // ── Top Bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'سياسة الخصوصية والأمان',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'لقطة (Laqta Scanner) • حماية وخصوصية تامة',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // ── Scrollable Body ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Summary Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF0F2B1E), const Color(0xFF133E2B)]
                              : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Color(0xFF10B981),
                            size: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تعهد الخصوصية الصارم (Zero-Knowledge)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'لا نقوم بجمع أو تخزين أو مشاركة أي مستندات أو بيانات شخصية. جميع عمليات المسح والذكاء الاصطناعي وOCR تتم 100% داخل هاتفك بدون خوادم خارجية.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Section 1: Data handled
                    _buildSectionCard(
                      icon: Icons.folder_shared_rounded,
                      iconColor: const Color(0xFF3B82F6),
                      title: '1. أين تُحفظ مستنداتك وصورك؟',
                      body:
                          'تُحفظ جميع المستندات والصور وملفات PDF حصرياً في مساحة التخزين الداخلية المعزولة لتطبيق لقطة على جهازك (App Sandboxed Storage).\n\nلا يمكن لأي تطبيق آخر، ولا لمطور التطبيق، ولا لأي طرف ثالث الوصول إلى ملفاتك أو قراءتها.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textMuted: textMuted,
                    ),

                    const SizedBox(height: 12),

                    // Section 2: OCR & On-Device Processing
                    _buildSectionCard(
                      icon: Icons.document_scanner_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      title: '2. التعرف الضوئي ومعالجة الصور (OCR)',
                      body:
                          'يستخدم التطبيق محركات Tesseract LSTM و OpenCV و Apple Vision / ML Kit مدمجة كلياً لمعالجة المستندات على جهازك.\n\nلا يتم إرسال أي صورة أو نص أو رقم بطاقة أو عقد إلى أي سحابة أو خدمة خارجية. المعالجة فورية وتتم بالكامل داخل معالج هاتفك.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textMuted: textMuted,
                    ),

                    const SizedBox(height: 12),

                    // Section 3: Vault & Encryption
                    _buildSectionCard(
                      icon: Icons.lock_outline_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: '3. الخزنة السرية والتشفير العسكري',
                      body:
                          'تُشفر مستندات الخزنة بمعيار التشفير المتقدم AES-256-GCM مع مفتاح مشتق عبر PBKDF2 (10,000 جولة).\n\nالمفاتيح محمية داخل وحدة الأمان المادية بهاتفك (Android Keystore / iOS Secure Enclave). التطبيق يدعم منع لقطات الشاشة لحماية وثائقك الحساسة.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textMuted: textMuted,
                    ),

                    const SizedBox(height: 12),

                    // Section 4: Cloud Backup
                    _buildSectionCard(
                      icon: Icons.cloud_sync_rounded,
                      iconColor: const Color(0xFF06B6D4),
                      title: '4. النسخ الاحتياطي السحابي المشفر',
                      body:
                          'عند اختيارك تصدير نسخة احتياطية لمزامنتها مع Google Drive أو iCloud، يتم تشفير النسخة بالكامل بكلمة مرورك قبل مغادرة الهاتف.\n\nلا تستطيع Google أو Apple أو أي طرف ثالث فك تشفير نسختك الاحتياطية لأن مفتاح فك التشفير غير معروف إلا لك وحدك (Zero-Knowledge).',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textMuted: textMuted,
                    ),

                    const SizedBox(height: 12),

                    // Section 5: Permissions
                    _buildSectionCard(
                      icon: Icons.tune_rounded,
                      iconColor: const Color(0xFFEC4899),
                      title: '5. الصلاحيات المطلوبة وأسبابها',
                      body:
                          '• الكاميرا: لمسح المستندات والبطاقات ضوئياً فقط.\n• معرض الصور: لاستيراد أو تصدير المستندات بناءً على اختيارك اليدوي.\n• البصمة / Face ID: لفتح الخزنة المشفرة وقفل التطبيق محلياً.\n• الشبكة المحلية (Wi-Fi): لميزة WebDrop لنقل المستندات إلى حاسوبك عبر الشبكة المحلية.\n\n*التطبيق لا يطلب: الموقع الجغرافي، الميكروفون، جهات الاتصال، أو معرف الإعلانات.*',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textMuted: textMuted,
                    ),

                    const SizedBox(height: 24),

                    // Share Policy Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text(
                          'مشاركة وثيقة سياسة الخصوصية',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Share.share(
                            'سياسة الخصوصية لتطبيق "لقطة" (Laqta Scanner):\n'
                            'تطبيق مسح ضوئي احترافي فائق الأمان والخصوصية بدون خوادم وبدون جمع أي بيانات.\n'
                            'مستنداتك مشفرة ولا تغادر جهازك إطلاقاً.',
                            subject: 'سياسة الخصوصية - لقطة',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
    required Color cardBg,
    required Color borderColor,
    required Color textMuted,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
