import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'in_app_privacy_dialog.dart';

/// نافذة ترحيبية وتعريفية تظهر لأول مرة عند تشغيل التطبيق (First-Run Onboarding)
/// تركز على تعزيز الثقة بمبدأ الخصوصية والأمان الفائق وأهم مميزات التطبيق
class OnboardingWelcomeSheet extends StatelessWidget {
  const OnboardingWelcomeSheet({super.key});

  static const String _prefKey = 'has_seen_onboarding_v1';

  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_prefKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markAsSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }

  static Future<void> show(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const OnboardingWelcomeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryBg = isDark ? const Color(0xFF11141C) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1A1F2C) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF2E384D) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: primaryBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 36,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 42,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),

            // Logo with subtle glow
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            const Text(
              'مرحباً بك في لَـقْـطَـة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'الماسح الضوئي الذكي والأكثر خصوصية لمستنداتك ووثائقك',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),

            const SizedBox(height: 24),

            // 3 Core Pillars
            _buildPillarItem(
              icon: Icons.shield_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'خصوصية مطلقة وأمان عالي',
              description:
                  'كل المستندات، واستخراج النصوص، ومعالجة الصور تتم محلياً بالكامل على هاتفك دون خوادم أو تتبع.',
              cardBg: cardBg,
              borderColor: borderColor,
              textMuted: textMuted,
            ),
            const SizedBox(height: 12),

            _buildPillarItem(
              icon: Icons.document_scanner_rounded,
              iconColor: const Color(0xFF007AFF),
              title: 'مسح ذكي وفائق الدقة',
              description:
                  'كشف تلقائي فوري للحواف، تسوية الانحناءات، إزالة الظلال، وفلاتر احترافية للوثائق والبطاقات.',
              cardBg: cardBg,
              borderColor: borderColor,
              textMuted: textMuted,
            ),
            const SizedBox(height: 12),

            _buildPillarItem(
              icon: Icons.lock_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'خزنة مشفرة ومحرك نصوص OCR',
              description:
                  'تشفير عسكري AES-256 للمستندات الحساسة، بحث لحظي داخل النصوص العربية، ونسخ سحابي مشفر بصفر معرفة.',
              cardBg: cardBg,
              borderColor: borderColor,
              textMuted: textMuted,
            ),

            const SizedBox(height: 26),

            // Start Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await markAsSeen();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  'ابدأ الاستخدام الآن',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Privacy Policy Link
            TextButton(
              onPressed: () {
                InAppPrivacySheet.show(context);
              },
              child: const Text(
                'اطّلع على سياسة الخصوصية والشروط',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillarItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required Color cardBg,
    required Color borderColor,
    required Color textMuted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
