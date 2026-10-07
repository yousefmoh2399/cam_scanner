import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../data/object_counter_service.dart';

/// Screen for counting objects, pipes, pills, boxes, sheets in images offline
/// with interactive touch to add/remove and formal inventory audit report export.
class ObjectCounterScreen extends ConsumerStatefulWidget {
  const ObjectCounterScreen({
    super.key,
    this.initialImagePath,
  });

  final String? initialImagePath;

  @override
  ConsumerState<ObjectCounterScreen> createState() => _ObjectCounterScreenState();
}

class _ObjectCounterScreenState extends ConsumerState<ObjectCounterScreen> {
  final ObjectCounterService _service = const ObjectCounterService();

  Uint8List? _imageBytes;
  final List<CountedItem> _items = [];

  CounterObjectCategory _selectedCategory = CounterObjectCategory.pipesAndTubes;
  double _sensitivity = 0.55;
  bool _isProcessing = false;
  Color _badgeColor = const Color(0xFFFF3B30); // Bright Red default

  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _loadImage(widget.initialImagePath!);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _isProcessing = true;
      _items.clear();
    });

    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
      });
      await _runDetection();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الصورة: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      await _loadImage(result.files.single.path!);
    }
  }

  Future<void> _runDetection() async {
    if (_imageBytes == null) return;
    setState(() => _isProcessing = true);
    HapticFeedback.selectionClick();

    try {
      final res = await _service.detectObjects(
        imageBytes: _imageBytes!,
        category: _selectedCategory,
        sensitivity: _sensitivity,
      );

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(res.items);
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء فحص العناصر: $e')),
      );
    }
  }

  void _onImageTap(TapUpDetails details, BoxConstraints constraints) {
    if (_imageBytes == null) return;
    HapticFeedback.lightImpact();

    final localPos = details.localPosition;
    final normX = (localPos.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final normY = (localPos.dy / constraints.maxHeight).clamp(0.0, 1.0);

    // Check if user tapped near an existing badge to delete it
    const touchThreshold = 0.045;
    int tappedIdx = -1;
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final dist = (it.x - normX).abs() + (it.y - normY).abs();
      if (dist < touchThreshold) {
        tappedIdx = i;
        break;
      }
    }

    setState(() {
      if (tappedIdx >= 0) {
        // Remove item
        _items.removeAt(tappedIdx);
        // Re-index remaining items
        for (int i = 0; i < _items.length; i++) {
          _items[i] = _items[i].copyWith(id: i + 1);
        }
      } else {
        // Add new item
        _items.add(
          CountedItem(
            id: _items.length + 1,
            x: normX,
            y: normY,
          ),
        );
      }
    });
  }

  Future<void> _exportInventoryReport() async {
    if (_imageBytes == null || _items.isEmpty) return;
    HapticFeedback.mediumImpact();

    final inspectorCtrl = TextEditingController();
    final locationCtrl = TextEditingController(text: 'المستودع الرئيسي');
    final notesCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: Color(0xFF007AFF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تصدير تقرير جرد رسمي (PDF)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        'مستند A4 رسمي معتمد وموثق بالصور والأعداد',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: inspectorCtrl,
              decoration: InputDecoration(
                labelText: 'اسم مسؤول الجرد / الفاحص',
                hintText: 'مثلاً: م. أحمد عبد الرحمن',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationCtrl,
              decoration: InputDecoration(
                labelText: 'المستودع / موقع التخزين',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'ملاحظات المعاينة (اختياري)',
                hintText: 'مثلاً: تم فحص الشحنة ومطابقتها لأمر التوريد رقم #4092',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: Text(
                'توليد تقرير الـ PDF (${_items.length} عنصر)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final pdfPath = await _service.generateInventoryReportPdf(
        imageBytes: _imageBytes!,
        items: _items,
        category: _selectedCategory,
        inspectorName: inspectorCtrl.text,
        location: locationCtrl.text,
        notes: notesCtrl.text,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء تقرير الجرد بنجاح!\nالعدد: ${_items.length} عنصر'),
          action: SnackBarAction(
            label: 'فتح التقرير',
            onPressed: () => OpenFilex.open(pdfPath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء التقرير: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'عداد العناصر والأشياء التلقائي',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded),
            tooltip: 'اختيار صورة جديدة',
            onPressed: _pickImage,
          ),
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'مسح جميع النقاط',
              onPressed: () {
                setState(() => _items.clear());
                HapticFeedback.lightImpact();
              },
            ),
        ],
      ),
      body: _imageBytes == null
          ? _buildEmptyState(isDark)
          : Column(
              children: [
                // Live Counter Stats Bar
                _buildCountBanner(isDark),

                // Interactive Image Inspection Viewport
                Expanded(
                  flex: 6,
                  child: _buildViewport(isDark),
                ),

                // Bottom Controls Card
                Expanded(
                  flex: 5,
                  child: _buildControlsCard(isDark),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pin_rounded,
                size: 46,
                color: Color(0xFFFF9500),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'عداد الأشياء التلقائي أوفلاين 🔢',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'وجّه الكاميرا إلى كومة من الأنابيب، كراتين البضائع، حبات الدواء، أو أوراق المستندات، ليقوم التطبيق بعدّها فوراً ووضع دوائر مرقمة عليها مع تصدير تقرير جرد رسمي.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9500),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text(
                'اختيار صورة للبدء بالعدّ',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: _pickImage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _badgeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded, color: _badgeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'العدد الإجمالي المحصى',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_items.length} عنصر',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _items.isNotEmpty ? _badgeColor : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'إعادة الفحص التلقائي',
                onPressed: _isProcessing ? null : _runDetection,
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('تقرير جرد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _items.isNotEmpty && !_isProcessing ? _exportInventoryReport : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewport(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            LayoutBuilder(
              builder: (ctx, constraints) {
                return GestureDetector(
                  onTapUp: (details) => _onImageTap(details, constraints),
                  child: Stack(
                    children: [
                      // Base Image
                      Image.memory(
                        _imageBytes!,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        fit: BoxFit.contain,
                      ),

                      // Numbered Badge Overlays
                      ..._items.map((item) {
                        final badgeLeft = (item.x * constraints.maxWidth) - 11;
                        final badgeTop = (item.y * constraints.maxHeight) - 11;

                        return Positioned(
                          left: badgeLeft,
                          top: badgeTop,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _badgeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${item.id}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),

            if (_isProcessing)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'جارٍ كشف وحساب العناصر أوفلاين...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Tip badge
            Positioned(
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'المس أي مكان لإضافة نقطة (+) أو المس نقطة موجودة لحذفها (-)',
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white12
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'نوع العناصر المراد عدّها',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CounterObjectCategory.values.map((cat) {
              final isSel = _selectedCategory == cat;
              return ChoiceChip(
                label: Text(cat.label.split('(').first.trim()),
                selected: isSel,
                onSelected: (val) {
                  if (val && !isSel) {
                    setState(() => _selectedCategory = cat);
                    _runDetection();
                  }
                },
                selectedColor: const Color(0xFFFF9500).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? const Color(0xFFFF9500) : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Sensitivity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'حساسية كشف العناصر',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                '${(_sensitivity * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Color(0xFFFF9500),
                ),
              ),
            ],
          ),
          Slider(
            value: _sensitivity,
            min: 0.2,
            max: 0.95,
            activeColor: const Color(0xFFFF9500),
            onChanged: (val) => setState(() => _sensitivity = val),
            onChangeEnd: (_) => _runDetection(),
          ),

          const SizedBox(height: 10),

          // Color Badges Palette
          Row(
            children: [
              const Text(
                'لون نقاط العد:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              ...[
                const Color(0xFFFF3B30), // Red
                const Color(0xFFFF9500), // Orange
                const Color(0xFF34C759), // Green
                const Color(0xFF007AFF), // Blue
                const Color(0xFFAF52DE), // Purple
              ].map((c) {
                final isSel = _badgeColor == c;
                return GestureDetector(
                  onTap: () => setState(() => _badgeColor = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: isSel ? Border.all(color: Colors.white, width: 2) : null,
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
