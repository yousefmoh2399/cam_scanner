import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Service that strips EXIF / GPS metadata from JPEG images.
///
/// All CPU-heavy work (decode + re-encode) is delegated to a separate Dart
/// [Isolate] so the UI thread is never blocked.
class ExifScrubberService {
  const ExifScrubberService();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Decodes [bytes] as JPEG, re-encodes at quality 92 without any EXIF data,
  /// and returns the resulting bytes.
  Future<Uint8List> scrubBytes(Uint8List bytes) {
    return Isolate.run(() => _scrubBytesSync(bytes));
  }

  /// Reads the JPEG at [imagePath], scrubs EXIF in place, and returns [imagePath].
  Future<String> scrubFile(String imagePath) async {
    final original = await File(imagePath).readAsBytes();
    final scrubbed = await scrubBytes(original);
    await File(imagePath).writeAsBytes(scrubbed, flush: true);
    return imagePath;
  }

  /// No-op for PDF files: our pipeline never embeds GPS data into PDFs.
  Future<void> scrubPdfExport(String pdfPath) async {
    // PDFs produced by this app do not carry GPS EXIF; nothing to do.
  }

  /// Returns `true` when [bytes] contains no GPS IFD tags in its EXIF segment.
  ///
  /// Scans the raw byte stream for the GPS latitude tag (0x0002) and the GPS
  /// longitude tag (0x0004) that would appear inside the GPS IFD block.
  /// This is a conservative heuristic: if neither tag byte-sequence is present
  /// anywhere in the first 64 KB we consider the image clean.
  bool isExifClean(Uint8List bytes) {
    // GPS IFD tag IDs written in both big-endian and little-endian forms.
    // Tag 0x0002 = GPSLatitude, tag 0x0004 = GPSLongitude
    final searchWindow = bytes.length < 65536 ? bytes.length : 65536;
    for (var i = 0; i < searchWindow - 1; i++) {
      final hi = bytes[i];
      final lo = bytes[i + 1];
      // Big-endian: 00 02 or 00 04
      if (hi == 0x00 && (lo == 0x02 || lo == 0x04)) return false;
      // Little-endian: 02 00 or 04 00
      if (lo == 0x00 && (hi == 0x02 || hi == 0x04)) return false;
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers (run inside isolates)
  // ─────────────────────────────────────────────────────────────────────────

  static Uint8List _scrubBytesSync(Uint8List bytes) {
    // Decode – image package strips EXIF during re-encode when we use
    // encodeJpg because it only preserves pixel data, not metadata.
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) {
      // Not a valid JPEG – return the original bytes unchanged.
      return bytes;
    }
    // Re-encode without metadata. package:image's encodeJpg does not
    // carry over the original EXIF/XMP/GPS APP segments.
    final scrubbed = img.encodeJpg(decoded, quality: 92);
    return Uint8List.fromList(scrubbed);
  }
}
