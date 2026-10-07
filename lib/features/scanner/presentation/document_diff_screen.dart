import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../data/document_diff_service.dart';

/// Screen for Visual and Textual Document Diff & Comparison (100% Offline).
class DocumentDiffScreen extends ConsumerStatefulWidget {
  const DocumentDiffScreen({
    super.key,
    this.initialDocA,
    this.initialDocB,
  });

  final PendingUpload? initialDocA;
  final PendingUpload? initialDocB;

  @override
  ConsumerState<DocumentDiffScreen> createState() => _DocumentDiffScreenState();
}

class _DocumentDiffScreenState extends ConsumerState<DocumentDiffScreen>
    with SingleTickerProviderStateMixin {
  final DocumentDiffService _diffService = DocumentDiffService();

  String? _pathA;
  String? _nameA;
  String? _pathB;
  String? _nameB;

  late TabController _tabController;

  // Visual Slider State
  double _splitRatio = 0.5; // 0.0 to 1.0

  // Text Diff State
  bool _isComparing = false;
  DocumentDiffResult? _diffResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialDocA != null && widget.initialDocA!.pages.isNotEmpty) {
      _pathA = widget.initialDocA!.pages.first.imagePath;
      _nameA = widget.initialDocA!.fileName;
    }
    if (widget.initialDocB != null && widget.initialDocB!.pages.isNotEmpty) {
      _pathB = widget.initialDocB!.pages.first.imagePath;
      _nameB = widget.initialDocB!.fileName;
    }

    if (_pathA != null && _pathB != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runDiffAnalysis();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument({required bool isDocA}) async {
    HapticFeedback.lightImpact();
    final docs = ref.read(pendingUploadsControllerProvider).value ?? [];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  isDocA ? 'اختر المستند الأول (الأصلي)' : 'اختر المستند الثاني (المعدل)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'قارن النصوص أو الاختلافات البصرية بالذكاء الاصطناعي',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  ),
                ),
                const SizedBox(height: 16),
                // External File Picker Apple Tactile Card
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx, 'file_picker');
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.file_open_rounded, color: Color(0xFF007AFF), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'اختيار ملف من ذاكرة الجهاز',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'مستند PDF أو صورة عالية الدقة',
                                style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF8E8E93)),
                      ],
                    ),
                  ),
                ),
                if (docs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'أو من مكتبة المستندات بالتطبيق (${docs.length}):',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (c, idx) {
                        final d = docs[idx];
                        return InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(ctx, d.id);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: (isDocA ? const Color(0xFF007AFF) : const Color(0xFF34C759))
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.description_rounded,
                                    size: 18,
                                    color: isDocA ? const Color(0xFF007AFF) : const Color(0xFF34C759),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      Text(
                                        '${d.pageCount} صفحة',
                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF8E8E93)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (choice == null || !mounted) return;

    if (choice == 'file_picker') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (res != null && res.files.single.path != null) {
        setState(() {
          if (isDocA) {
            _pathA = res.files.single.path;
            _nameA = res.files.single.name;
          } else {
            _pathB = res.files.single.path;
            _nameB = res.files.single.name;
          }
        });
        _checkAndRunAnalysis();
      }
    } else {
      final selected = docs.firstWhere((d) => d.id == choice);
      if (selected.pages.isNotEmpty) {
        setState(() {
          if (isDocA) {
            _pathA = selected.pages.first.imagePath;
            _nameA = selected.fileName;
          } else {
            _pathB = selected.pages.first.imagePath;
            _nameB = selected.fileName;
          }
        });
        _checkAndRunAnalysis();
      }
    }
  }

  void _checkAndRunAnalysis() {
    if (_pathA != null && _pathB != null) {
      _runDiffAnalysis();
    }
  }

  Future<void> _runDiffAnalysis() async {
    if (_pathA == null || _pathB == null) return;
    setState(() => _isComparing = true);

    try {
      final textA = await _diffService.extractTextOffline(_pathA!);
      final textB = await _diffService.extractTextOffline(_pathB!);

      final result = _diffService.compareTexts(textA, textB);

      if (mounted) {
        setState(() {
          _diffResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء فحص الفروقات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isComparing = false);
    }
  }

  void _shareDiffReport() {
    if (_diffResult == null) return;
    final r = _diffResult!;
    final summary = '''
تقرير مقارنة المستندات (Visual & Text Diff)
----------------------------------------
المستند الأصلي (A): ${_nameA ?? 'مستند 1'}
المستند المعدل (B): ${_nameB ?? 'مستند 2'}

نسبة التطابق: ${r.similarityScore.toStringAsFixed(1)}%
• الكلمات المتطابقة: ${r.unchangedCount}
• الكلمات المضافة (+): ${r.addedCount}
• الكلمات المحذوفة (-): ${r.deletedCount}

تم الفحص بنجاح بدون إنترنت بواسطة تطبيق  .
''';
    Share.share(summary, subject: 'تقرير مقارنة الفروقات بين المستندات');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.appThemePalette;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'مقارنة واكتشاف الفروقات',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          if (_diffResult != null)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'مشاركة التقرير',
              onPressed: _shareDiffReport,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          tabs: const [
            Tab(icon: Icon(Icons.splitscreen_rounded), text: 'المنزلق البصري'),
            Tab(icon: Icon(Icons.difference_rounded), text: 'تحليل الفروقات النصية'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Document Selection Header Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                // Doc A Card
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDocument(isDocA: true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.looks_one_rounded, size: 14, color: Color(0xFF007AFF)),
                              SizedBox(width: 4),
                              Text(
                                'الأصل (A)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _nameA ?? 'اضغط لاختيار المستند',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // VS Icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: palette.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Doc B Card
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDocument(isDocA: false),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF34C759).withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.looks_two_rounded, size: 14, color: Color(0xFF34C759)),
                              SizedBox(width: 4),
                              Text(
                                'المعدل (B)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34C759),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _nameB ?? 'اضغط لاختيار المستند',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Main Content Area (Tabs) ──
          Expanded(
            child: _pathA == null || _pathB == null
                ? _buildEmptyState()
                : _isComparing
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator.adaptive(),
                            SizedBox(height: 16),
                            Text(
                              'جاري فحص المستندات واستخراج الفروقات بدون إنترنت...',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildVisualSplitSlider(),
                          _buildTextDiffAnalysis(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.compare_rounded, size: 54, color: Color(0xFF007AFF)),
            ),
            const SizedBox(height: 16),
            const Text(
              'اختر نسختين للمقارنة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'حدد النسخة الأصلية والنسخة المعدلة من العقد أو المستند لاكتشاف أي تغييرات أو تلاعب في النصوص والأختام بدقة تامة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mode 1: Interactive Visual Split Slider ──
  Widget _buildVisualSplitSlider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            // Background Layer: Document B (Modified)
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(_pathB!),
                    cacheWidth: 1440,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),

            // Clipped Top Layer: Document A (Original)
            Positioned.fill(
              child: ClipRect(
                clipper: _SplitClipper(ratio: _splitRatio),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(
                      File(_pathA!),
                      cacheWidth: 1440,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Draggable Divider Line & Handle
            Positioned(
              left: (w * _splitRatio) - 1.5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                color: const Color(0xFF007AFF),
              ),
            ),

            // Circular Touch Handle
            Positioned(
              left: (w * _splitRatio) - 20,
              top: (h / 2) - 20,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitRatio = (_splitRatio + (details.delta.dx / w)).clamp(0.05, 0.95);
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.code_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

            // Floating Labels
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'الأصل (A)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'المعدل (B)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Mode 2: Text Diff Analysis & Badges ──
  Widget _buildTextDiffAnalysis() {
    if (_diffResult == null) {
      return const Center(child: Text('لا توجد نتائج متوفرة'));
    }

    final r = _diffResult!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Similarity Score Dashboard Card ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E24) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'نسبة التطابق بين النسختين',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    Text(
                      '${r.similarityScore.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: r.similarityScore > 85
                            ? const Color(0xFF34C759)
                            : (r.similarityScore > 60
                                ? const Color(0xFFFF9500)
                                : const Color(0xFFFF2D55)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (r.similarityScore / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation(
                      r.similarityScore > 85
                          ? const Color(0xFF34C759)
                          : (r.similarityScore > 60
                              ? const Color(0xFFFF9500)
                              : const Color(0xFFFF2D55)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Stat counters
                Row(
                  children: [
                    _buildStatPill(
                      label: 'مضافة (+)',
                      count: r.addedCount,
                      color: const Color(0xFF34C759),
                    ),
                    const SizedBox(width: 8),
                    _buildStatPill(
                      label: 'محذوفة (-)',
                      count: r.deletedCount,
                      color: const Color(0xFFFF2D55),
                    ),
                    const SizedBox(width: 8),
                    _buildStatPill(
                      label: 'متطابقة (=)',
                      count: r.unchangedCount,
                      color: const Color(0xFF007AFF),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Highlighted Diff Output ──
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'النصوص المكتشفة مع إبراز الفروقات:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E24) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Wrap(
              spacing: 5,
              runSpacing: 6,
              children: r.segments.map((seg) {
                if (seg.text == '\n') {
                  return const SizedBox(width: double.infinity, height: 8);
                }

                switch (seg.type) {
                  case DiffType.insert:
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF34C759).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        '+ ${seg.text}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    );
                  case DiffType.delete:
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '- ${seg.text}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          color: Color(0xFFFF2D55),
                        ),
                      ),
                    );
                  case DiffType.equal:
                    return Text(
                      seg.text,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    );
                }
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required int count,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  const _SplitClipper({required this.ratio});
  final double ratio;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * ratio, size.height);
  }

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) => oldClipper.ratio != ratio;
}
