import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/models/pending_upload.dart';
import '../../../../shared/models/scan_page.dart';
import '../../../../shared/providers/providers.dart';
import '../government_documents_screen.dart';
import '../scanner_session_screen.dart';
import '../tools_hub_screen.dart';
import '../vault_screen.dart';
import '../id_card_a4_screen.dart';
import '../notebook_lines_remover_screen.dart';
import '../object_counter_screen.dart';
import '../anti_moire_whiteboard_screen.dart';

/// An Apple Human Interface Guidelines bottom navigation bar featuring:
/// - Frosted glass blur backdrop filter
/// - 4 balanced tabs: المستندات, الأدوات, الهوية, الخزنة
/// - Prominent elevated Center Scan Camera Button
/// - Instant tap to scan and long-press quick-actions sheet
class AppleBottomNavBar extends ConsumerWidget {
  const AppleBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onScanTap,
  });

  /// 0: Library (المستندات)
  /// 1: Tools Hub (الأدوات)
  /// 2: Official ID Studio (الهوية)
  /// 3: Secret Vault (الخزنة)
  final int currentIndex;

  /// Custom scan action, or null to launch default camera scanner session.
  final VoidCallback? onScanTap;

  Future<void> _handleScanAction(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    if (onScanTap != null) {
      onScanTap!();
      return;
    }

    try {
      await ref.read(scanSessionControllerProvider.notifier).startNewEmptySession();
      if (!context.mounted) return;
      await Navigator.of(context).push<PendingUpload>(
        MaterialPageRoute(
          builder: (_) => const ScannerSessionScreen(),
        ),
      );
      if (!context.mounted) return;
      ref.read(pendingUploadsControllerProvider.notifier).refresh();
    } catch (_) {}
  }

  void _onTabTapped(BuildContext context, int index) {
    if (index == currentIndex) {
      HapticFeedback.selectionClick();
      return;
    }

    HapticFeedback.lightImpact();

    if (index == 0) {
      // Pop all until home library screen
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final Widget targetScreen;
    switch (index) {
      case 1:
        targetScreen = const ToolsHubScreen();
        break;
      case 2:
        targetScreen = const GovernmentDocumentsScreen();
        break;
      case 3:
        targetScreen = const VaultScreen();
        break;
      default:
        return;
    }

    if (currentIndex == 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => targetScreen,
          transitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final palette = Theme.of(context).colorScheme;
    final activeColor = palette.primary;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: EdgeInsets.only(
            bottom: bottomPadding > 0 ? bottomPadding : 6,
            top: 4,
            left: 8,
            right: 8,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xE6141416)
                : const Color(0xF2FFFFFF),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Tab 0: المستندات
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  label: 'المستندات',
                  icon: Icons.folder_outlined,
                  activeIcon: Icons.folder_rounded,
                  isSelected: currentIndex == 0,
                  activeColor: activeColor,
                  isDark: isDark,
                  onTap: () => _onTabTapped(context, 0),
                ),
              ),

              // Tab 1: الأدوات
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  label: 'الأدوات',
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  isSelected: currentIndex == 1,
                  activeColor: activeColor,
                  isDark: isDark,
                  onTap: () => _onTabTapped(context, 1),
                ),
              ),

              // ── Center Action Button: المسح الضوئي ──
              _buildCenterScanButton(context, ref, activeColor),

              // Tab 2: الهوية
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  label: 'الهوية',
                  icon: Icons.badge_outlined,
                  activeIcon: Icons.badge_rounded,
                  isSelected: currentIndex == 2,
                  activeColor: activeColor,
                  isDark: isDark,
                  onTap: () => _onTabTapped(context, 2),
                ),
              ),

              // Tab 3: الخزنة
              Expanded(
                child: _buildNavItem(
                  index: 3,
                  label: 'الخزنة',
                  icon: Icons.lock_outline_rounded,
                  activeIcon: Icons.lock_rounded,
                  isSelected: currentIndex == 3,
                  activeColor: activeColor,
                  isDark: isDark,
                  onTap: () => _onTabTapped(context, 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterScanButton(
    BuildContext context,
    WidgetRef ref,
    Color activeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => _handleScanAction(context, ref),
        onLongPress: () => _showQuickActionsSheet(context, ref),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF007AFF),
                    Color(0xFF0056D2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.38),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'مسح',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF007AFF),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickActionsSheet(BuildContext context, WidgetRef ref) async {
    HapticFeedback.heavyImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xE61C1C1E) : const Color(0xF2FFFFFF),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF545458) : const Color(0xFFC7C7CC),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.flash_on_rounded,
                          color: Color(0xFF007AFF),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إجراءات المسح السريعة',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          Text(
                            'اختر نمط المسح أو استيراد ملفات',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.document_scanner_rounded,
                    color: const Color(0xFF007AFF),
                    title: 'مسح مستند ذكي (كاميرا)',
                    subtitle: 'كشف تلقائي للحواف وفلاتر تباين فائقة',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _handleScanAction(context, ref);
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.badge_rounded,
                    color: const Color(0xFF5856D6),
                    title: 'بطاقة هوية وش وظهر A4 (مقياس 1:1)',
                    subtitle: 'دمج بالأبعاد الطبيعية الحقيقية مع علامة أمنية وطباعة فورية',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const IdCardA4Screen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.border_color_rounded,
                    color: const Color(0xFF007AFF),
                    title: 'إزالة خطوط الدفاتر والشبكات 📓',
                    subtitle: 'تبييض ورق الكشاكيل وحذف التسطير مع إبقاء خط اليد',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotebookLinesRemoverScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.pin_rounded,
                    color: const Color(0xFFFF9500),
                    title: 'عداد العناصر والأشياء التلقائي 🔢',
                    subtitle: 'عد الأنابيب، الكراتين، والأدوية وتقرير جرد PDF',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ObjectCounterScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.screenshot_monitor_rounded,
                    color: const Color(0xFF007AFF),
                    title: 'مزيل تموجات الشاشات والسبورة 🖥️',
                    subtitle: 'إزالة خطوط الشاشة ولمعان الضوء لتخرج كصورة أصلية',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AntiMoireWhiteboardScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.table_chart_rounded,
                    color: const Color(0xFF10B981),
                    title: 'مسح واستخراج جدول Excel (.xlsx)',
                    subtitle: 'تفريغ الجداول المطبوعة إلى ملف إكسل حقيقي',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ToolsHubScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.qr_code_scanner_rounded,
                    color: const Color(0xFFFF9500),
                    title: 'مسح باركود ورموز QR',
                    subtitle: 'قراءة وتحليل الرموز والروابط فوريًا',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _handleScanAction(context, ref);
                    },
                  ),
                  _buildQuickActionTile(
                    sheetCtx: sheetCtx,
                    icon: Icons.photo_library_rounded,
                    color: const Color(0xFFFF2D55),
                    title: 'استيراد من ألبوم الصور',
                    subtitle: 'جلب مستندات أو صور من جهازك وتحويلها',
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      await _importFromGallery(context, ref);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({
    required BuildContext sheetCtx,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importFromGallery(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final validPaths = picked.files
          .map((f) => f.path)
          .where((p) => p != null && p.isNotEmpty && File(p).existsSync())
          .cast<String>()
          .toList();
      if (validPaths.isEmpty) return;

      final sessionNotifier = ref.read(scanSessionControllerProvider.notifier);
      await sessionNotifier.startNewEmptySession();

      for (final p in validPaths) {
        await sessionNotifier.addPage(
          ScanPage(
            id: const Uuid().v4(),
            imagePath: p,
            originalPath: p,
            createdAt: DateTime.now(),
          ),
        );
      }

      if (!context.mounted) return;
      await Navigator.of(context).push<PendingUpload>(
        MaterialPageRoute(
          builder: (_) => const ScannerSessionScreen(),
        ),
      );
      if (!context.mounted) return;
      ref.read(pendingUploadsControllerProvider.notifier).refresh();
    } catch (_) {}
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const inactiveColor = Color(0xFF8E8E93);

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: isDark ? 0.22 : 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 21,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
