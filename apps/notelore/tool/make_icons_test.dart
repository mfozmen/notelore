// Writes every platform's app icon from Notelore's mark (lib/src/mark.dart),
// so the icons and the in-app mark never drift apart (#340). Not part of the
// test suite (it lives outside test/); run it by hand after changing the mark:
//
//   cd apps/notelore && flutter test tool/make_icons_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/mark.dart';
import 'package:path/path.dart' as p;

/// The mark drawn on a [side]-pixel canvas as PNG bytes; [margin] (a share of
/// the side) is left around the painter's own square.
Future<Uint8List> png(
  int side,
  MarkPainter painter, {
  double margin = 0,
  bool opaque = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (opaque) canvas.drawColor(MarkColors.teal, BlendMode.src);
  final body = side * (1 - 2 * margin);
  canvas.translate(side * margin, side * margin);
  painter.paint(canvas, Size.square(body));
  final image = await recorder.endRecording().toImage(side, side);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// A Windows icon of PNG entries, one per size (Vista and later read these).
Uint8List ico(List<(int, Uint8List)> images) {
  final out = BytesBuilder();
  final header = ByteData(6)
    ..setUint16(2, 1, Endian.little) // an icon
    ..setUint16(4, images.length, Endian.little);
  out.add(header.buffer.asUint8List());
  var offset = 6 + 16 * images.length;
  for (final (side, bytes) in images) {
    final entry = ByteData(16)
      ..setUint8(0, side >= 256 ? 0 : side) // 0 means 256
      ..setUint8(1, side >= 256 ? 0 : side)
      ..setUint16(4, 1, Endian.little) // colour planes
      ..setUint16(6, 32, Endian.little) // bits per pixel
      ..setUint32(8, bytes.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(entry.buffer.asUint8List());
    offset += bytes.length;
  }
  for (final (_, bytes) in images) {
    out.add(bytes);
  }
  return out.toBytes();
}

void write(String path, List<int> bytes) =>
    (File(path)..parent.createSync(recursive: true)).writeAsBytesSync(bytes);

void main() {
  testWidgets('write the app icons', (tester) async {
    await tester.runAsync(() async {
      const full = MarkPainter(background: MarkColors.teal);
      // Android: legacy squares, and the adaptive layers (108 dp; the card
      // inside the 66 dp safe circle, so no launcher mask cuts it).
      const res = 'android/app/src/main/res';
      for (final (density, scale) in [
        ('mdpi', 1.0),
        ('hdpi', 1.5),
        ('xhdpi', 2.0),
        ('xxhdpi', 3.0),
        ('xxxhdpi', 4.0),
      ]) {
        final dir = p.join(res, 'mipmap-$density');
        write(p.join(dir, 'ic_launcher.png'), await png((48 * scale).round(), full));
        final side = (108 * scale).round();
        write(
          p.join(dir, 'ic_launcher_foreground.png'),
          await png(side, const MarkPainter(inset: 0.22, ink: MarkColors.ribbon)),
        );
        write(
          p.join(dir, 'ic_launcher_monochrome.png'),
          await png(side, const MarkPainter(inset: 0.22, mono: true)),
        );
      }
      write(p.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), utf8.encode(_adaptive));
      write(p.join(res, 'values', 'ic_launcher_background.xml'), utf8.encode(_background));
      // Windows.
      write(
        'windows/runner/resources/app_icon.ico',
        ico([
          for (final side in [16, 24, 32, 48, 64, 128, 256]) (side, await png(side, full)),
        ]),
      );
      // macOS: Apple's grid, an 824-wide body on a 1024 canvas.
      const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final side in [16, 32, 64, 128, 256, 512, 1024]) {
        write(p.join(mac, 'app_icon_$side.png'), await png(side, full, margin: 100 / 1024));
      }
      // iOS: full squares without transparency; iOS rounds them itself.
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final contents = jsonDecode(File(p.join(ios, 'Contents.json')).readAsStringSync()) as Map;
      for (final image in (contents['images'] as List).cast<Map<String, Object?>>()) {
        final points = double.parse('${image['size']}'.split('x').first);
        final scale = double.parse('${image['scale']}'.replaceAll('x', ''));
        write(
          p.join(ios, '${image['filename']}'),
          await png(
            (points * scale).round(),
            const MarkPainter(radius: 0, background: MarkColors.teal),
            opaque: true,
          ),
        );
      }
    });
  });
}

const _adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Written by tool/make_icons_test.dart from Notelore's mark (#340). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''';

const _background = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Written by tool/make_icons_test.dart: the mark's teal (#340). -->
<resources>
    <color name="ic_launcher_background">#0D9488</color>
</resources>
''';
