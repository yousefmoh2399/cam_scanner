import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/audio_feedback_service.dart';
import '../data/vault_security_service.dart';
import 'widgets/apple_bottom_nav_bar.dart';
import 'widgets/cloud_backup_sheet.dart';

/// Phase 3.3: Secret Vault (AES-256-GCM On-Disk Encryption) & App Lock Settings Screen.
/// Redesigned with authentic Apple iOS Passcode lock experience, tactile numeric dial pad,
/// animated passcode dots, error-shake transitions, and a luxury encrypted file manager.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with SingleTickerProviderStateMixin {
  final VaultSecurityService _securityService = VaultSecurityService();

  // ── PIN & Lock Screen State ──
  String _enteredPin = '';
  String _tempFirstPin = '';
  int _setupStep = 0; // 0 = first entry, 1 = confirm entry
  bool _isChangingPin = false;
  String? _errorMessage;

  // ── Shake Animation ──
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // ── Vault Document State ──
  bool _isLoading = true;
  bool _isUnlocked = false;
  VaultSecuritySettings _settings = const VaultSecuritySettings();
  List<PendingUpload> _vaultDocs = const [];

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
    _initVault();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _initVault() async {
    final settings = await _securityService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _isLoading = false;
    });

    if (settings.hasPinConfigured && settings.biometricsEnabled) {
      final ok = await _securityService.authenticateWithBiometrics(
        reason: 'تأكيد الهوية لفتح الخزنة السرية المشفرة (AES-256-GCM)',
      );
      if (ok && mounted) {
        await _unlockAndLoadDocs();
      }
    }
  }

  Future<void> _unlockAndLoadDocs() async {
    ref.read(audioFeedbackServiceProvider).playVaultUnlock();
    final docs = await _securityService.loadVaultDocuments();
    if (!mounted) return;
    setState(() {
      _isUnlocked = true;
      _vaultDocs = docs;
      _errorMessage = null;
      _enteredPin = '';
      _isChangingPin = false;
      _setupStep = 0;
    });
  }

  Future<void> _triggerErrorShake(String message) async {
    HapticFeedback.heavyImpact();
    setState(() {
      _errorMessage = message;
    });
    try {
      await _shakeController.forward(from: 0);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _enteredPin = '';
      });
    }
  }

  Future<void> _onKeyTap(String digit) async {
    if (_enteredPin.length >= 4) return;
    HapticFeedback.lightImpact();

    final nextPin = _enteredPin + digit;
    setState(() {
      _enteredPin = nextPin;
      _errorMessage = null;
    });

    if (nextPin.length == 4) {
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted) return;
      await _processCompletedPin(nextPin);
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  void _onClearAll() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _enteredPin = '';
      _errorMessage = null;
    });
  }

  Future<void> _processCompletedPin(String pin) async {
    final isSetupMode = !_settings.hasPinConfigured || _isChangingPin;

    if (isSetupMode) {
      if (_setupStep == 0) {
        // Step 0: Save first entry and ask for confirmation
        HapticFeedback.mediumImpact();
        setState(() {
          _tempFirstPin = pin;
          _enteredPin = '';
          _setupStep = 1;
        });
      } else {
        // Step 1: Check confirmation
        if (pin == _tempFirstPin) {
          HapticFeedback.mediumImpact();
          await _securityService.configurePin(pin);
          final updated = _settings.copyWith(hasPinConfigured: true);
          await _securityService.saveSettings(updated);
          setState(() {
            _settings = updated;
          });
          await _unlockAndLoadDocs();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم إعداد الرمز السري بنجاح وتفعيل الخزنة المشفرة.'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
          }
        } else {
          // Mismatch
          await _triggerErrorShake('الرمز غير متطابق! يرجى إعادة المحاولة من البداية.');
          setState(() {
            _setupStep = 0;
            _tempFirstPin = '';
          });
        }
      }
    } else {
      // Normal Unlock Verification
      final valid = await _securityService.verifyPin(pin);
      if (valid) {
        HapticFeedback.mediumImpact();
        await _unlockAndLoadDocs();
      } else {
        await _triggerErrorShake('الرمز السري غير صحيح. يرجى المحاولة ثانية.');
      }
    }
  }

  Future<void> _authenticateBiometrics() async {
    HapticFeedback.lightImpact();
    final ok = await _securityService.authenticateWithBiometrics(
      reason: 'تأكيد الهوية لفتح الخزنة السرية المشفرة (AES-256-GCM)',
    );
    if (ok && mounted) {
      await _unlockAndLoadDocs();
    }
  }

  Future<void> _moveLibraryDocToVault() async {
    final libraryDocs =
        ref.read(pendingUploadsControllerProvider).valueOrNull ?? const [];
    if (libraryDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات في المكتبة لنقلها.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chosen = await showModalBottomSheet<PendingUpload>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      useSafeArea: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'اختر مستنداً لنقله وتشفيره داخل الخزنة:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: libraryDocs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final d = libraryDocs[idx];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded,
                            color: Color(0xFF9333EA), size: 22),
                      ),
                      title: Text(
                        stripFileExtension(d.fileName),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text(
                        '${formatPageCount(d.effectivePageCount)} • غير مشفر',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: const Icon(Icons.lock_outline_rounded,
                          color: Color(0xFF9333EA), size: 20),
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

    if (chosen == null) return;

    setState(() => _isLoading = true);
    try {
      await _securityService.moveDocumentToVault(chosen);
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .deleteDocument(chosen.id);
      final updatedVault = await _securityService.loadVaultDocuments();
      if (mounted) {
        setState(() {
          _vaultDocs = updatedVault;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تشفير "${stripFileExtension(chosen.fileName)}" بمعيار AES-256-GCM ونقله للخزنة السرية!',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر نقل المستند للخزنة: $e')),
        );
      }
    }
  }

  Future<void> _restoreVaultDocToLibrary(PendingUpload doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('فك تشفير المستند وإعادته؟',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'سيتم فك تشفير "${stripFileExtension(doc.fileName)}" وإعادته إلى المكتبة الرئيسية للمستندات ليكون مرئياً وقابلاً للبحث والمشاركة.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فك التشفير الآن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final restored = await _securityService.restoreDocumentFromVault(doc.id);
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .addDocument(restored);
      final updatedVault = await _securityService.loadVaultDocuments();
      if (mounted) {
        setState(() {
          _vaultDocs = updatedVault;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم فك تشفير "${stripFileExtension(doc.fileName)}" وإعادته للمكتبة بنجاح!',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل فك التشفير: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteVaultDoc(PendingUpload doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'حذف المستند المشفر نهائياً؟',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.red),
        ),
        content: Text(
          'سيتم حذف "${stripFileExtension(doc.fileName)}" وملفاته المشفرة نهائياً من وحدة التخزين. هذا الإجراء غير قابل للتراجع.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _securityService.deleteFromVaultPermanently(doc.id);
      final updatedVault = await _securityService.loadVaultDocuments();
      if (mounted) {
        setState(() {
          _vaultDocs = updatedVault;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المستند المشفر نهائياً.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e')),
        );
      }
    }
  }

  Future<void> _previewVaultDocument(PendingUpload doc) async {
    final targetPath = doc.pages.isNotEmpty
        ? doc.pages.first.imagePath
        : (doc.thumbnailPath ?? '');
    if (targetPath.isEmpty) return;

    final decryptedBytes = await _securityService.decryptFileToMemory(targetPath);
    if (!mounted || decryptedBytes == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                elevation: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stripFileExtension(doc.fileName),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'معاينة آمنة في الذاكرة RAM فقط',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: 1),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                  ),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.memory(
                      Uint8List.fromList(decryptedBytes),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSecuritySettingsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.security_rounded,
                            color: Color(0xFF007AFF), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'إعدادات الأمان وقفل التطبيق',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'قفل التطبيق بالكامل (App Lock)',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: const Text(
                            'طلب الرمز عند الفتح أو العودة من الخلفية',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _settings.appLockEnabled,
                          activeTrackColor: const Color(0xFF34C759),
                          onChanged: (v) async {
                            final next = _settings.copyWith(appLockEnabled: v);
                            await _securityService.saveSettings(next);
                            setState(() => _settings = next);
                            setSheetState(() {});
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'المصادقة بالبصمة / الوجه (Biometrics)',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: const Text(
                            'فتح الخزنة تلقائياً بالبصمة المعتمدة',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _settings.biometricsEnabled,
                          activeTrackColor: const Color(0xFF34C759),
                          onChanged: (v) async {
                            final next = _settings.copyWith(biometricsEnabled: v);
                            await _securityService.saveSettings(next);
                            setState(() => _settings = next);
                            setSheetState(() {});
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'حظر تصوير الشاشة (FLAG_SECURE)',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: const Text(
                            'منع لقطات الشاشة وإخفاء محتوى التطبيق بالمهام',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _settings.secureScreenEnabled,
                          activeTrackColor: const Color(0xFF34C759),
                          onChanged: (v) async {
                            final next = _settings.copyWith(secureScreenEnabled: v);
                            await _securityService.saveSettings(next);
                            setState(() => _settings = next);
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AutoLockTimeout>(
                    initialValue: _settings.autoLockTimeout,
                    decoration: InputDecoration(
                      labelText: 'مهلة القفل التلقائي',
                      prefixIcon: const Icon(Icons.timer_outlined),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: AutoLockTimeout.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.labelAr, style: const TextStyle(fontSize: 13)),
                          ),
                        )
                        .toList(),
                    onChanged: (val) async {
                      if (val == null) return;
                      final next = _settings.copyWith(autoLockTimeout: val);
                      await _securityService.saveSettings(next);
                      setState(() => _settings = next);
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('الخزنة السرية')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const AppleBottomNavBar(currentIndex: 3),
      );
    }

    if (!_isUnlocked) {
      return _buildApplePasscodeScreen();
    }

    return _buildUnlockedVaultScreen();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. APPLE PASSCODE LOCK SCREEN
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildApplePasscodeScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSetupMode = !_settings.hasPinConfigured || _isChangingPin;

    final title = isSetupMode
        ? (_setupStep == 0
            ? 'تعيين رمز سري جديد'
            : 'تأكيد الرمز السري')
        : 'الخزنة السرية المشفرة';

    final subtitle = isSetupMode
        ? (_setupStep == 0
            ? 'أدخل 4 أرقام لإنشاء رمز الحماية'
            : 'أعد إدخال الرمز السري للتأكيد')
        : 'أدخل رمز الدخول المكون من 4 أرقام';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isChangingPin
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _isChangingPin = false;
                    _isUnlocked = true;
                    _enteredPin = '';
                    _setupStep = 0;
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),

            // Top Icon (Apple Shield with Glow)
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF9333EA).withValues(alpha: 0.22),
                    const Color(0xFF007AFF).withValues(alpha: 0.16),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 36,
                color: Color(0xFF9333EA),
              ),
            ),
            const SizedBox(height: 16),

            // Title & Subtitle
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Passcode Dots with Shake Animation
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (ctx, child) {
                final offset = math.sin(_shakeAnimation.value * math.pi * 4) * 12;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? (_errorMessage != null
                              ? Colors.red
                              : const Color(0xFF9333EA))
                          : Colors.transparent,
                      border: Border.all(
                        color: _errorMessage != null
                            ? Colors.red
                            : (isFilled
                                ? const Color(0xFF9333EA)
                                : (isDark ? Colors.white38 : Colors.black38)),
                        width: 1.8,
                      ),
                    ),
                  );
                }),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const Spacer(flex: 2),

            // Apple Tactile Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  _buildKeypadRow(['1', '2', '3'], ['', 'ABC', 'DEF'], isDark),
                  const SizedBox(height: 16),
                  _buildKeypadRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO'], isDark),
                  const SizedBox(height: 16),
                  _buildKeypadRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ'], isDark),
                  const SizedBox(height: 16),
                  _buildKeypadBottomRow(isDark, isSetupMode),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // Security note footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    'تشفير محلي صارم AES-256-GCM بدون أي سيرفر خارجي',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      bottomNavigationBar: const AppleBottomNavBar(currentIndex: 3),
    );
  }

  Widget _buildKeypadRow(
    List<String> digits,
    List<String> letters,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (idx) {
        return _buildKeypadButton(
          digit: digits[idx],
          letters: letters[idx],
          isDark: isDark,
          onTap: () => _onKeyTap(digits[idx]),
        );
      }),
    );
  }

  Widget _buildKeypadBottomRow(bool isDark, bool isSetupMode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Left: Biometrics or Empty
        SizedBox(
          width: 72,
          height: 72,
          child: (!isSetupMode && _settings.biometricsEnabled)
              ? InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _authenticateBiometrics,
                  child: Center(
                    child: Icon(
                      Icons.fingerprint_rounded,
                      size: 32,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // Center: Digit 0
        _buildKeypadButton(
          digit: '0',
          letters: '',
          isDark: isDark,
          onTap: () => _onKeyTap('0'),
        ),

        // Right: Backspace
        SizedBox(
          width: 72,
          height: 72,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _onBackspace,
            onLongPress: _onClearAll,
            child: Center(
              child: Icon(
                Icons.backspace_outlined,
                size: 24,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadButton({
    required String digit,
    required String letters,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white : Colors.black,
                  height: 1.1,
                ),
              ),
              if (letters.isNotEmpty)
                Text(
                  letters,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. UNLOCKED VAULT MANAGER SCREEN
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildUnlockedVaultScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.enhanced_encryption_rounded,
                color: Color(0xFF10B981), size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'الخزنة السرية (AES-256)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'النسخ الاحتياطي السحابي المشفر',
            icon: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF007AFF)),
            onPressed: () => CloudBackupSheet.show(context),
          ),
          IconButton(
            tooltip: 'إعدادات الأمان',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSecuritySettingsSheet,
          ),
          IconButton(
            tooltip: 'قفل الخزنة فوراً',
            icon: const Icon(Icons.lock_rounded, color: Colors.amber),
            onPressed: () {
              ref.read(audioFeedbackServiceProvider).playVaultLock();
              setState(() {
                _isUnlocked = false;
                _enteredPin = '';
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          // Luxury Status Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1730), const Color(0xFF121424)]
                    : [const Color(0xFFF5E8FF), const Color(0xFFE8EEFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9333EA).withValues(alpha: isDark ? 0.2 : 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: Color(0xFF9333EA), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الخزنة السرية مفتوحة ومؤمّنة',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'الملفات مشفرة على القرص ومخفية تماماً عن المعرض والمكتبة وتطبيقات النظام.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Apple Dual Action Cards (50% / 50%)
          Row(
            children: [
              // Card 1: Import from Library
              Expanded(
                child: Material(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _moveLibraryDocToVault();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9333EA).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add_moderator_rounded,
                                color: Color(0xFF9333EA), size: 22),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تشفير مستند',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 1),
                                Text(
                                  'نقل من المكتبة',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Card 2: Change PIN
              Expanded(
                child: Material(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _isChangingPin = true;
                        _isUnlocked = false;
                        _setupStep = 0;
                        _enteredPin = '';
                        _tempFirstPin = '';
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.password_rounded,
                                color: Colors.amber, size: 22),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تغيير الرمز',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 1),
                                Text(
                                  'تحديث رمز الدخول',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Vault Documents Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.folder_special_rounded,
                    color: Color(0xFF10B981), size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'المستندات المشفرة داخل الخزنة (${_vaultDocs.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Vault Documents List
          if (_vaultDocs.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_clock_rounded,
                        size: 32, color: Color(0xFF9333EA)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الخزنة فارغة حالياً',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اضغط على "تشفير مستند" لاختيار ملف من المكتبة وتأمينه بتشفير AES-256-GCM الصارم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._vaultDocs.map((doc) => _buildVaultDocumentCard(doc, isDark)),
        ],
      ),
      bottomNavigationBar: const AppleBottomNavBar(currentIndex: 3),
    );
  }

  Widget _buildVaultDocumentCard(PendingUpload doc, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                // Lock Badge Avatar
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Color(0xFF9333EA),
                        size: 24,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 9, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stripFileExtension(doc.fileName),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'AES-256-GCM',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatPageCount(doc.effectivePageCount),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Card Action Buttons
            Row(
              children: [
                // Preview in memory
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('معاينة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: () => _previewVaultDocument(doc),
                  ),
                ),
                const SizedBox(width: 8),

                // Restore to library
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('استعادة للمكتبة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    onPressed: () => _restoreVaultDocToLibrary(doc),
                  ),
                ),
                const SizedBox(width: 4),

                // Delete permanently
                IconButton(
                  tooltip: 'حذف نهائي',
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                  onPressed: () => _confirmDeleteVaultDoc(doc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
