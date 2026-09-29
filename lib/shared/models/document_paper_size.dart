enum DocumentPaperSize { a4, idCard, receipt, auto }

extension DocumentPaperSizeLabels on DocumentPaperSize {
  String get label => switch (this) {
    DocumentPaperSize.a4 => 'ورقة عادية (A4)',
    DocumentPaperSize.idCard => 'بطاقة هوية',
    DocumentPaperSize.receipt => 'إيصال',
    DocumentPaperSize.auto => 'تلقائي (بدون هوامش)',
  };

  static DocumentPaperSize fromName(String? name) {
    if (name == null) return DocumentPaperSize.auto;
    return DocumentPaperSize.values.firstWhere(
      (size) => size.name == name,
      orElse: () => DocumentPaperSize.auto,
    );
  }
}
