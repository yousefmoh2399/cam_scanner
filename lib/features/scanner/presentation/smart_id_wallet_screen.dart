import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/motion_tokens.dart';
import '../data/native_scanner_bridge.dart';
import '../../../shared/providers/providers.dart';
import '../data/smart_id_wallet_service.dart';
import 'id_card_a4_screen.dart';
import 'scan_review_screen.dart';

class SmartIdWalletScreen extends ConsumerStatefulWidget {
  const SmartIdWalletScreen({super.key});

  @override
  ConsumerState<SmartIdWalletScreen> createState() => _SmartIdWalletScreenState();
}

class _SmartIdWalletScreenState extends ConsumerState<SmartIdWalletScreen> {
  final SmartIdWalletService _walletService = SmartIdWalletService.instance;

  List<SmartIdCard> _cards = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Track flip state per card (cardId -> isFlipped)
  final Map<String, bool> _flippedCards = {};

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _isLoading = true);
    final cards = await _walletService.loadCards();
    if (mounted) {
      setState(() {
        _cards = cards;
        _isLoading = false;
      });
    }
  }

  List<SmartIdCard> get _filteredCards {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _cards;
    return _cards.where((c) {
      final inTitle = c.title.toLowerCase().contains(q);
      final inName = c.holderName?.toLowerCase().contains(q) ?? false;
      final inNum = c.cardNumber?.toLowerCase().contains(q) ?? false;
      return inTitle || inName || inNum;
    }).toList();
  }

  void _flipCard(String cardId) {
    HapticFeedback.selectionClick();
    setState(() {
      _flippedCards[cardId] = !(_flippedCards[cardId] ?? false);
    });
  }

  Future<void> _printPvcCard(SmartIdCard card) async {
    HapticFeedback.mediumImpact();
    try {
      final pdfBytes = await _walletService.buildPvcCardPdf(card);
      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes,
        name: '${card.title}_CR80_PVC.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الطباعة: $e')),
        );
      }
    }
  }

  void _openInIdCardA4Studio(SmartIdCard card) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IdCardA4Screen(
          initialFrontPath: card.frontImagePath,
          initialBackPath: card.backImagePath,
          initialTitle: card.title,
        ),
      ),
    );
  }

  void _shareCardImages(SmartIdCard card) {
    HapticFeedback.lightImpact();
    final files = [XFile(card.frontImagePath)];
    if (card.hasBack) {
      files.add(XFile(card.backImagePath!));
    }
    Share.shareXFiles(files, subject: card.title);
  }

  Future<void> _deleteCard(SmartIdCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف البطاقة من المحفظة؟',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('هل تريد حذف "${card.title}" نهائياً من محفظة البطاقات؟'),
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
      await _walletService.deleteCard(card.id);
      _loadCards();
    }
  }

  void _showAddCardModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddCardSheet(onSaved: _loadCards),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cards = _filteredCards;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'المحفظة الذكية للبطاقات (PVC)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
            ),
            Text(
              '${_cards.length} بطاقات • مقاس قياسي CR-80 وطباعة 1:1',
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إضافة بطاقة جديدة',
            icon: const Icon(Icons.add_card_rounded, color: Color(0xFF007AFF)),
            onPressed: _showAddCardModal,
          ),
        ],
      ),
      body: Column(
        children: [
          // Apple Inset Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'بحث في البطاقات (الاسم، الرقم، النوع)...',
                  hintStyle:
                      TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Color(0xFF8E8E93),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Cards List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : cards.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.badge_rounded,
                                  color: Color(0xFF007AFF),
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'محفظة البطاقات البلاستيكية فارغة',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'احفظ بطاقة الرقم القومي ورخص القيادة وبطاقات العمل والاشتراكات بوجهين، مع طباعتها بحجمها الطبيعي 1:1 بالمقاس القياسي العالمي CR-80.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                onPressed: _showAddCardModal,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('إضافة أول بطاقة الآن'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: cards.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 18),
                        itemBuilder: (ctx, idx) {
                          final card = cards[idx];
                          final isFlipped = _flippedCards[card.id] ?? false;
                          return _buildCardItem(card, isFlipped, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(SmartIdCard card, bool isFlipped, bool isDark) {
    final cardColor = Color(card.cardType.colorValue);

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
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    card.cardType.arabicLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cardColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (card.hasBack)
                  InkWell(
                    onTap: () => _flipCard(card.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flip_rounded, size: 13, color: Color(0xFF007AFF)),
                          const SizedBox(width: 4),
                          Text(
                            isFlipped ? 'الوجه الخلفي 🔄' : 'الوجه الأمامي 🔄',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Interactive 3D Physical Card Display (Ratio: 85.6 / 53.98 = 1.586)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GestureDetector(
              onTap: card.hasBack ? () => _flipCard(card.id) : null,
              child: AspectRatio(
                aspectRatio: SmartIdWalletService.cr80WidthMm /
                    SmartIdWalletService.cr80HeightMm, // 1.5857
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: isFlipped ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutBack,
                  builder: (context, val, child) {
                    final isUnder = (val >= 0.5);
                    final displayImagePath =
                        (isUnder && card.hasBack) ? card.backImagePath! : card.frontImagePath;

                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(val * math.pi),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.12),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..rotateY(isUnder ? math.pi : 0.0),
                                child: Image.file(
                                  File(displayImagePath),
                                  fit: BoxFit.cover,
                                  cacheWidth: 600,
                                  errorBuilder: (ctx, err, st) => Container(
                                    color: cardColor.withValues(alpha: 0.15),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.badge_rounded, color: cardColor, size: 36),
                                          const SizedBox(height: 6),
                                          Text(
                                            card.title,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: cardColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Holographic corner chip badge
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: const Text(
                                    'CR-80 PVC',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Card details line (Holder Name / Number)
          if (card.holderName != null || card.cardNumber != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  if (card.holderName != null) ...[
                    const Icon(Icons.person_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      card.holderName!,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  if (card.cardNumber != null) ...[
                    const Icon(Icons.credit_card_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      card.cardNumber!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // Balanced Apple HIG Actions Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                // 1. PVC Card Print (50%)
                Expanded(
                  child: Material(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _printPvcCard(card),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.print_rounded, size: 17, color: Color(0xFF007AFF)),
                            SizedBox(width: 6),
                            Text(
                              'طابعة PVC (1:1)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. A4 Sheet Export (50%)
                Expanded(
                  child: Material(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _openInIdCardA4Studio(card),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, size: 17, color: Color(0xFF34C759)),
                            SizedBox(width: 6),
                            Text(
                              'ورقة A4 (1:1)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Share Icon Squircle
                Material(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _shareCardImages(card),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                          width: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.ios_share_rounded, size: 17),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Delete Icon Squircle
                Material(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _deleteCard(card),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.2),
                          width: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.delete_outline_rounded, size: 17, color: Colors.red),
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
  }
}

class _AddCardSheet extends ConsumerStatefulWidget {
  const _AddCardSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends ConsumerState<_AddCardSheet> {
  final _titleCtrl = TextEditingController();
  final _holderNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _expiryDateCtrl = TextEditingController();

  SmartIdCardType _selectedType = SmartIdCardType.nationalId;
  String? _frontImagePath;
  String? _backImagePath;
  bool _isSaving = false;

  Future<void> _scanCardSide(bool isFront) async {
    HapticFeedback.lightImpact();
    try {
      final draftsDir =
          await ref.read(localDocumentStoreProvider).getDraftsDirectory();
      final results = await NativeScannerBridge.startScan(
        destDir: draftsDir.path,
        batch: false,
      );

      if (results.isNotEmpty && mounted) {
        final res = results.first;
        final processedPath = await openScanReviewScreen(
          context,
          rawImagePath: res.path,
          initialCorners: res.corners,
          imageWidth: res.width,
          imageHeight: res.height,
        );
        if (processedPath != null && mounted) {
          setState(() {
            if (isFront) {
              _frontImagePath = processedPath;
            } else {
              _backImagePath = processedPath;
            }
          });
        }
      }
    } on ScannerPermissionDeniedException catch (e) {
      if (mounted) {
        await showScannerPermissionDialog(context, e);
      }
    } catch (_) {
      // Fallback: pick from gallery
      _pickFromGallery(isFront);
    }
  }

  Future<void> _pickFromGallery(bool isFront) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null && mounted) {
      final processedPath = await openScanReviewScreen(
        context,
        rawImagePath: res.files.single.path!,
      );
      if (processedPath != null && mounted) {
        setState(() {
          if (isFront) {
            _frontImagePath = processedPath;
          } else {
            _backImagePath = processedPath;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (_frontImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تصوير أو اختيار الوجه الأمامي للبطاقة')),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      await SmartIdWalletService.instance.addCard(
        title: _titleCtrl.text,
        cardType: _selectedType,
        frontSourcePath: _frontImagePath!,
        backSourcePath: _backImagePath,
        holderName: _holderNameCtrl.text,
        cardNumber: _cardNumberCtrl.text,
        expiryDate: _expiryDateCtrl.text,
      );

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت إضافة البطاقة للمحفظة بنجاح'),
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إضافة بطاقة إلى المحفظة الذكية',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),

            // Card Type Dropdown
            DropdownButtonFormField<SmartIdCardType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'نوع الوثيقة أو البطاقة',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              items: SmartIdCardType.values.map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Text(t.arabicLabel),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'عنوان البطاقة (مثال: بطاقة الرقم القومي)',
                hintText: _selectedType.arabicLabel,
                prefixIcon: const Icon(Icons.title_rounded),
              ),
            ),

            const SizedBox(height: 16),

            // Two-sided Photo Pickers
            Row(
              children: [
                Expanded(
                  child: _buildSideBox(
                    label: 'الوجه الأمامي *',
                    imagePath: _frontImagePath,
                    isFront: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSideBox(
                    label: 'الوجه الخلفي (اختياري)',
                    imagePath: _backImagePath,
                    isFront: false,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Optional Metadata
            TextField(
              controller: _holderNameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم صاحب البطاقة (اختياري)',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cardNumberCtrl,
              decoration: const InputDecoration(
                labelText: 'رقم البطاقة (اختياري)',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),

            const SizedBox(height: 18),

            Material(
              color: _isSaving
                  ? const Color(0xFF007AFF).withValues(alpha: 0.6)
                  : const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _isSaving ? null : _save,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSaving) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        const Icon(Icons.save_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _isSaving ? 'جارٍ الحفظ المشفر...' : 'حفظ البطاقة بالمحفظة',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideBox({
    required String label,
    required String? imagePath,
    required bool isFront,
  }) {
    return InkWell(
      onTap: () => _scanCardSide(isFront),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: imagePath != null
                ? const Color(0xFF34C759)
                : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: imagePath != null ? 1.5 : 1,
          ),
        ),
        child: imagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (ctx, err, st) => const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.grey),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt_rounded, color: Color(0xFF007AFF), size: 26),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
