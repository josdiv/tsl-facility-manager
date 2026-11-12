import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Reads (width, height, colour type) from a PNG file header.
(int, int, int) pngInfo(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20), bytes[25]);
}

void main() {
  const rgb = 2;
  const rgba = 6;
  const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

  test('App Store icon is 1024px with no transparency', () {
    // Apple rejects an App Store icon that has an alpha channel.
    expect(pngInfo('$ios/Icon-App-1024x1024@1x.png'), (1024, 1024, rgb));
  });

  test('every iOS icon drops the alpha channel', () {
    final icons = Directory(ios)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'));
    expect(icons, isNotEmpty);
    for (final icon in icons) {
      expect(pngInfo(icon.path).$3, isNot(rgba), reason: icon.path);
    }
  });

  test('Android has every launcher density at the right size', () {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    sizes.forEach((density, size) {
      final (width, height, _) = pngInfo(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect((width, height), (size, size), reason: density);
    });
  });

  test('Android adaptive icon uses a transparent foreground', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('ic_launcher_foreground'));
    expect(adaptive, contains('ic_launcher_background'));
    expect(pngInfo('assets/icon/app_icon_foreground.png').$3, rgba);
  });
}
