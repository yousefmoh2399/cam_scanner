import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/signature_composer_service.dart';

/// Allows the user to position and resize a signature on top of a scanned page.
///
/// Returns the composited JPEG [Uint8List] or null if the user cancels.
class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({
    super.key,
    required this.pageImagePath,
    required this.signatureBytes,
  });

  final String pageImagePath;
  final Uint8List signatureBytes;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  // Relative position of the signature top-left corner (0.0–1.0 of IMAGE bounds)
  double _relX = 0.18;
  double _relY = 0.72;

  // Signature width as a fraction of the page width (0.0–1.0)
  double _relW = 0.34;
  double _baseRelW = 0.34;

  // Aspect ratio (height / width) of the signature image itself
  double _sigAspectRatio = 0.45;

  bool _applying = false;

  // Natural image dimensions (loaded once in initState)
  Size _imageNaturalSize = Size.zero;

  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImageAndSigSizes();
  }

  Future<void> _loadImageAndSigSizes() async {
    try {
      final sigBuffer = await ui.ImmutableBuffer.fromUint8List(
        widget.signatureBytes,
      );
      final sigDesc = await ui.ImageDescriptor.encoded(sigBuffer);
      if (sigDesc.width > 0 && sigDesc.height > 0) {
        _sigAspectRatio = sigDesc.height / sigDesc.width;
      }
      sigDesc.dispose();
      sigBuffer.dispose();
    } catch (_) {}

    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(
        widget.pageImagePath,
      );
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width.toDouble();
      final h = descriptor.height.toDouble();
      descriptor.dispose();
      buffer.dispose();
      if (mounted) {
        setState(() {
          _imageNaturalSize = Size(w, h);
        });
      }
    } catch (_) {
      final bytes = await File(widget.pageImagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (mounted) {
        setState(() {
          _imageNaturalSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
        });
      }
    }
  }

  /// The area (in stack-local coordinates) that the image actually occupies
  /// after BoxFit.contain letterboxing.
  Rect _imageFitRect(Size stackSize) {
    if (_imageNaturalSize == Size.zero || stackSize == Size.zero) {
      return Rect.fromLTWH(0, 0, stackSize.width, stackSize.height);
    }

    final scaleX = stackSize.width / _imageNaturalSize.width;
    final scaleY = stackSize.height / _imageNaturalSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final renderedW = _imageNaturalSize.width * scale;
    final renderedH = _imageNaturalSize.height * scale;
    final offsetX = (stackSize.width - renderedW) / 2;
    final offsetY = (stackSize.height - renderedH) / 2;

    return Rect.fromLTWH(offsetX, offsetY, renderedW, renderedH);
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);

    try {
      final composer = SignatureComposerService();
      final result = await composer.compositeSignatureOnImage(
        pageImagePath: widget.pageImagePath,
        signatureBytes: widget.signatureBytes,
        relativeX: _relX,
        relativeY: _relY,
        relativeWidth: _relW,
      );

      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تطبيق التوقيع: $e')));
        setState(() => _applying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D16),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'تحديد موضع التوقيع',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FilledButton.icon(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text(
                'تأكيد',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Sleek instruction pill ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_with_rounded,
                      size: 16,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'اسحب التوقيع للمكان المطلوب • تحكم في الحجم من الشريط بالأسفل',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Page + interactive signature box ──
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stackSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final fitRect = _imageFitRect(stackSize);

                  final screenWidth = (_relW * fitRect.width).clamp(
                    36.0,
                    fitRect.width > 0 ? fitRect.width : 300.0,
                  );
                  final screenHeight = (screenWidth * _sigAspectRatio).clamp(
                    24.0,
                    fitRect.height > 0 ? fitRect.height : 200.0,
                  );
                  final maxRelY = fitRect.height > 0
                      ? (1.0 - (screenHeight / fitRect.height)).clamp(0.0, 0.96)
                      : 0.92;
                  final clampedRelX = _relX.clamp(0.0, 1.0 - _relW);
                  final clampedRelY = _relY.clamp(0.0, maxRelY);

                  final screenLeft = fitRect.left + clampedRelX * fitRect.width;
                  final screenTop = fitRect.top + clampedRelY * fitRect.height;

                  return GestureDetector(
                    onScaleStart: (_) {
                      _baseRelW = _relW;
                    },
                    onScaleUpdate: (details) {
                      if (fitRect.width == 0 || fitRect.height == 0) return;
                      setState(() {
                        final dxRel =
                            details.focalPointDelta.dx / fitRect.width;
                        final dyRel =
                            details.focalPointDelta.dy / fitRect.height;
                        _relX = (_relX + dxRel).clamp(0.0, 1.0 - _relW);
                        _relY = (_relY + dyRel).clamp(0.0, maxRelY);

                        if (details.pointerCount >= 2) {
                          _relW = (_baseRelW * details.scale).clamp(0.12, 0.85);
                          _relX = _relX.clamp(0.0, 1.0 - _relW);
                        }
                      });
                    },
                    child: Stack(
                      key: _stackKey,
                      fit: StackFit.expand,
                      children: [
                        // Page image with subtle shadow
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.file(
                            File(widget.pageImagePath),
                            fit: BoxFit.contain,
                          ),
                        ),

                        // Signature overlay box
                        if (fitRect.width > 0)
                          Positioned(
                            left: screenLeft,
                            top: screenTop,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: screenWidth,
                                  height: screenHeight,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: palette.accent.withValues(
                                      alpha: 0.06,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: palette.accent,
                                      width: 1.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.accent.withValues(
                                          alpha: 0.22,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Image.memory(
                                    widget.signatureBytes,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                // Corner anchor dots
                                for (final pos in const [
                                  Offset(-5, -5),
                                  Offset(1, -5),
                                  Offset(-5, 1),
                                ])
                                  Positioned(
                                    left: pos.dx < 0 ? -5 : null,
                                    right: pos.dx > 0 ? -5 : null,
                                    top: pos.dy < 0 ? -5 : null,
                                    bottom: pos.dy > 0 ? -5 : null,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: palette.accent,
                                          width: 2.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Interactive corner resize knob
                                Positioned(
                                  right: -12,
                                  bottom: -12,
                                  child: GestureDetector(
                                    onPanUpdate: (d) {
                                      if (fitRect.width == 0) return;
                                      setState(() {
                                        final deltaW =
                                            d.delta.dx / fitRect.width;
                                        _relW = (_relW + deltaW).clamp(
                                          0.12,
                                          0.85,
                                        );
                                        _relX = _relX.clamp(0.0, 1.0 - _relW);
                                      });
                                    },
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: palette.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black38,
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.open_in_full_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Bottom control panel (Size slider + Action buttons) ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF131926),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_size_select_small_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'حجم التوقيع',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: _relW.clamp(0.12, 0.85),
                            min: 0.12,
                            max: 0.85,
                            activeColor: palette.accent,
                            inactiveColor: Colors.white24,
                            onChanged: (v) {
                              setState(() {
                                _relW = v;
                                _relX = _relX.clamp(0.0, 1.0 - _relW);
                              });
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${(_relW * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _applying
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _applying ? null : _apply,
                          icon: _applying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.done_all_rounded),
                          label: const Text(
                            'اعتماد التوقيع على الورقة',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
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
