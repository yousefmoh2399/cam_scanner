import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';

class AccentThemeOption {
  const AccentThemeOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.color,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color color;
}

const List<AccentThemeOption> kAccentThemes = [
  AccentThemeOption(
    id: 'default',
    name: 'أزرق أبل الكلاسيكي',
    subtitle: 'لون نظام iOS الكلاسيكي الأنيق',
    color: Color(0xFF007AFF),
  ),
  AccentThemeOption(
    id: 'titanium',
    name: 'تيتانيوم رمادي',
    subtitle: 'مستوحى من تصميم iPhone 15/16 Pro',
    color: Color(0xFF8E8E93),
  ),
  AccentThemeOption(
    id: 'violet',
    name: 'بنفسجي ملكي',
    subtitle: 'لمسة فاخرة وعصرية لواجهة التطبيق',
    color: Color(0xFF5856D6),
  ),
  AccentThemeOption(
    id: 'emerald',
    name: 'أخضر زمردي',
    subtitle: 'لون حيوي ومريح للقراءة والمستندات',
    color: Color(0xFF34C759),
  ),
  AccentThemeOption(
    id: 'sunset',
    name: 'برتقالي أبل',
    subtitle: 'مظهر جريء ودافئ مستوحى من Apple Watch',
    color: Color(0xFFFF9500),
  ),
];

Future<void> showThemeSelectionSheet(BuildContext context, WidgetRef ref) async {
  HapticFeedback.lightImpact();
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => Consumer(
      builder: (ctx, watchRef, _) {
        final prefs = watchRef.watch(userPreferencesControllerProvider).valueOrNull;
        final currentThemeId = prefs?.accentThemeId ?? 'default';

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.palette_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ألوان التمييز (Accent Themes)',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            Text(
                              'اختر لون التطبيق الأساسي بنمط Apple',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF8E8E93)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ...kAccentThemes.map((theme) {
                      final isSelected = currentThemeId == theme.id;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.color.withValues(alpha: isDark ? 0.18 : 0.08)
                              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? theme.color
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                            width: isSelected ? 1.5 : 0.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              watchRef
                                  .read(userPreferencesControllerProvider.notifier)
                                  .setAccentTheme(theme.id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: theme.color,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: theme.color.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          theme.name,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                            color: isSelected ? theme.color : null,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          theme.subtitle,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.radio_button_checked_rounded,
                                      size: 19,
                                      color: theme.color,
                                    )
                                  else
                                    Icon(
                                      Icons.radio_button_off_rounded,
                                      size: 19,
                                      color: isDark ? Colors.white24 : Colors.black26,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
