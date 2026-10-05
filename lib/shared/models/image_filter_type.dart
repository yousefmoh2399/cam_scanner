enum ImageFilterType {
  original,
  magic,
  enhance,
  lighten,
  noHandwriting,
  shadowRemover,
  gray,
  bw,
  eco;

  String get nativeKey => switch (this) {
        ImageFilterType.original => 'original',
        ImageFilterType.magic => 'magic',
        ImageFilterType.enhance => 'enhance',
        ImageFilterType.lighten => 'lighten',
        ImageFilterType.noHandwriting => 'no_handwriting',
        ImageFilterType.shadowRemover => 'shadow_remover',
        ImageFilterType.gray => 'gray',
        ImageFilterType.bw => 'bw',
        ImageFilterType.eco => 'eco',
      };

  String get label => switch (this) {
        ImageFilterType.original => 'أصلي',
        ImageFilterType.magic => 'لون سحري',
        ImageFilterType.enhance => 'توضيح',
        ImageFilterType.lighten => 'تفتيح',
        ImageFilterType.noHandwriting => 'إزالة خط اليد',
        ImageFilterType.shadowRemover => 'إزالة الظلال والأصابع',
        ImageFilterType.gray => 'رمادي',
        ImageFilterType.bw => 'أبيض وأسود',
        ImageFilterType.eco => 'توفير الحبر',
      };

  static ImageFilterType fromKey(String? key) {
    return switch (key?.toLowerCase().trim()) {
      'original' => ImageFilterType.original,
      'magic' || 'magic_color' => ImageFilterType.magic,
      'enhance' || 'document' => ImageFilterType.enhance,
      'lighten' || 'color' => ImageFilterType.lighten,
      'no_handwriting' || 'nohandwriting' => ImageFilterType.noHandwriting,
      'shadow_remover' || 'remove_shadows' || 'shadow' =>
        ImageFilterType.shadowRemover,
      'gray' || 'grayscale' => ImageFilterType.gray,
      'bw' || 'blackwhite_sharp' || 'sauvola' => ImageFilterType.bw,
      'eco' || 'blackwhite' => ImageFilterType.eco,
      _ => ImageFilterType.enhance,
    };
  }
}
