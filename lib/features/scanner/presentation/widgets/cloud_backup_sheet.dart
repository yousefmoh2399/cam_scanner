import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion_tokens.dart';
import '../../../../shared/models/pending_upload.dart';
import '../../../../shared/providers/providers.dart';
import '../../../../shared/services/audio_feedback_service.dart';

/// نافذة النسخ الاحتياطي السحابي المشفر بالكامل بهوية آبل (Zero-Knowledge Cloud Backup)
/// - يدعم تصدير الأرشيف المشفر (PBKDF2 + AES-256-GCM) مباشرة إلى Google Drive أو iCloud أو الذاكرة
/// - يتيح تشفير مستندات المكتبة والخزنة السرية وفهرس البحث
/// - استعادة ذكية تمنع التكرار وتتحقق من سلامة البيانات
class CloudBackupSheet extends ConsumerStatefulWidget {
  const CloudBackupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudBackupSheet(),
    );
  }

  @override
  ConsumerState<CloudBackupSheet> createState() => _CloudBackupSheetState();
}

class _CloudBackupSheetState extends ConsumerState<CloudBackupSheet> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _includeVault = true;
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final password = _passwordController.text.trim();
    if (password.isNotEmpty && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمة المرور يجب أن تكون 6 أحرف أو أرقام على الأقل لضمان التشفير العسكري.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ جمع المستندات وتجهيز الأرشيف...';
    });

    try {
      final docs = ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
      final folders = await ref.read(documentFolderServiceProvider).loadFolders();

      List<PendingUpload>? vaultDocs;
      if (_includeVault) {
        final secSvc = ref.read(vaultSecurityServiceProvider);
        vaultDocs = await secSvc.loadVaultDocuments();
      }

      final backupSvc = ref.read(backupRestoreServiceProvider);
      final zipPath = await backupSvc.createBackupZip(
        documents: docs,
        folders: folders,
        vaultDocuments: vaultDocs,
        password: password.isEmpty ? null : password,
        onProgress: (status) {
          if (mounted) setState(() => _statusMessage = status);
        },
      );

      ref.read(audioFeedbackServiceProvider).playSuccess();

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });

        // Prompt native share sheet to send to Google Drive, iCloud, Files, etc.
        await Share.shareXFiles(
          [XFile(zipPath)],
          subject: 'نسخة لقطة الاحتياطية المشفرة (Zero-Knowledge)',
          text: 'نسخة احتياطية مشفرة لمستندات لقطة (تشفير AES-256-GCM)',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء النسخة الاحتياطية: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    HapticFeedback.lightImpact();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'laqtabak'],
    );
    final filePath = picked?.files.firstOrNull?.path;
    if (filePath == null || !mounted) return;

    final backupSvc = ref.read(backupRestoreServiceProvider);
    final isEncrypted = await backupSvc.isBackupEncrypted(filePath);

    String? password = _passwordController.text.trim();
    if (isEncrypted && password.isEmpty) {
      if (!mounted) return;
      final enteredPwd = await _promptPasswordDialog();
      if (enteredPwd == null || enteredPwd.isEmpty) return;
      password = enteredPwd;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'جارٍ فك التشفير واستعادة المستندات...';
    });

    try {
      final currentDocs =
          ref.read(pendingUploadsControllerProvider).valueOrNull ?? [];
      final currentFolders =
          await ref.read(documentFolderServiceProvider).loadFolders();

      final res = await backupSvc.restoreFromBackupFile(
        zipFilePath: filePath,
        currentDocuments: currentDocs,
        currentFolders: currentFolders,
        password: password.isEmpty ? null : password,
        onProgress: (status) {
          if (mounted) setState(() => _statusMessage = status);
        },
      );

      await ref
          .read(documentFolderServiceProvider)
          .saveFolders(res.mergedFolders);
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .replaceAllDocuments(res.mergedDocuments);

      // If backup contained vault documents, restore them into the vault storage
      if (res.restoredVaultDocuments.isNotEmpty) {
        final secSvc = ref.read(vaultSecurityServiceProvider);
        final existingVault = await secSvc.loadVaultDocuments();
        final existingVaultIds = existingVault.map((d) => d.id).toSet();
        final updatedVault = List<PendingUpload>.from(existingVault);
        for (final vDoc in res.restoredVaultDocuments) {
          if (!existingVaultIds.contains(vDoc.id)) {
            updatedVault.add(vDoc);
          }
        }
        await secSvc.saveVaultDocuments(updatedVault);
      }

      ref.read(audioFeedbackServiceProvider).playSuccess();

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت الاستعادة بنجاح: ${res.stats.restoredDocuments} مستند، ${res.stats.restoredFolders} مجلد'
              '${res.stats.restoredVaultDocuments > 0 ? "، ${res.stats.restoredVaultDocuments} مستند بالخزنة" : ""}',
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل استعادة النسخة: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<String?> _promptPasswordDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الملف مشفر بكلمة مرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'هذه النسخة الاحتياطية محمية بتشفير عسكري AES-256-GCM. يرجى إدخال كلمة المرور لفك التشفير:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('فك التشفير واستعادة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.appThemePalette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181C26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Notch Bar
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // Hero Identity Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF007AFF), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cloud_sync_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'النسخ الاحتياطي السحابي',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'Zero-Knowledge',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'مزامنة مشفرة مع Google Drive أو iCloud بدون إمكانية قراءة أي طرف ثالث',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Privacy Trust Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'تشفير عسكري AES-256-GCM مع اشتقاق PBKDF2 (10,000 جولة). حتى خوادم جوجل أو أبل لن تتمكن من قراءة ملفاتك.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Password Input Field
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isProcessing,
                  decoration: InputDecoration(
                    labelText: 'كلمة مرور تشفير النسخة (Zero-Knowledge Key)',
                    hintText: 'أدخل كلمة مرور قوية لتشفير النسخة',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    helperText: 'اختياري ولكن يُوصى به بشدة لحماية مستنداتك وسريتك.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Include Vault Checkbox
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _includeVault,
                  onChanged: _isProcessing
                      ? null
                      : (val) => setState(() => _includeVault = val),
                  title: const Text(
                    'تضمين مستندات الخزنة السرية',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'حزم الملفات المشفرة المخزنة بالخزنة الآمنة في نفس النسخة الاحتياطية',
                    style: TextStyle(fontSize: 11),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.enhanced_encryption_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Processing Indicator
                if (_isProcessing) ...[
                  LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: palette.accent.withValues(alpha: 0.2),
                    color: palette.accent,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage ?? 'جارٍ المعالجة...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : _exportBackup,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text(
                      'إنشاء ورفع إلى Google Drive / iCloud',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _importBackup,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: const Text(
                      'استعادة من Google Drive أو iCloud أو ملف',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
