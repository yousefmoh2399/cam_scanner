import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/document_folder.dart';

/// خيارات الألوان والأيقونات المخصصة للمجلدات
class FolderVisualOption {
  const FolderVisualOption({
    required this.key,
    required this.name,
    required this.icon,
  });

  final String key;
  final String name;
  final IconData icon;
}

class FolderColorOption {
  const FolderColorOption({
    required this.name,
    required this.color,
  });

  final String name;
  final Color color;

  int get value => color.toARGB32();
}

class FolderVisualHelper {
  static const Color defaultColor = Color(0xFFF59E0B); // Amber

  static const List<FolderColorOption> availableColors = [
    FolderColorOption(name: 'كهرماني', color: Color(0xFFF59E0B)),
    FolderColorOption(name: 'أزرق', color: Color(0xFF007AFF)),
    FolderColorOption(name: 'زمردي', color: Color(0xFF10B981)),
    FolderColorOption(name: 'بنفسجي', color: Color(0xFF8B5CF6)),
    FolderColorOption(name: 'وردي', color: Color(0xFFEC4899)),
    FolderColorOption(name: 'برتقالي', color: Color(0xFFF97316)),
    FolderColorOption(name: 'سماوي', color: Color(0xFF06B6D4)),
    FolderColorOption(name: 'نيلي', color: Color(0xFF6366F1)),
  ];

  static const List<FolderVisualOption> availableIcons = [
    FolderVisualOption(key: 'folder', name: 'مجلد عام', icon: Icons.folder_rounded),
    FolderVisualOption(key: 'car', name: 'سيارة ومرور', icon: Icons.directions_car_rounded),
    FolderVisualOption(key: 'work', name: 'عمل ووظيفة', icon: Icons.business_center_rounded),
    FolderVisualOption(key: 'home', name: 'عقارات ومنزل', icon: Icons.home_rounded),
    FolderVisualOption(key: 'medical', name: 'صحة وعلاج', icon: Icons.medical_services_rounded),
    FolderVisualOption(key: 'finance', name: 'مالية وفواتير', icon: Icons.account_balance_wallet_rounded),
    FolderVisualOption(key: 'school', name: 'دراسة وشهادات', icon: Icons.school_rounded),
    FolderVisualOption(key: 'passport', name: 'هوية ووثائق', icon: Icons.badge_rounded),
    FolderVisualOption(key: 'contract', name: 'عقود رسمية', icon: Icons.description_rounded),
    FolderVisualOption(key: 'star', name: 'مميز ومهم', icon: Icons.star_rounded),
  ];

  static IconData getIcon(String? iconKey) {
    if (iconKey == null) return Icons.folder_rounded;
    for (final opt in availableIcons) {
      if (opt.key == iconKey) return opt.icon;
    }
    return Icons.folder_rounded;
  }

  static Color getColor(int? colorValue) {
    if (colorValue == null) return defaultColor;
    return Color(colorValue);
  }
}

/// نتيجة نافذة إنشاء أو تعديل تخصيص المجلد
class FolderEditResult {
  const FolderEditResult({
    required this.name,
    required this.colorValue,
    required this.iconKey,
  });

  final String name;
  final int colorValue;
  final String iconKey;
}

/// حوار مخصص لإنشاء وتعديل مظهر المجلد (الاسم، اللون، الأيقونة)
class FolderCustomizationDialog extends StatefulWidget {
  const FolderCustomizationDialog({
    super.key,
    this.initialFolder,
    this.title = 'إنشاء مجلد جديد',
  });

  final DocumentFolder? initialFolder;
  final String title;

  static Future<FolderEditResult?> show({
    required BuildContext context,
    DocumentFolder? initialFolder,
    String title = 'إنشاء مجلد جديد',
  }) {
    HapticFeedback.lightImpact();
    return showDialog<FolderEditResult>(
      context: context,
      builder: (_) => FolderCustomizationDialog(
        initialFolder: initialFolder,
        title: title,
      ),
    );
  }

  @override
  State<FolderCustomizationDialog> createState() =>
      _FolderCustomizationDialogState();
}

class _FolderCustomizationDialogState extends State<FolderCustomizationDialog> {
  late final TextEditingController _nameController;
  late Color _selectedColor;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialFolder?.name ?? '',
    );
    _selectedColor = FolderVisualHelper.getColor(
      widget.initialFolder?.colorValue,
    );
    _selectedIconKey = widget.initialFolder?.iconKey ?? 'folder';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _selectedColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      FolderVisualHelper.getIcon(_selectedIconKey),
                      color: _selectedColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'تخصيص الاسم واللون والأيقونة المعبرة',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Name Field
              TextField(
                controller: _nameController,
                autofocus: widget.initialFolder == null,
                decoration: InputDecoration(
                  labelText: 'اسم المجلد',
                  hintText: 'مثال: سيارات ومرور، فواتير، عقود العمل...',
                  filled: true,
                  fillColor: cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Color Swatches
              const Text(
                'اختر لون المجلد',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: FolderVisualHelper.availableColors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final col = FolderVisualHelper.availableColors[index];
                    final isSelected = col.color.toARGB32() ==
                        _selectedColor.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedColor = col.color);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: col.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: col.color.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              // Icon Selector
              const Text(
                'اختر أيقونة المجلد',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: FolderVisualHelper.availableIcons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final iconOpt = FolderVisualHelper.availableIcons[index];
                    final isSelected = iconOpt.key == _selectedIconKey;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedIconKey = iconOpt.key);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _selectedColor.withValues(alpha: 0.18)
                              : cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? _selectedColor
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              iconOpt.icon,
                              size: 24,
                              color: isSelected
                                  ? _selectedColor
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              iconOpt.name,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? _selectedColor
                                    : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      Navigator.of(context).pop(
                        FolderEditResult(
                          name: name,
                          colorValue: _selectedColor.toARGB32(),
                          iconKey: _selectedIconKey,
                        ),
                      );
                    },
                    child: Text(
                      widget.initialFolder == null ? 'إنشاء المجلد' : 'حفظ التعديل',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
