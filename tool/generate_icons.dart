import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const sourcePath =
      'C:/Users/Yousef/.gemini/antigravity/brain/f9230a21-8644-4c14-b758-6f1d7e366576/.user_uploaded/media_1791279899287.jpg';

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    print('ERROR: Source image not found at $sourcePath');
    exit(1);
  }

  print('Reading source image: $sourcePath');
  final bytes = sourceFile.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) {
    print('ERROR: Failed to decode source image');
    exit(1);
  }

  print('Source image decoded successfully: ${image.width}x${image.height}');

  // 1. Save to assets/images/app_icon.png
  final assetsDir = Directory('assets/images');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  final icon1024 = img.copyResize(image, width: 1024, height: 1024, interpolation: img.Interpolation.linear);
  File('assets/images/app_icon.png').writeAsBytesSync(img.encodePng(icon1024));
  print('Saved assets/images/app_icon.png (1024x1024)');

  // 2. Android Mipmap icons
  final androidSizes = <String, int>{
    'android/app/src/main/res/mipmap-mdpi': 48,
    'android/app/src/main/res/mipmap-hdpi': 72,
    'android/app/src/main/res/mipmap-xhdpi': 96,
    'android/app/src/main/res/mipmap-xxhdpi': 144,
    'android/app/src/main/res/mipmap-xxxhdpi': 192,
  };

  for (final entry in androidSizes.entries) {
    final dir = Directory(entry.key);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final size = entry.value;
    final resized = img.copyResize(image, width: size, height: size, interpolation: img.Interpolation.linear);
    final pngBytes = img.encodePng(resized);

    File('${entry.key}/ic_launcher.png').writeAsBytesSync(pngBytes);
    File('${entry.key}/ic_launcher_round.png').writeAsBytesSync(pngBytes);
    print('Generated Android ${entry.key}: ic_launcher.png & ic_launcher_round.png (${size}x$size)');
  }

  // 3. iOS AppIcon set
  final iosSizes = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };

  final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosDir.existsSync()) {
    for (final entry in iosSizes.entries) {
      final size = entry.value;
      final resized = img.copyResize(image, width: size, height: size, interpolation: img.Interpolation.linear);
      File('${iosDir.path}/${entry.key}').writeAsBytesSync(img.encodePng(resized));
      print('Generated iOS AppIcon: ${entry.key} (${size}x$size)');
    }
  }

  print('All icons generated successfully!');
}
