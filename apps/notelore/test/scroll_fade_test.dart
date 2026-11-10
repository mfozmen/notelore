import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/scroll_fade.dart';

void main() {
  Future<ScrollFadeState Function()> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            height: 400,
            child: ScrollFade(
              child: ListView(
                children: [
                  // A row that scrolls on its own: only the list's own scrolling counts.
                  SizedBox(
                    height: 50,
                    child: ListView(
                      key: const Key('row'),
                      scrollDirection: Axis.horizontal,
                      children: [for (var i = 0; i < 20; i++) const SizedBox(width: 100)],
                    ),
                  ),
                  for (var i = 0; i < 20; i++) const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // the first metrics arrive after layout
    return () => tester.state<ScrollFadeState>(find.byType(ScrollFade));
  }

  testWidgets('fades only the edges the list runs on under', (tester) async {
    final state = await pump(tester);
    expect((state().above, state().below), (false, true));
    await tester.drag(find.byKey(const Key('row')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect((state().above, state().below), (false, true));
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect((state().above, state().below), (true, true));
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect((state().above, state().below), (true, false));
  });

  testWidgets('a desk scrollbar paints above the mask, so its ends are never faded', (
    tester,
  ) async {
    await pump(tester);
    final mask = find.byType(ShaderMask);
    expect(find.ancestor(of: mask, matching: find.byType(Scrollbar)), findsOneWidget);
    expect(find.descendant(of: mask, matching: find.byType(Scrollbar)), findsNothing);
    // The thumb follows the list it sits beside.
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!.offset, greaterThan(0));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a phone keeps its own scroll look: no scrollbar added', (tester) async {
    await pump(tester);
    expect(find.byType(Scrollbar), findsNothing);
  }, variant: TargetPlatformVariant.mobile());

  test('the mask: clear at a faded edge, opaque elsewhere, never past the middle', () {
    final both = ScrollFade.mask(above: true, below: true, height: 240);
    expect(both.colors.map((c) => c.a), [0, 1, 1, 0]);
    expect(both.stops, [0, 0.1, 0.9, 1]);
    final none = ScrollFade.mask(above: false, below: false, height: 240);
    expect(none.colors.map((c) => c.a), [1, 1, 1, 1]);
    // Shorter than two fades: they meet in the middle.
    expect(ScrollFade.mask(above: true, below: true, height: 20).stops, [0, 0.5, 0.5, 1]);
  });
}
