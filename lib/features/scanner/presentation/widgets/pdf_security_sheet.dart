import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/pending_upload.dart';
import '../../data/vault_security_service.dart';

class PdfSecurityOptions {
  const PdfSecurityOptions({
    required this.password,
    this.lockWithBiometrics = false,
    this.preventPrinting = false,
    this.preventCopying = false,
  });

  final String password;
  final bool lockWithBiometrics;
  final bool preventPrinting;
  final bool preventCopying;
}

/// A modal sheet for configuring military-grade password encryption
/// and biometric protection for documents (100% offline).
class PdfSecuritySheet extends StatefulWidget {
  const PdfSecuritySheet({
    super.key,
    required this.document,
  });

  final PendingUpload document;

  @override
  State<PdfSecuritySheet> createState() => _PdfSecuritySheetState();
}

class _PdfSecuritySheetState extends State<PdfSecuritySheet> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final VaultSecurityService _vaultService = VaultSecurityService();

  bool _obscurePassword = true;
  bool _lockWithBiometrics = false;
  bool _preventPrinting = false;
  bool _preventCopying = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  double _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0.0;
    double strength = 0.0;
    if (password.length >= 6) strength += 0.25;
    if (password.length >= 10) strength += 0.25;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 0.25;
    if (RegExp(r'[A-Za-z!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) strength += 0.25;
    return strength.clamp(0.0, 1.0);
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (password.isEmpty && !_lockWithBiometrics) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال كلمة مرور أو تفعيل القفل بالبصمة'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }

    if (password.isNotEmpty && password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمتا المرور غير متطابقتين'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      if (_lockWithBiometrics) {
        final authenticated = await _vaultService.authenticateWithBiometrics(
          reason: 'تأكيد البصمة لقفل المستند وحمايته',
        );
        if (!authenticated) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لم يتم تأكيد البصمة')),
            );
          }
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(
          PdfSecurityOptions(
            password: password,
            lockWithBiometrics: _lockWithBiometrics,
            preventPrinting: _preventPrinting,
            preventCopying: _preventCopying,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.appThemePalette;
    final strength = _calculatePasswordStrength(_passwordController.text);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.enhanced_encryption_rounded,
                    color: Color(0xFF007AFF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'قفل وتشفير المستند (AES-256)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'تشفير متقدم يمنع فتح الملف إلا بكلمة السر',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Password Field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'كلمة المرور المشفرة',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 8),

            // Strength bar
            if (_passwordController.text.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength,
                  minHeight: 5,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation(
                    strength > 0.75
                        ? const Color(0xFF34C759)
                        : (strength > 0.4
                            ? const Color(0xFFFF9500)
                            : const Color(0xFFFF2D55)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Confirm Password Field
            TextField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                prefixIcon: const Icon(Icons.lock_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),

            // Toggle 1: Lock with biometrics
            _buildOptionSwitch(
              icon: Icons.fingerprint_rounded,
              title: 'قفل المستند بالبصمة داخل التطبيق',
              subtitle: 'طلب البصمة أو الوجه قبل فتح هذا المستند في مكتبتك',
              value: _lockWithBiometrics,
              color: palette.accent,
              onChanged: (val) => setState(() => _lockWithBiometrics = val),
            ),
            const SizedBox(height: 8),

            // Toggle 2: Prevent copying
            _buildOptionSwitch(
              icon: Icons.content_copy_rounded,
              title: 'منع نسخ واستخراج النصوص',
              subtitle: 'تقييد النسخ لمنع تسريب محتوى الوثيقة',
              value: _preventCopying,
              color: const Color(0xFFFF9500),
              onChanged: (val) => setState(() => _preventCopying = val),
            ),
            const SizedBox(height: 8),

            // Toggle 3: Prevent printing
            _buildOptionSwitch(
              icon: Icons.print_disabled_rounded,
              title: 'منع الطباعة',
              subtitle: 'حظر أوامر الطباعة الخارجية إلا برمز الصلاحية',
              value: _preventPrinting,
              color: const Color(0xFF5856D6),
              onChanged: (val) => setState(() => _preventPrinting = val),
            ),
            const SizedBox(height: 20),

            // Submit Button
            FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.shield_rounded),
              label: Text(_isSaving ? 'جاري تطبيق الحماية...' : 'تأكيد وقفل المستند'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: color,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
