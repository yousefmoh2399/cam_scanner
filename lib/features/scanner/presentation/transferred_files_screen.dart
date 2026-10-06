import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../data/local_web_drop_service.dart';
import '../data/transferred_files_service.dart';
import 'web_drop_screen.dart';

class TransferredFilesScreen extends StatefulWidget {
  const TransferredFilesScreen({super.key});

  @override
  State<TransferredFilesScreen> createState() => _TransferredFilesScreenState();
}

class _TransferredFilesScreenState extends State<TransferredFilesScreen> {
  final TransferredFilesService _service = TransferredFilesService.instance;
  final LocalWebDropService _webDropService = LocalWebDropService.instance;

  List<TransferredFile> _allFiles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Received, 2: Sent

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final files = await _service.loadFiles();
    if (mounted) {
      setState(() {
        _allFiles = files;
        _isLoading = false;
      });
    }
  }

  List<TransferredFile> get _filteredFiles {
    return _allFiles.where((file) {
      if (_selectedFilter == 1 && !file.isReceived) return false;
      if (_selectedFilter == 2 && !file.isSent) return false;

      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return file.name.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _saveToDownloads(TransferredFile file) async {
    HapticFeedback.mediumImpact();
    final savedPath = await _service.saveToDownloads(file);
    if (!mounted) return;

    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('تم حفظ "${file.name}" في التنزيلات بنجاح!'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF34C759),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الملف في التنزيلات')),
      );
    }
  }

  Future<void> _deleteFile(TransferredFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملف المنقول؟',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('هل تريد حذف "${file.name}" من سجل الملفات المنقولة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.lightImpact();
      await _service.deleteFile(file.id);
      _loadData();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كافة الملفات المنقولة؟',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            'سيتم حذف كافة الملفات المستلمة والمرسلة عبر سيرفر المشاركة نهائياً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.heavyImpact();
      await _service.clearAll();
      _loadData();
    }
  }

  void _shareViaWebDrop(TransferredFile file) {
    HapticFeedback.mediumImpact();
    final drop = SharedDropFile(
      id: 'staged_${DateTime.now().millisecondsSinceEpoch}_${file.name.hashCode}',
      name: file.name,
      filePath: file.filePath,
      fileSize: file.fileSize,
      sharedAt: DateTime.now(),
      mimeType: file.mimeType,
      isFromAppLibrary: false,
    );
    _webDropService.addStagedFile(drop);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ تمت إعادة بث "${file.name}" للكمبيوتر عبر Web Drop'),
        backgroundColor: const Color(0xFF007AFF),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return Icons.image_rounded;
      case '.xlsx':
      case '.xls':
        return Icons.table_chart_rounded;
      case '.docx':
      case '.doc':
        return Icons.description_rounded;
      case '.zip':
      case '.rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return const Color(0xFFFF2D55);
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return const Color(0xFF8B5CF6);
      case '.xlsx':
      case '.xls':
        return const Color(0xFF34C759);
      case '.docx':
      case '.doc':
        return const Color(0xFF007AFF);
      case '.zip':
      case '.rar':
        return const Color(0xFFFF9500);
      default:
        return const Color(0xFF5856D6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final files = _filteredFiles;

    final receivedCount = _allFiles.where((f) => f.isReceived).length;
    final sentCount = _allFiles.where((f) => f.isSent).length;

    return Scaffold(
      appBar: AppBar(
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
              'الملفات المنقولة (Web Drop)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              'منفصلة عن المستندات • حفظ ومشاركة فورية',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'فتح سيرفر المشاركة',
            icon: const Icon(Icons.wifi_tethering_rounded,
                color: Color(0xFF007AFF)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WebDropScreen()),
              );
            },
          ),
          if (_allFiles.isNotEmpty)
            IconButton(
              tooltip: 'مسح الكل',
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs (Segmented bar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E22)
                    : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildTabButton(
                    index: 0,
                    title: 'الكل (${_allFiles.length})',
                    isDark: isDark,
                  ),
                  _buildTabButton(
                    index: 1,
                    title: 'المستلمة 📥 ($receivedCount)',
                    isDark: isDark,
                  ),
                  _buildTabButton(
                    index: 2,
                    title: 'المرسلة 📤 ($sentCount)',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'بحث في الملفات المنقولة...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1C1C1E)
                    : const Color(0xFFF2F2F7),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // File List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : files.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.folder_open_rounded,
                                  color: Color(0xFF007AFF),
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'لا توجد ملفات منقولة حالياً',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'أي ملف ترسله للكمبيوتر أو تستقبله منه سيظهر هنا في صفحة مخصصة دون أن يختلط بالمستندات.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const WebDropScreen()),
                                  );
                                },
                                icon: const Icon(Icons.wifi_tethering_rounded),
                                label: const Text('فتح سيرفر المشاركة الآن'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          itemCount: files.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) {
                            final item = files[idx];
                            return _buildFileCard(item, isDark);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String title,
    required bool isDark,
  }) {
    final isSelected = _selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(TransferredFile item, bool isDark) {
    final icon = _getFileIcon(item.name);
    final iconColor = _getFileColor(item.name);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: File Icon + Info + Quick Actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // File Type Squircle Icon Box
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                ),
                const SizedBox(width: 12),

                // File Name & Direction Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: item.isReceived
                                  ? const Color(0xFF34C759)
                                      .withValues(alpha: 0.12)
                                  : const Color(0xFF007AFF)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.isReceived
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  size: 11,
                                  color: item.isReceived
                                      ? const Color(0xFF34C759)
                                      : const Color(0xFF007AFF),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  item.isReceived
                                      ? 'مستلم من الكمبيوتر'
                                      : 'مُرسل من هاتفك',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: item.isReceived
                                        ? const Color(0xFF34C759)
                                        : const Color(0xFF007AFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.formattedSize,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Top Trailing Actions (Re-broadcast & Delete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'إعادة بث للكمبيوتر عبر Wi-Fi',
                      icon: const Icon(Icons.offline_bolt_rounded,
                          size: 20, color: Color(0xFF007AFF)),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      onPressed: () => _shareViaWebDrop(item),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'حذف الملف',
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: Colors.redAccent),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      onPressed: () => _deleteFile(item),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            const SizedBox(height: 10),

            // Symmetrical 3-Button Action Row (Equal Flex: 1, Height: 40px, Radius: 12px)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        OpenFilex.open(item.filePath);
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text(
                        'معاينة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _saveToDownloads(item),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'حفظ بالهاتف',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Share.shareXFiles([XFile(item.filePath)],
                            subject: item.name);
                      },
                      icon: const Icon(Icons.ios_share_rounded, size: 16),
                      label: const Text(
                        'مشاركة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
