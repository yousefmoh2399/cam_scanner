enum ImageFilterType {
  enhance,
  original,
  lighten,
  gray,
  eco,
  noHandwriting;

  String get nativeKey => switch (this) {
        ImageFilterType.enhance => 'enhance',
        ImageFilterType.original => 'original',
        ImageFilterType.lighten => 'lighten',
        ImageFilterType.gray => 'gray',
        ImageFilterType.eco => 'eco',
        ImageFilterType.noHandwriting => 'no_handwriting',
      };

  String get label => switch (this) {
        ImageFilterType.enhance => 'توضيح',
        ImageFilterType.original => 'أصلي',
        ImageFilterType.lighten => 'تفتيح',
        ImageFilterType.gray => 'رمادي',
        ImageFilterType.eco => 'اقتصادي',
        ImageFilterType.noHandwriting => 'بدون كتابة يد',
      };

  static ImageFilterType fromKey(String? key) {
    return switch (key?.toLowerCase().trim()) {
      'original' => ImageFilterType.original,
      'lighten' || 'color' => ImageFilterType.lighten,
      'gray' || 'grayscale' => ImageFilterType.gray,
      'eco' || 'blackwhite' => ImageFilterType.eco,
      'no_handwriting' || 'nohandwriting' => ImageFilterType.noHandwriting,
      _ => ImageFilterType.enhance,
    };
  }
}
