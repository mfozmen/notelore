import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/mark.dart';

/// [painter]'s picture at [side] pixels, as RGBA bytes.
Future<ByteData> pixels(WidgetTester tester, MarkPainter painter, int side) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size.square(side.toDouble()));
  return (await tester.runAsync(() async {
    final image = await recorder.endRecording().toImage(side, side);
    return image.toByteData();
  }))!;
}

/// The colour at ([x], [y]) of an RGBA picture [side] pixels wide.
Color at(ByteData data, int side, int x, int y) {
  final i = (y * side + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  testWidgets('the badge: teal around a white card with teal writing (#340)', (tester) async {
    final data = await pixels(tester, const MarkPainter(background: MarkColors.teal), 100);
    expect(at(data, 100, 50, 4), MarkColors.teal); // the background, above the card
    expect(at(data, 100, 30, 70), MarkColors.card); // the card
    expect(at(data, 100, 40, 39), MarkColors.teal); // the first line of writing
  });

  testWidgets('the themed icon: one colour, the writing cut out', (tester) async {
    final data = await pixels(tester, const MarkPainter(inset: 0, mono: true), 100);
    expect(at(data, 100, 30, 20).a, 1); // the card, opaque
    expect(at(data, 100, 40, 36).a, 0); // the writing, see-through
    expect(at(data, 100, 2, 2).a, 0); // no background
  });

  test('repaints only when what it draws changes', () {
    const mark = MarkPainter();
    expect(mark.shouldRepaint(const MarkPainter()), isFalse);
    expect(mark.shouldRepaint(const MarkPainter(mono: true)), isTrue);
    expect(mark.shouldRepaint(const MarkPainter(background: MarkColors.teal)), isTrue);
  });
}
