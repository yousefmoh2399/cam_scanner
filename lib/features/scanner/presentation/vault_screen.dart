import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../data/vault_security_service.dart';
import 'widgets/apple_bottom_nav_bar.dart';

/// Phase 3.3: Secret Vault (AES-256-GCM On-Disk Encryption) & App Lock Settings Screen.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final VaultSecurityService _securityService = VaultSecurityService();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = true;
  bool _isUnlocked = false;
  VaultSecuritySettings _settings = const VaultSecuritySettings();
  List<PendingUpload> _vaultDocs = const [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initVault();
  }

  @override
  void dispose() {
    _pinController.dispose();
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
    final docs = await _securityService.loadVaultDocuments();
    if (!mounted) return;
    setState(() {
      _isUnlocked = true;
      _vaultDocs = docs;
      _errorMessage = null;
    });
  }

  Future<void> _handleSetupPin() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() {
        _errorMessage = 'يجب أن يتكون الرمز السري من 4 أرقام على الأقل.';
      });
      return;
    }

    await _securityService.configurePin(pin);
    final updated = _settings.copyWith(hasPinConfigured: true);
    await _securityService.saveSettings(updated);
    _pinController.clear();
    setState(() => _settings = updated);
    await _unlockAndLoadDocs();
  }

  Future<void> _handleVerifyPin() async {
    final pin = _pinController.text.trim();
    final valid = await _securityService.verifyPin(pin);
    if (!valid) {
      setState(() => _errorMessage = 'الرمز السري غير صحيح.');
      return;
    }
    _pinController.clear();
    await _unlockAndLoadDocs();
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

    final chosen = await showModalBottomSheet<PendingUpload>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        itemCount: libraryDocs.length,
        itemBuilder: (_, idx) {
          final d = libraryDocs[idx];
          return ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: Text(
              stripFileExtension(d.fileName),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(formatPageCount(d.effectivePageCount)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.of(ctx).pop(d),
          );
        },
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
              'تم فك تشفير "${stripFileExtension(doc.fileName)}" وإعادته للمكتبة!',
            ),
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

  Future<void> _previewVaultDocument(PendingUpload doc) async {
    final targetPath = doc.pages.isNotEmpty
        ? doc.pages.first.imagePath
        : (doc.thumbnailPath ?? '');
    if (targetPath.isEmpty) return;

    final decryptedBytes = await _securityService.decryptFileToMemory(targetPath);
    if (!mounted || decryptedBytes == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(stripFileExtension(doc.fileName)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  Uint8List.fromList(decryptedBytes),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('الخزنة السرية والحماية')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isUnlocked) {
      final isFirstSetup = !_settings.hasPinConfigured;
      final isDark = theme.brightness == Brightness.dark;
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        appBar: AppBar(
          backgroundColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'الخزنة السرية (AES-256)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.enhanced_encryption_rounded,
                    size: 38,
                    color: palette.accent,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isFirstSetup
                    ? 'إعداد الرمز السري للخزنة المشفرة'
                    : 'أدخل الرمز السري لفتح الخزنة',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تنبيه هام: التشفير يتم محلياً بمعيار AES-256-GCM بدون أي سيرفر؛ نسيان الرمز السري يعني استحالة استرجاع الملفات المشفرة نهائياً.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    labelText: 'الرمز السري (4 إلى 8 أرقام)',
                    errorText: _errorMessage,
                    border: InputBorder.none,
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin_rounded),
                  ),
                  onSubmitted: (_) =>
                      isFirstSetup ? _handleSetupPin() : _handleVerifyPin(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      isFirstSetup ? _handleSetupPin() : _handleVerifyPin(),
                  icon: const Icon(Icons.lock_open_rounded, size: 20),
                  label: Text(
                    isFirstSetup
                        ? 'تفعيل التشفير وحفظ الرمز'
                        : 'فتح الخزنة السرية',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (!isFirstSetup && _settings.biometricsEnabled) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _securityService
                          .authenticateWithBiometrics();
                      if (ok && mounted) {
                        await _unlockAndLoadDocs();
                      }
                    },
                    icon: const Icon(Icons.fingerprint_rounded, size: 22),
                    label: const Text(
                      'فتح باستخدام البصمة / الوجه',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.accent, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: const AppleBottomNavBar(currentIndex: 3),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'الخزنة السرية وإعدادات الحماية',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'قفل الخزنة الآن',
            icon: const Icon(Icons.lock_rounded),
            onPressed: () => setState(() => _isUnlocked = false),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onPressed: _moveLibraryDocToVault,
        icon: const Icon(Icons.enhanced_encryption_rounded),
        label: const Text(
          'نقل مستند للخزنة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        children: [
          // Security Controls Card
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'قفل التطبيق وحماية الشاشة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'قفل التطبيق (App Lock)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'طلب الرمز السري عند الفتح أو العودة من الخلفية',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: _settings.appLockEnabled,
                  onChanged: (v) async {
                    final next = _settings.copyWith(appLockEnabled: v);
                    await _securityService.saveSettings(next);
                    setState(() => _settings = next);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'المصادقة بالبصمة / الوجه (Biometrics)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  value: _settings.biometricsEnabled,
                  onChanged: (v) async {
                    final next = _settings.copyWith(biometricsEnabled: v);
                    await _securityService.saveSettings(next);
                    setState(() => _settings = next);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'حظر لقطات الشاشة (FLAG_SECURE)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'منع تصوير الشاشة وإخفاء المعاينة بالخلفية',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: _settings.secureScreenEnabled,
                  onChanged: (v) async {
                    final next = _settings.copyWith(secureScreenEnabled: v);
                    await _securityService.saveSettings(next);
                    setState(() => _settings = next);
                  },
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<AutoLockTimeout>(
                  initialValue: _settings.autoLockTimeout,
                  decoration: const InputDecoration(
                    labelText: 'مهلة القفل التلقائي',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: AutoLockTimeout.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.labelAr),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    final next = _settings.copyWith(autoLockTimeout: val);
                    await _securityService.saveSettings(next);
                    setState(() => _settings = next);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.shield_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                'المستندات المشفرة داخل الخزنة (${_vaultDocs.length}):',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_vaultDocs.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              child: const Text(
                'الخزنة السرية فارغة حالياً.\nاضغط على "نقل مستند للخزنة" لتشفير أي مستند بمعيار AES-256-GCM وإخفائه من المكتبة والبحث.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._vaultDocs.map(
              (doc) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: palette.accent.withValues(alpha: 0.14),
                    child: Icon(
                      Icons.enhanced_encryption_rounded,
                      color: palette.accent,
                    ),
                  ),
                  title: Text(
                    stripFileExtension(doc.fileName),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${formatPageCount(doc.effectivePageCount)} • مشفر بـ AES-256-GCM',
                  ),
                  onTap: () => _previewVaultDocument(doc),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      IconButton(
                        tooltip: 'معاينة آمنة في الذاكرة',
                        icon: const Icon(Icons.visibility_rounded),
                        onPressed: () => _previewVaultDocument(doc),
                      ),
                      IconButton(
                        tooltip: 'فك التشفير وإعادة للمكتبة',
                        icon: const Icon(Icons.lock_open_rounded),
                        onPressed: () => _restoreVaultDocToLibrary(doc),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppleBottomNavBar(currentIndex: 3),
    );
  }
}
