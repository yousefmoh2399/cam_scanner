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
              'الملفات المنقولة',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${_allFiles.length} ملف • Web Drop أوفلاين',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WebDropScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  size: 18,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
          ),
          if (_allFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: InkWell(
                onTap: _clearAll,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFFE5E5EA),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_sweep_rounded,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Apple Inset Segmented Tabs ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E)
                    : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 0.5,
                ),
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

          // ── Apple Inset Search Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'البحث في الملفات المنقولة...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF8E8E93),
                    size: 18,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.cancel_rounded,
                            color: Color(0xFF8E8E93),
                            size: 16,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFE5E5EA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF007AFF),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),

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
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.folder_open_rounded,
                                  color: Color(0xFF007AFF),
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'لا توجد ملفات منقولة حالياً',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'أي ملف ترسله للكمبيوتر أو تستقبله منه سيظهر هنا في صفحة مخصصة دون أن يختلط بالمستندات.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8E8E93),
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
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF007AFF),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
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
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF1C1C1E))
                  : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }

  void _showFileOptionsSheet(TransferredFile file) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = _getFileIcon(file.name);
    final iconColor = _getFileColor(file.name);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Drag Handle
                  Container(
                    width: 36,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E8E93).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  // Header Info Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: iconColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${file.formattedSize} • ${file.isReceived ? "مستلم من الكمبيوتر" : "مُرسل من الهاتف"}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF8E8E93),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions Group
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.visibility_rounded,
                              color: Color(0xFF007AFF)),
                          title: const Text('معاينة وفتح الملف',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          onTap: () {
                            Navigator.pop(ctx);
                            OpenFilex.open(file.filePath);
                          },
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 52,
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        ),
                        ListTile(
                          leading: const Icon(Icons.download_rounded,
                              color: Color(0xFF34C759)),
                          title: const Text('حفظ نسخة في مجلد التنزيلات',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _saveToDownloads(file);
                          },
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 52,
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        ),
                        ListTile(
                          leading: const Icon(Icons.ios_share_rounded,
                              color: Color(0xFF007AFF)),
                          title: const Text('مشاركة عبر التطبيقات',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          onTap: () {
                            Navigator.pop(ctx);
                            Share.shareXFiles([XFile(file.filePath)],
                                subject: file.name);
                          },
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 52,
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        ),
                        ListTile(
                          leading: const Icon(Icons.wifi_tethering_rounded,
                              color: Color(0xFFFF9500)),
                          title: const Text('إعادة بث إلى الكمبيوتر (Web Drop)',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _shareViaWebDrop(file);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Destructive Group
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      title: const Text(
                        'حذف الملف من السجل',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Colors.redAccent,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _deleteFile(file);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileCard(TransferredFile item, bool isDark) {
    final icon = _getFileIcon(item.name);
    final iconColor = _getFileColor(item.name);

    return Container(
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            OpenFilex.open(item.filePath);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Squircle Icon Box
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),

                    // File metadata
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
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: item.isReceived
                                      ? const Color(0xFF34C759)
                                          .withValues(alpha: 0.12)
                                      : const Color(0xFF007AFF)
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  item.isReceived ? 'مستلم 📥' : 'مُرسل 📤',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: item.isReceived
                                        ? const Color(0xFF34C759)
                                        : const Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item.formattedSize,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF8E8E93),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Trailing more options button
                    IconButton(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Color(0xFF8E8E93),
                        size: 20,
                      ),
                      tooltip: 'خيارات الملف',
                      onPressed: () => _showFileOptionsSheet(item),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
                const SizedBox(height: 8),

                // Balanced Equal 2-Button Action Row (Height: 38px, Radius: 10px)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            OpenFilex.open(item.filePath);
                          },
                          icon: const Icon(Icons.visibility_rounded, size: 15),
                          label: const Text(
                            'معاينة الملف',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showFileOptionsSheet(item);
                          },
                          icon: const Icon(Icons.more_vert_rounded, size: 15),
                          label: const Text(
                            'المزيد من الخيارات',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
        ),
      ),
    );
  }
}
