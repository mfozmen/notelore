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
  testWidgets('the badge: a white ribbon on teal, its fold in mint (#568)', (tester) async {
    final data = await pixels(
      tester,
      const MarkPainter(background: MarkColors.teal, inset: 0),
      100,
    );
    expect(at(data, 100, 50, 4), MarkColors.teal); // the badge above the ribbon
    expect(at(data, 100, 25, 50), MarkColors.ribbon); // the left upright
    expect(at(data, 100, 75, 50), MarkColors.ribbon); // the right upright
    expect(at(data, 100, 70, 70), MarkColors.fold); // the turned underside
    expect(at(data, 100, 26, 20), MarkColors.teal); // the bookmark notch
  });

  testWidgets('without a badge the ribbon is teal on the page (#568)', (tester) async {
    final data = await pixels(tester, const MarkPainter(inset: 0), 100);
    expect(at(data, 100, 50, 4).a, 0); // no square
    expect(at(data, 100, 25, 50), MarkColors.teal); // the ribbon
    expect(at(data, 100, 70, 70), MarkColors.fold); // the fold
  });

  testWidgets('a light ribbon over its own teal layer, as Android draws it (#568)', (tester) async {
    final data = await pixels(tester, const MarkPainter(inset: 0, ink: MarkColors.ribbon), 100);
    expect(at(data, 100, 25, 50), MarkColors.ribbon); // the ribbon
    expect(at(data, 100, 50, 4).a, 0); // no square of its own
  });

  testWidgets('the themed icon: one colour, the ribbon silhouette (#568)', (tester) async {
    final data = await pixels(tester, const MarkPainter(inset: 0, mono: true), 100);
    expect(at(data, 100, 25, 50).a, 1); // the left upright
    expect(at(data, 100, 70, 70).a, 1); // the fold stays solid
    expect(at(data, 100, 26, 20).a, 0); // the notch
    expect(at(data, 100, 2, 2).a, 0); // no background
  });

  testWidgets('at 16 px the N and its notch still read (#568)', (tester) async {
    final data = await pixels(tester, const MarkPainter(background: MarkColors.teal, inset: 0), 16);
    expect(at(data, 16, 4, 8), MarkColors.ribbon); // the left upright
    expect(at(data, 16, 12, 8), MarkColors.ribbon); // the right upright
    expect(at(data, 16, 4, 2), MarkColors.teal); // the notch
  });

  test('repaints only when what it draws changes', () {
    const mark = MarkPainter();
    expect(mark.shouldRepaint(const MarkPainter()), isFalse);
    expect(mark.shouldRepaint(const MarkPainter(mono: true)), isTrue);
    expect(mark.shouldRepaint(const MarkPainter(ink: MarkColors.ribbon)), isTrue);
    expect(mark.shouldRepaint(const MarkPainter(fold: MarkColors.foldOnLight)), isTrue);
    expect(mark.shouldRepaint(const MarkPainter(background: MarkColors.teal)), isTrue);
  });
}
