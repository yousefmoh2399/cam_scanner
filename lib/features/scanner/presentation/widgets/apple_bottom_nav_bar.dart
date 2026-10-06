import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/pending_upload.dart';
import '../../../../shared/providers/providers.dart';
import '../government_documents_screen.dart';
import '../scanner_session_screen.dart';
import '../tools_hub_screen.dart';
import '../vault_screen.dart';

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
            left: 12,
            right: 12,
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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Tab 0: المستندات
              _buildNavItem(
                index: 0,
                label: 'المستندات',
                icon: Icons.folder_outlined,
                activeIcon: Icons.folder_rounded,
                isSelected: currentIndex == 0,
                activeColor: activeColor,
                isDark: isDark,
                onTap: () => _onTabTapped(context, 0),
              ),

              // Tab 1: الأدوات
              _buildNavItem(
                index: 1,
                label: 'الأدوات',
                icon: Icons.grid_view_outlined,
                activeIcon: Icons.grid_view_rounded,
                isSelected: currentIndex == 1,
                activeColor: activeColor,
                isDark: isDark,
                onTap: () => _onTabTapped(context, 1),
              ),

              // ── Center Action Button: المسح الضوئي ──
              _buildCenterScanButton(context, ref, activeColor),

              // Tab 2: الهوية
              _buildNavItem(
                index: 2,
                label: 'الهوية',
                icon: Icons.badge_outlined,
                activeIcon: Icons.badge_rounded,
                isSelected: currentIndex == 2,
                activeColor: activeColor,
                isDark: isDark,
                onTap: () => _onTabTapped(context, 2),
              ),

              // Tab 3: الخزنة
              _buildNavItem(
                index: 3,
                label: 'الخزنة',
                icon: Icons.lock_outline_rounded,
                activeIcon: Icons.lock_rounded,
                isSelected: currentIndex == 3,
                activeColor: activeColor,
                isDark: isDark,
                onTap: () => _onTabTapped(context, 3),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
