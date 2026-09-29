String sanitizePdfName(String raw) {
  var name = raw.trim();
  if (name.isEmpty) {
    name = defaultPdfName();
  }
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (!name.toLowerCase().endsWith('.pdf')) {
    name = '$name.pdf';
  }
  return name;
}

String stripFileExtension(String fileName) {
  final dotIdx = fileName.lastIndexOf('.');
  if (dotIdx > 0) {
    return fileName.substring(0, dotIdx);
  }
  return fileName;
}

String defaultPdfName({String? ownerName}) {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final prefix = (ownerName != null && ownerName.trim().isNotEmpty)
      ? '${ownerName.trim()}_'
      : 'مستند_';
  return '$prefix$y-$m-${d}_$hh-$mm';
}

String formatDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final hh = hour12.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'م' : 'ص';
  return '$y/$m/$d • $hh:$mm $period';
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 بايت';
  if (bytes < 1024) return '$bytes بايت';
  final kb = bytes / 1024.0;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} ك.ب';
  }
  final mb = kb / 1024.0;
  return '${mb.toStringAsFixed(2)} م.ب';
}

String formatPageCount(int count) {
  if (count <= 0) return 'بدون صفحات';
  if (count == 1) return 'صفحة واحدة';
  if (count == 2) return 'صفحتان';
  if (count >= 3 && count <= 10) return '$count صفحات';
  return '$count صفحة';
}
