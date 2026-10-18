import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/pattern_pad.dart';
import 'package:notelore/src/strings.dart';

void main() {
  Future<List<String>> pad(WidgetTester tester, {bool enabled = true}) async {
    final done = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PatternPad(strings: EnglishStrings(), enabled: enabled, onDone: done.add),
          ),
        ),
      ),
    );
    return done;
  }

  Finder dot(int number) => find.bySemanticsLabel('Dot $number');

  Future<void> draw(WidgetTester tester, List<int> dots) async {
    final gesture = await tester.startGesture(tester.getCenter(dot(dots.first)));
    for (final number in dots.skip(1)) {
      await gesture.moveTo(tester.getCenter(dot(number)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a pattern drawn through the dots is their numbers, 0 to 8', (tester) async {
    final done = await pad(tester);
    await draw(tester, [1, 5, 9, 6]);
    expect(done, ['0-4-8-5']);
    await draw(tester, [1, 2, 3]); // too few dots: nothing
    expect(done, ['0-4-8-5']);
    await draw(tester, [3, 2, 1, 2, 4]); // a dot counts once
    expect(done, ['0-4-8-5', '2-1-0-3']);
  });

  testWidgets('without dragging: tap the dots in turn, then Done; Clear starts over', (
    tester,
  ) async {
    final done = await pad(tester);
    for (final number in [7, 8, 9]) {
      await tester.tap(dot(number));
      await tester.pump();
    }
    expect(tester.getSemantics(dot(7)).flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(tester.getSemantics(dot(7)).flagsCollection.isSelected, Tristate.isFalse);
    for (final number in [7, 8, 9, 6]) {
      await tester.tap(dot(number));
      await tester.pump();
    }
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(done, ['6-7-8-5']);
  });

  testWidgets('Clear shows once a dot is chosen; the pad says how many are (#412)', (tester) async {
    await pad(tester);
    bool clearShown() => tester.widget<Visibility>(find.byKey(const Key('pattern-clear'))).visible;
    expect(clearShown(), isFalse);
    for (final number in [1, 2, 3]) {
      await tester.tap(dot(number));
      await tester.pump();
    }
    expect(clearShown(), isTrue);
    expect(find.bySemanticsLabel('3 dots chosen'), findsOneWidget);
  });

  testWidgets('a drag the system calls off draws nothing', (tester) async {
    final done = await pad(tester);
    final gesture = await tester.startGesture(tester.getCenter(dot(1)));
    await gesture.moveTo(tester.getCenter(dot(5)));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(done, isEmpty);
    expect(tester.getSemantics(dot(1)).flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('a disabled pad (a wait after wrong tries) takes nothing', (tester) async {
    final done = await pad(tester, enabled: false);
    await draw(tester, [1, 5, 9, 6]);
    await tester.tap(dot(1));
    await tester.pump();
    expect(done, isEmpty);
    expect(patternOf([0, 4, 8]), '0-4-8');
  });
}
