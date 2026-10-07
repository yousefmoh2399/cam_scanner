import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'native_scanner_bridge.dart';

/// Unified offline QR & Barcode Detection Service.
/// Combines Google ML Kit Barcode Scanning with Native OpenCV QRCodeDetector fallback.
class QrScannerService {
  QrScannerService._();
  static final QrScannerService instance = QrScannerService._();

  final BarcodeScanner _mlKitScanner = BarcodeScanner(
    formats: [BarcodeFormat.qrCode, BarcodeFormat.all],
  );

  /// Decodes QR code from an image file path on disk.
  Future<String?> scanImage(String imagePath) async {
    // 1. Try Google ML Kit Barcode Scanner first
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final barcodes = await _mlKitScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw != null && raw.trim().isNotEmpty) {
          return raw.trim();
        }
        final display = barcode.displayValue;
        if (display != null && display.trim().isNotEmpty) {
          return display.trim();
        }
      }
    } catch (e) {
      debugPrint('[QrScannerService] MLKit scan error: $e');
    }

    // 2. Fallback to OpenCV QRCodeDetector natively
    try {
      final nativeResult = await NativeScannerBridge.decodeQrCode(imagePath);
      if (nativeResult != null && nativeResult.trim().isNotEmpty) {
        return nativeResult.trim();
      }
    } catch (e) {
      debugPrint('[QrScannerService] OpenCV fallback scan error: $e');
    }

    return null;
  }

  /// Displays an Apple-styled action modal sheet when a QR code / server URL is detected.
  Future<void> handleScannedPayload({
    required BuildContext context,
    required String payload,
  }) async {
    HapticFeedback.heavyImpact();
    final trimmed = payload.trim();
    final isUrl = trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('www.') ||
        RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?').hasMatch(trimmed);

    String normalizedUrl = trimmed;
    if (isUrl && !normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'http://$normalizedUrl';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Color(0xFF34C759),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUrl
                              ? 'تم اكتشاف خادم Web Drop / رابط'
                              : 'تم مسح رمز QR بنجاح',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'اختر طريقة فتح والتعامل مع البيانات الممسوحة',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Payload Display Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isUrl
                        ? const Color(0xFF007AFF).withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isUrl ? Icons.link_rounded : Icons.info_outline_rounded,
                          size: 16,
                          color: isUrl ? const Color(0xFF007AFF) : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isUrl ? 'عنوان الخادم المكتشف:' : 'محتوى الرمز:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isUrl ? const Color(0xFF007AFF) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      normalizedUrl,
                      style: TextStyle(
                        fontFamily: isUrl ? 'monospace' : null,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isUrl
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Actions for URLs (The user's exact core requirement!)
              if (isUrl) ...[
                // Option 1: External Browser
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                  label: const Text(
                    'فتح في المتصفح الخارجي (Chrome / Safari)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final uri = Uri.parse(normalizedUrl);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذر فتح المتصفح: $e')),
                        );
                      }
                    }
                  },
                ),

                const SizedBox(height: 10),

                // Option 2: In-App Browser / Web View
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFF34C759),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.smartphone_rounded, size: 20),
                  label: const Text(
                    'فتح داخل التطبيق (متصفح داخلي مدمج)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final uri = Uri.parse(normalizedUrl);
                      final ok = await launchUrl(uri, mode: LaunchMode.inAppWebView);
                      if (!ok) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذر العرض داخل التطبيق: $e')),
                        );
                      }
                    }
                  },
                ),

                const SizedBox(height: 10),
              ],

              // Copy & Share Action Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('نسخ للذاكرة', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: normalizedUrl));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ الرابط للحافظة بنجاح'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.ios_share_rounded, size: 16),
                      label: const Text('مشاركة', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Share.share(normalizedUrl);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
