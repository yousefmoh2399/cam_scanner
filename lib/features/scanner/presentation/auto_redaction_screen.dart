import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../data/smart_redaction_service.dart';

class AutoRedactionScreen extends ConsumerStatefulWidget {
  const AutoRedactionScreen({
    super.key,
    this.initialDocument,
    this.initialImagePath,
  });

  final PendingUpload? initialDocument;
  final String? initialImagePath;

  @override
  ConsumerState<AutoRedactionScreen> createState() => _AutoRedactionScreenState();
}

class _AutoRedactionScreenState extends ConsumerState<AutoRedactionScreen> {
  final SmartRedactionService _redactionService = SmartRedactionService();

  String? _selectedImagePath;
  PendingUpload? _selectedDoc;

  final List<RedactionTarget> _redactions = [];
  bool _isManualDrawing = false;
  Offset? _drawStart;
  Offset? _drawCurrent;

  bool _isSaving = false;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _selectedDoc = widget.initialDocument;
    if (widget.initialImagePath != null) {
      _selectedImagePath = widget.initialImagePath;
    } else if (widget.initialDocument != null &&
        widget.initialDocument!.pages.isNotEmpty) {
      _selectedImagePath = widget.initialDocument!.pages.first.imagePath;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedImagePath != null) {
        _triggerAutoDetection();
      }
    });
  }

  Future<void> _triggerAutoDetection() async {
    if (_selectedImagePath == null) return;

    try {
      final ocrService = ref.read(ocrServiceProvider);
      final ocrDoc = await ocrService.recognizeDocument(
        imagePaths: [_selectedImagePath!],
      );
      if (ocrDoc.pages.isNotEmpty) {
        final detected = _redactionService.autoDetectSensitiveTargets(
          ocrLines: ocrDoc.pages.first.lines,
        );

        if (mounted) {
          setState(() {
            _redactions.clear();
            _redactions.addAll(detected);
          });
        }
      }
    } catch (_) {}

    await _updatePreview();
  }

  Future<void> _updatePreview() async {
    if (_selectedImagePath == null) return;
    final file = File(_selectedImagePath!);
    if (!file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final redacted = await _redactionService.burnRedactionsToBytes(
        imageBytes: bytes,
        redactions: _redactions,
      );

      if (mounted) {
        setState(() {
          _previewBytes = redacted;
        });
      }
    } catch (_) {}
  }

  Future<void> _selectDocumentFromLibrary() async {
    final docs = await ref.read(pendingUploadsControllerProvider.future);
    if (!mounted) return;

    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<PendingUpload>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'اختر مستنداً لحجب وتسويد البيانات الحساسة',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        return ListTile(
                          leading: const Icon(Icons.shield_outlined, color: Colors.red),
                          title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${d.pages.length} صفحات'),
                          onTap: () => Navigator.of(ctx).pop(d),
                        );
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

    if (selected != null && selected.pages.isNotEmpty) {
      setState(() {
        _selectedDoc = selected;
        _selectedImagePath = selected.pages.first.imagePath;
      });
      await _triggerAutoDetection();
    }
  }

  void _addManualRedactionBox(Rect normalized) {
    setState(() {
      _redactions.add(RedactionTarget(
        id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
        label: 'حجب يدوي مخصص',
        normalizedRect: normalized,
        isAutoDetected: false,
      ));
    });
    _updatePreview();
  }

  void _removeRedaction(int index) {
    setState(() {
      _redactions.removeAt(index);
    });
    _updatePreview();
  }

  Future<void> _saveRedactedDocument() async {
    if (_selectedImagePath == null) return;
    setState(() => _isSaving = true);

    try {
      final outPath = await _redactionService.burnRedactionsToFile(
        sourceImagePath: _selectedImagePath!,
        redactions: _redactions,
      );

      final docStore = ref.read(localDocumentStoreProvider);
      final newDoc = PendingUpload(
        id: 'redacted_${DateTime.now().millisecondsSinceEpoch}',
        fileName: '${_selectedDoc?.title ?? "مستند"}_محجوب_أمنياً',
        filePath: outPath,
        pageCount: 1,
        pages: [
          ScanPage(
            imagePath: outPath,
          ),
        ],
        createdAt: DateTime.now(),
        tags: const ['محجوب أمنياً', 'خصوصية', 'حجب'],
      );

      await docStore.savePendingUpload(newDoc);
      await ref.read(pendingUploadsControllerProvider.notifier).refresh();

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: const Text(
              'تم تسويد وحجب البيانات وحفظ النسخة الآمنة بالمكتبة بنجاح!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.white,
              onPressed: () {
                Share.shareXFiles([XFile(outPath)], text: newDoc.title);
              },
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'الحجب الأمني وتسويد البيانات',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'تغيير المستند',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _selectDocumentFromLibrary,
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Top Info Banner ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFECEC),
              child: Row(
                children: [
                  const Icon(Icons.security_update_warning_rounded, color: Colors.red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتم حرق مربعات التسويد مباشرة داخل بكسلات الصورة لحجب الرقم القومي أو الأرقام الحساسة نهائياً.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Interactive Document Preview Area ──
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF000000) : const Color(0xFFE5E5EA),
                child: Center(
                  child: _selectedImagePath == null
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('اختر مستنداً من المكتبة'),
                          onPressed: _selectDocumentFromLibrary,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              onPanStart: (details) {
                                if (!_isManualDrawing) return;
                                setState(() {
                                  _drawStart = details.localPosition;
                                  _drawCurrent = details.localPosition;
                                });
                              },
                              onPanUpdate: (details) {
                                if (!_isManualDrawing) return;
                                setState(() {
                                  _drawCurrent = details.localPosition;
                                });
                              },
                              onPanEnd: (details) {
                                if (!_isManualDrawing ||
                                    _drawStart == null ||
                                    _drawCurrent == null) {
                                  return;
                                }

                                final boxW = constraints.maxWidth;
                                final boxH = constraints.maxHeight;

                                final l = (_drawStart!.dx / boxW).clamp(0.0, 1.0);
                                final t = (_drawStart!.dy / boxH).clamp(0.0, 1.0);
                                final r = (_drawCurrent!.dx / boxW).clamp(0.0, 1.0);
                                final b = (_drawCurrent!.dy / boxH).clamp(0.0, 1.0);

                                final rect = Rect.fromLTRB(
                                  l < r ? l : r,
                                  t < b ? t : b,
                                  l < r ? r : l,
                                  t < b ? b : t,
                                );

                                if (rect.width > 0.02 && rect.height > 0.01) {
                                  _addManualRedactionBox(rect);
                                }

                                setState(() {
                                  _drawStart = null;
                                  _drawCurrent = null;
                                  _isManualDrawing = false;
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_previewBytes != null)
                                    Image.memory(
                                      _previewBytes!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                      ),
                                    )
                                  else if (_selectedImagePath != null)
                                    Image.file(
                                      File(_selectedImagePath!),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                      ),
                                    ),
                                  // Live drawing feedback rectangle
                                  if (_drawStart != null && _drawCurrent != null)
                                    CustomPaint(
                                      painter: _DragRectPainter(
                                        start: _drawStart!,
                                        current: _drawCurrent!,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),

            // ── Redaction Targets List & Controls ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        'عناصر الحجب والتسويد (${_redactions.length}):',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      FilledButton.tonalIcon(
                        icon: Icon(
                          _isManualDrawing ? Icons.check_circle : Icons.draw_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _isManualDrawing ? 'اسحب على الورقة الآن' : 'تحديد يدوي',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isManualDrawing ? Colors.amber.shade700 : null,
                          foregroundColor: _isManualDrawing ? Colors.white : null,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () {
                          setState(() => _isManualDrawing = !_isManualDrawing);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_redactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      child: Text(
                        'اضغط "تحديد يدوي" واسحب بإصبعك فوق أي جزء تريد تسويده وحجبه',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _redactions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final target = _redactions[i];
                          return Chip(
                            avatar: Icon(
                              target.isAutoDetected
                                  ? Icons.smart_toy_rounded
                                  : Icons.back_hand_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            backgroundColor: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFF1C1C1E),
                            label: Text(
                              target.label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white70,
                            ),
                            onDeleted: () => _removeRedaction(i),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Save Redacted Copy Button ──
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_rounded),
                    label: Text(
                      _isSaving ? 'جاري حرق التسويد والحفظ...' : 'حفظ المستند المحجوب نهائياً',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    onPressed: _selectedImagePath != null && !_isSaving
                        ? _saveRedactedDocument
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragRectPainter extends CustomPainter {
  _DragRectPainter({required this.start, required this.current});
  final Offset start;
  final Offset current;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, current);
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DragRectPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.current != current;
}
