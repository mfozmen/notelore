import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/soft.dart';
import 'package:notelore/src/theme.dart';

Future<void> _pump(WidgetTester tester, Widget child, {Brightness brightness = Brightness.light}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: noteloreTheme(brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  const tabs = [
    (AppIcons.chat, AppIcons.chatActive, 'Chat'),
    (AppIcons.note, AppIcons.noteActive, 'Notes'),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the tab bar: the chosen tab shows its label, the others a tooltip ($brightness)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final picked = <int>[];
      await _pump(
        tester,
        SoftNavBar(destinations: tabs, selected: 0, onSelected: picked.add),
        brightness: brightness,
      );
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Notes'), findsNothing); // icon only
      expect(find.byTooltip('Notes'), findsOneWidget);
      expect(
        tester.getSemantics(find.byTooltip('Notes')),
        matchesSemantics(label: 'Notes', isButton: true, hasSelectedState: true),
      );
      expect(
        tester.getSemantics(find.byTooltip('Chat')),
        matchesSemantics(label: 'Chat', isButton: true, hasSelectedState: true, isSelected: true),
      );
      await tester.tap(find.byTooltip('Notes'));
      expect(picked, [1]);
      // Every tab keeps the 48-point target.
      expect(tester.getSize(find.byTooltip('Notes')).height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });
  }

  testWidgets('a press dims and shrinks, and comes back on release or cancel', (tester) async {
    await _pump(
      tester,
      const Pressed(
        child: ColoredBox(color: Colors.red, child: SizedBox.square(dimension: 48)),
      ),
    );
    double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(Pressed)));
    await tester.pump();
    expect(opacity(), lessThan(1));
    await gesture.up();
    await tester.pump();
    expect(opacity(), 1);
    final again = await tester.startGesture(tester.getCenter(find.byType(Pressed)));
    await tester.pump();
    await again.cancel();
    await tester.pump();
    expect(opacity(), 1);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the switch toggles from its row or itself, and says its state ($brightness)', (
      tester,
    ) async {
      var on = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SoftSwitchTile(
            title: const Text('Web search'),
            subtitle: const Text('Looks things up'),
            secondary: const Icon(AppIcons.web),
            value: on,
            onChanged: (value) => setState(() => on = value),
          ),
        ),
        brightness: brightness,
      );
      await tester.tap(find.text('Web search'));
      await tester.pumpAndSettle();
      expect(on, isTrue);
      await tester.tap(find.byType(SoftSwitch));
      await tester.pumpAndSettle();
      expect(on, isFalse);
      expect(
        tester.getSemantics(find.byType(SoftSwitchTile)),
        matchesSemantics(
          label: 'Web search\nLooks things up',
          hasToggledState: true,
          isButton: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(tester.getSize(find.byType(SoftSwitchTile)).height, greaterThanOrEqualTo(48));
    });
  }

  testWidgets('a switch without onChanged is dimmed and does nothing', (tester) async {
    await _pump(tester, const SoftSwitchTile(title: Text('Off'), value: true, onChanged: null));
    await tester.tap(find.byType(SoftSwitch));
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity).last).opacity, lessThan(1));
    expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
  });

  testWidgets('a choice: an orb with a dot when chosen, a ring when not', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SoftRadio(selected: true, semanticLabel: 'In use'),
          SoftRadio(selected: false),
        ],
      ),
    );
    final chosen = find.byType(SoftRadio).first;
    expect(find.descendant(of: chosen, matching: find.byType(Container)), findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(SoftRadio).last, matching: find.byType(Container)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(chosen),
      matchesSemantics(label: 'In use', hasCheckedState: true, isChecked: true),
    );
  });
}
