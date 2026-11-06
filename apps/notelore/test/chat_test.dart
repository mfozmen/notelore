import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/theme.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

/// The Kil and Orman look of the chat (#782); what it does is tested in app_test.
void main() {
  void dark(WidgetTester tester) {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> say(WidgetTester tester, String message) async {
    await tester.enterText(find.byKey(const Key('message')), message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
  }

  BoxDecoration? decorationAbove(WidgetTester tester, Finder finder) {
    final box = tester.widget<Container>(
      find.ancestor(of: finder, matching: find.byType(Container)).first,
    );
    return box.decoration as BoxDecoration?;
  }

  final orb = find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle &&
        (w.decoration as BoxDecoration).gradient is RadialGradient,
  );

  testWidgets('the answer sits on the page; the message on its own tint and edge', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await say(tester, 'Kitaplari rafa koy');
    final theme = Theme.of(tester.element(find.byType(MarkdownBody)));
    final tokens = theme.extension<NoteloreTokens>()!;
    expect(decorationAbove(tester, find.byType(MarkdownBody)), isNull);
    final mine = decorationAbove(tester, find.text('Kitaplari rafa koy'))!;
    expect(mine.color, theme.colorScheme.primaryContainer);
    expect(mine.border, Border.all(color: tokens.mineBorder));
    expect(
      mine.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(6),
      ),
    );
    // The message actions are quiet: small, in the muted colour.
    final copy = tester.widget<Icon>(find.byIcon(Icons.copy).first);
    expect(copy.size, 18);
    expect(copy.color, theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('the talk button is a glowing orb, in Orman too', (tester) async {
    phone(tester);
    dark(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    final decoration = tester.widget<DecoratedBox>(orb).decoration as BoxDecoration;
    expect((decoration.gradient! as RadialGradient).colors[1], colors.primary);
    expect(decoration.boxShadow!.single.color, colors.primary.withValues(alpha: .45));
    expect(find.descendant(of: orb, matching: find.byTooltip('Tap or hold to talk')), findsOne);
    // The button's own Material sits inside the orb, so its splash, hover and
    // focus overlays paint above the gradient, not under it.
    final ink = find.descendant(of: orb, matching: find.byType(InkWell));
    final inner = find.descendant(of: orb, matching: find.byType(Material));
    expect(find.ancestor(of: ink, matching: inner), findsOne);
  });

  testWidgets('one rounded field holds the attach button, the box and the orb', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    final field = find.ancestor(of: orb, matching: find.byKey(const Key('composer')));
    final decoration = tester.widget<Container>(field).decoration! as BoxDecoration;
    expect(decoration.color, colors.surfaceContainerLow);
    expect(decoration.borderRadius, BorderRadius.circular(28));
    expect(find.descendant(of: field, matching: find.byTooltip('Attach a file')), findsOne);
    expect(find.descendant(of: field, matching: find.byKey(const Key('message'))), findsOne);
  });

  testWidgets('the starters are bordered cards with the accent arrow', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    final style = tester.widget<OutlinedButton>(find.byType(OutlinedButton).first).style!;
    expect(style.backgroundColor!.resolve({}), colors.surfaceContainerLow);
    expect(
      style.shape!.resolve({}),
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.north_west).first).color, colors.primary);
  });

  testWidgets('the model is a bordered pill with the accent spark', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    final spark = find.byIcon(Icons.auto_awesome_outlined);
    expect(tester.widget<Icon>(spark).color, colors.primary);
    final pill = tester.widget<Container>(
      find.ancestor(of: spark, matching: find.byType(Container)).first,
    );
    expect(
      pill.decoration,
      ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
      ),
    );
  });

  testWidgets('a banner is a card-coloured strip with the accent icon', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    harness.models = ['model-a', 'model-b'];
    await session.refreshModels();
    await tester.pumpAndSettle();
    final colors = Theme.of(tester.element(find.byType(MaterialBanner))).colorScheme;
    final strip = tester.widget<Material>(
      find.descendant(of: find.byType(MaterialBanner), matching: find.byType(Material)).first,
    );
    expect(strip.color, colors.surfaceContainerLow);
    expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber)).color, colors.primary);
  });
}
