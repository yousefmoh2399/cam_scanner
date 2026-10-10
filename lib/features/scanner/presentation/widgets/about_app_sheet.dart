import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'in_app_privacy_dialog.dart';

/// نافذة "حول التطبيق والخصوصية" بهوية Apple Minimalist
class AboutAppSheet extends StatelessWidget {
  const AboutAppSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AboutAppSheet(),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: primaryBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),

          // App Logo
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/app_icon.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title & Version
          const Text(
            'لَـقْـطَـة (Laqta Scanner)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'الإصدار 1.0.0 (Build 1) • أوفلاين 100%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),

          const SizedBox(height: 18),

          // Feature Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBadge(
                icon: Icons.wifi_off_rounded,
                label: '100% أوفلاين',
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildBadge(
                icon: Icons.lock_rounded,
                label: 'AES-256-GCM',
                color: const Color(0xFF007AFF),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildBadge(
                icon: Icons.block_rounded,
                label: 'بدون إعلانات',
                color: const Color(0xFF8B5CF6),
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 22),

          // Menu Actions
          _buildActionTile(
            icon: Icons.verified_user_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'سياسة الخصوصية والأمان',
            subtitle: 'تعهد عدم جمع البيانات والعزل الأمني الكامل',
            onTap: () {
              Navigator.of(context).pop();
              InAppPrivacySheet.show(context);
            },
            cardBg: cardBg,
            borderColor: borderColor,
            textMuted: textMuted,
          ),

          const SizedBox(height: 10),

          _buildActionTile(
            icon: Icons.share_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'مشاركة التطبيق',
            subtitle: 'رشّح تطبيق "لقطة" لزملائك وأصدقائك',
            onTap: () {
              HapticFeedback.lightImpact();
              Share.share(
                'حمّل تطبيق "لقطة" (Laqta Scanner) - الماسح الضوئي الذكي الأقوى والأكثر أماناً:\n'
                '• يعمل 100% بدون إنترنت وبخصوصية مطلقة\n'
                '• مسح سريع وكشف تلقائي للحواف وفلاتر العقود والوثائق\n'
                '• استخراج فوري للنصوص باللغة العربية (OCR)\n'
                '• خزنة مشفرة عسكرية لحفظ مستنداتك وبطاقاتك بأمان',
                subject: 'تطبيق لقطة - الماسح الضوئي الذكي',
              );
            },
            cardBg: cardBg,
            borderColor: borderColor,
            textMuted: textMuted,
          ),

          const SizedBox(height: 10),

          _buildActionTile(
            icon: Icons.star_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'تقييم التطبيق على المتجر',
            subtitle: 'دعمك بتقييم 5 نجوم يساعدنا على الاستمرار في التطوير',
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('شكراً لدعمك لتطبيق لقطة! سيتم فتح صفحة التقييم فور اعتماد التطبيق بالمتجر.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            cardBg: cardBg,
            borderColor: borderColor,
            textMuted: textMuted,
          ),

          const SizedBox(height: 16),
          Text(
            'صُمم وطُوّر بكل عناية للأمان والإنتاجية الفائقة • جميع الحقوق محفوظة © 2026',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color cardBg,
    required Color borderColor,
    required Color textMuted,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
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
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: textMuted.withValues(alpha: 0.6),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
