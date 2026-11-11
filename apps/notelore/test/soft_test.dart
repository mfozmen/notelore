import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/soft.dart';
import 'package:notelore/src/theme.dart';

import 'theme_test.dart' show contrast;

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
        matchesSemantics(
          label: 'Notes',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byTooltip('Chat')),
        matchesSemantics(
          label: 'Chat',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byTooltip('Notes'));
      expect(picked, [1]);
      // A screen reader activates it, and a keyboard can reach and press it.
      tester.semantics.tap(find.semantics.byLabel('Chat'));
      expect(picked, [1, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picked.length, 3);
      // Every tab keeps the 48-point target.
      expect(tester.getSize(find.byTooltip('Notes')).height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });
  }

  const four = [
    (AppIcons.chat, AppIcons.chatActive, 'Chat'),
    (AppIcons.note, AppIcons.noteActive, 'Notes'),
    (AppIcons.calendar, AppIcons.calendarActive, 'Calendar'),
    (AppIcons.person, AppIcons.personActive, 'About me'),
  ];

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the bar on a $width-point phone at ${scale}x text: a tall orb, the tabs close', (
        tester,
      ) async {
        tester.view
          ..physicalSize = Size(width, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: noteloreTheme(Brightness.dark),
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: Scaffold(
                bottomNavigationBar: SoftNavBar(
                  destinations: four,
                  selected: 0,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        final bar = tester.getRect(
          find.descendant(
            of: find.byType(SoftNavBar),
            matching: find.byWidgetPredicate(
              (w) => w is DecoratedBox && w.decoration is ShapeDecoration,
            ),
          ),
        );
        expect(bar.height, SoftNavBar.height);
        // As wide as the design's 360-point frame draws it, centred on a wider phone.
        expect(bar.width, 328);
        expect(bar.center.dx, width / 2);
        final orb = tester.getRect(
          find.descendant(of: find.byTooltip('Chat'), matching: find.byType(DecoratedBox)),
        );
        expect(orb.height, greaterThanOrEqualTo(44));
        // On the 4/8 grid: the bar's inset, and the orb's room around its icon and label.
        expect(orb.left - bar.left, Gap.s);
        final orbIcon = find
            .descendant(of: find.byTooltip('Chat'), matching: find.byType(Icon))
            .first;
        expect(tester.getRect(orbIcon).left - orb.left, Gap.m);
        expect(orb.right - tester.getRect(find.text('Chat')).right, Gap.m);
        for (final label in ['Notes', 'Calendar', 'About me']) {
          expect(tester.getSize(find.byTooltip(label)).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(find.byTooltip(label)).width, greaterThanOrEqualTo(48));
        }
        expect(bar.right - tester.getRect(find.byTooltip('About me')).right, lessThanOrEqualTo(12));
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('a soft round button: a filled circle in a 48-point target ($brightness)', (
      tester,
    ) async {
      final colors = noteloreTheme(brightness).colorScheme;
      await _pump(
        tester,
        IconButton(
          style: softRound(colors),
          tooltip: 'Menu',
          icon: const Icon(AppIcons.menu),
          onPressed: () {},
        ),
        brightness: brightness,
      );
      final button = find.byType(IconButton);
      final material = find.descendant(of: button, matching: find.byType(Material));
      expect(tester.widget<Material>(material).color, colors.surfaceContainerLow);
      expect(
        tester.widget<Material>(material).shape,
        softBorder(colors, BorderRadius.circular(19)),
      );
      expect(tester.getSize(material), const Size.square(38));
      expect(tester.getSize(button), const Size.square(48));
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

  for (final brightness in Brightness.values) {
    testWidgets('the off switch: knob and track edge meet 3:1 (WCAG 1.4.11) ($brightness)', (
      tester,
    ) async {
      await _pump(tester, const SoftSwitch(value: false, enabled: true), brightness: brightness);
      final colors = noteloreTheme(brightness).colorScheme;
      final boxes = tester
          .widgetList<Container>(
            find.descendant(of: find.byType(SoftSwitch), matching: find.byType(Container)),
          )
          .map((c) => c.decoration! as BoxDecoration)
          .toList();
      final track = boxes.first, knob = boxes.last;
      final edge = (track.border! as Border).top.color;
      // The switch sits on a card or on the page.
      for (final behind in [colors.surface, colors.surfaceContainerLow]) {
        expect(contrast(knob.color!, behind), greaterThanOrEqualTo(3), reason: 'knob');
        expect(contrast(edge, behind), greaterThanOrEqualTo(3), reason: 'track edge');
      }
    });
  }

  testWidgets('a tile whose subtitle runs past two lines has its icon beside the title', (
    tester,
  ) async {
    Future<void> tile(String subtitle) => _pump(
      tester,
      SizedBox(
        width: 320,
        child: TallTile(
          child: ListTile(
            leading: const Icon(AppIcons.shield),
            title: const Text('Share'),
            subtitle: Text(subtitle),
            trailing: const Icon(AppIcons.chevronRight),
          ),
        ),
      ),
    );
    final icon = find.byIcon(AppIcons.shield);
    double offTitle() => tester.getTopLeft(icon).dy - tester.getTopLeft(find.text('Share')).dy;
    double offMiddle() => tester.getCenter(icon).dy - tester.getCenter(find.byType(ListTile)).dy;

    await tile('Two\nlines');
    await tester.pumpAndSettle();
    expect(offMiddle(), 0); // centred, as before

    await tile('One\nTwo\nThree');
    await tester.pumpAndSettle();
    expect(offTitle(), 0);

    await tile('One line');
    await tester.pumpAndSettle();
    expect(offMiddle(), 0);
  });

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
