import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/chat.dart' show FieldDecoration, Orb, orbEdge;
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore/src/notes.dart';
import 'package:notelore/src/strings.dart' show AppLanguage;
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'desktop_test.dart' show desktop;
import 'support.dart';

/// The model's turn that runs [calls] (name and input), then answers [answer].
List<Object> calls(List<(String, Map<String, Object?>)> calls, String answer) => [
  AgentResponse([
    for (final (i, (name, input)) in calls.indexed)
      {'type': 'tool_use', 'id': 't$i', 'name': name, 'input': input},
  ], 'tool_use'),
  answer,
];

void dark(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Future<void> say(WidgetTester tester, String message, {String send = 'Send'}) async {
  await tester.enterText(find.byKey(const Key('message')), message);
  await tester.pump();
  await tester.tap(find.byTooltip(send));
  await tester.pumpAndSettle();
}

/// The Kil and Orman look of the chat (#782); what it does is tested in app_test.
void main() {
  testWidgets('the message field paints its edge inside, as two softened rounded rects (#881)', (
    tester,
  ) async {
    const edge = BorderSide(color: Color(0xFFFF8800), width: 2);
    const field = FieldDecoration(color: Color(0xFF101010), edge: edge, radius: 28);
    // Equal fields compare equal, so a rebuild does not repaint the box.
    final same = FieldDecoration(color: field.color, edge: edge, radius: 28);
    expect(same, field);
    expect(same.hashCode, field.hashCode);
    expect(
      same == const FieldDecoration(color: Color(0xFF101010), edge: edge, radius: 20),
      isFalse,
    );
    await tester.pumpWidget(
      const Center(
        child: SizedBox(width: 200, height: 56, child: DecoratedBox(decoration: field)),
      ),
    );
    final outer = RRect.fromLTRBR(0, 0, 200, 56, const Radius.circular(28));
    expect(
      find.byType(DecoratedBox),
      paints
        ..rrect(rrect: outer, color: edge.color, hasMaskFilter: true)
        ..rrect(rrect: outer.deflate(2), color: field.color, hasMaskFilter: true),
    );
  });

  testWidgets('the orb fades its own rim over one device pixel (#881)', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: noteloreTheme(Brightness.light),
        home: const Center(child: Orb(SizedBox.square(dimension: 48))),
      ),
    );
    final mask = tester.widget<ShaderMask>(
      find.descendant(of: find.byType(Orb), matching: find.byType(ShaderMask)),
    );
    expect(mask.blendMode, BlendMode.dstIn);
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(ShaderMask), matching: find.byType(DecoratedBox)).first,
    );
    expect((box.decoration as BoxDecoration).shape, BoxShape.rectangle);

    final edge = orbEdge(const Size.square(48), 2);
    // Half a device pixel (.25) either side of the 24-point rim.
    expect(edge.radius, 24.25 / 48);
    expect(edge.stops, [0, 23.75 / 24.25, 1]);
    expect(edge.colors, [Colors.white, Colors.white, Colors.transparent]);
  });

  group('write receipts (#791)', () {
    Harness atlas(List<Object> answers) {
      final harness = Harness(answers: answers);
      createNote(harness.paths.notes.path, 'project', 'Project Atlas', today: today);
      return harness;
    }

    final decides = calls([
      ('record_decision', {'slug': 'project-atlas', 'topic': 'database', 'value': 'Postgres'}),
    ], 'Saved.');
    final label = find.text('PROJECT ATLAS · DECISION ADDED');

    testWidgets('a pill under the answer names the note; Open pushes it on a phone', (
      tester,
    ) async {
      phone(tester);
      await pumpApp(tester, atlas([...decides, 'Hello.']));
      await connect(tester, key: 'k');
      await say(tester, 'Atlas: we picked Postgres');
      expect(label, findsOneWidget);
      final open = find.widgetWithText(TextButton, 'Open');
      expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
      // Hover and press tint the pill's own end, never the 48-point target around it.
      final ink = tester.getRect(find.descendant(of: open, matching: find.byType(InkWell)));
      final pill = tester.getRect(
        find.descendant(
          of: find.ancestor(of: label, matching: find.byType(Stack)).first,
          matching: find.byType(Ink),
        ),
      );
      expect((ink.top, ink.bottom), (pill.top, pill.bottom));
      expect(ink.right, pill.right);
      final theme = Theme.of(tester.element(label));
      expect(tester.widget<Text>(label).style!.color, theme.colorScheme.primary);
      expect(
        tester.getSemantics(open),
        matchesSemantics(label: 'Open Project Atlas', isButton: true, hasTapAction: true),
      );
      await say(tester, 'hi'); // an answer that wrote nothing has none
      expect(find.text('Open'), findsOneWidget);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(WritableNoteView), findsOneWidget);
      expect(find.textContaining('Postgres'), findsOneWidget);
    });

    testWidgets('on the desktop Open shows the note in the Notes reader', (tester) async {
      desktop(tester, 1280);
      await pumpApp(tester, atlas(decides));
      await connect(tester, key: 'k');
      await say(tester, 'Atlas: we picked Postgres');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(find.byType(NoteView), findsOneWidget);
      expect(find.byType(WritableNoteView), findsNothing); // the pane, not a page
      // Back in the Notes tab later, the list shows with no note forced open.
      await tester.tap(tab('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(tab('Notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteView), findsNothing);
    });

    testWidgets('a note gone since says so; an archived one has no Open', (tester) async {
      phone(tester);
      final session = await pumpApp(
        tester,
        atlas([
          ...decides,
          ...calls([
            ('archive', {'slug': 'project-atlas'}),
          ], 'Archived.'),
        ]),
      );
      await connect(tester, key: 'k');
      await say(tester, 'Atlas: we picked Postgres');
      File(notePath(session.paths.notes.path, 'project', 'project-atlas')).deleteSync();
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('That note is no longer there.'), findsOneWidget);
      expect(find.byType(WritableNoteView), findsNothing);
      createNote(session.paths.notes.path, 'project', 'Project Atlas', today: today);
      await say(tester, 'archive Atlas');
      expect(find.text('PROJECT ATLAS · ARCHIVED'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget); // the first answer's only
    });

    testWidgets('in Turkish and at night: the pill on the card colour, its edge', (tester) async {
      phone(tester);
      dark(tester);
      final session = await pumpApp(tester, atlas(decides));
      await connect(tester, key: 'k');
      session.setLanguage(AppLanguage.tr);
      await tester.pumpAndSettle();
      await say(tester, 'Atlas: Postgres seçtik', send: 'Gönder');
      final turkish = find.text('PROJECT ATLAS · KARAR EKLENDİ');
      expect(turkish, findsOneWidget);
      final colors = Theme.of(tester.element(turkish)).colorScheme;
      expect(colors.brightness, Brightness.dark);
      final pill = tester.widget<Ink>(
        find.descendant(
          of: find.ancestor(of: turkish, matching: find.byType(Stack)).first,
          matching: find.byType(Ink),
        ),
      );
      expect(
        pill.decoration,
        ShapeDecoration(
          color: colors.surfaceContainerLow,
          shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
        ),
      );
      expect(find.text('Aç'), findsOneWidget);
    });
  });

  group('decision source cards (#792)', () {
    Harness atlas(List<Object> answers) {
      final harness = Harness(
        answers: [
          ...calls([
            (
              'record_decision',
              {
                'slug': 'project-atlas',
                'topic': 'database',
                'value': 'Postgres',
                'reason': 'Mature and well known.',
              },
            ),
            ('record_decision', {'slug': 'project-atlas', 'topic': 'hosting', 'value': 'Fly'}),
          ], 'Saved.'),
          ...answers,
        ],
      );
      createNote(harness.paths.notes.path, 'project', 'Project Atlas', today: today);
      return harness;
    }

    final asks = calls([
      ('get_decision', {'slug': 'project-atlas', 'topic': 'database'}),
      ('get_decision', {'slug': 'project-atlas', 'topic': 'hosting'}),
    ], 'You picked Postgres and Fly.');
    final open = find.text('Open note →');

    Future<void> asked(WidgetTester tester, Harness harness) async {
      await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      await say(tester, 'Atlas: Postgres, because it is mature; Fly for hosting');
      expect(find.text('Source: Project Atlas'), findsNothing); // a write has receipts only
      await say(tester, 'Which database and hosting?');
    }

    testWidgets('each decision the answer used shows as the index has it; Open pushes the note', (
      tester,
    ) async {
      phone(tester);
      await asked(tester, atlas(asks));
      expect(find.text('DATABASE'), findsOneWidget);
      expect(find.text('HOSTING'), findsOneWidget);
      expect(find.text('30 Sep'), findsNWidgets(2));
      final value = find.text('Postgres');
      expect(tester.widget<Text>(value).style!.fontFamily, 'Fraunces');
      final theme = Theme.of(tester.element(value));
      final tokens = theme.extension<NoteloreTokens>()!;
      Color? color(String text) => tester.widget<Text>(find.text(text).first).style!.color;
      // A found decision is the coloured card, its words a hierarchy (#854).
      expect(
        [color('DATABASE'), color('30 Sep'), color('Postgres'), color('Mature and well known.')],
        [tokens.hotLabel, tokens.hotLabel, tokens.hotValue, tokens.hotReason],
      );
      expect(color('Source: Project Atlas'), tokens.hotSource);
      expect(tester.widget<Text>(open.first).style!.decoration, TextDecoration.underline);
      final link = tester.widget<RichText>(
        find.descendant(of: open.first, matching: find.byType(RichText)),
      );
      expect(link.text.style!.color, tokens.hotLink);
      // The accent ring would vanish on the clay fill; a keyboard focus rings in the link colour.
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      expect(
        TextButtonTheme.of(tester.element(open.first)).style!.side!.resolve({WidgetState.focused}),
        BorderSide(color: tokens.hotLink, width: 2),
      );
      expect(find.ancestor(of: value, matching: find.byType(Card)), findsOneWidget);
      expect(
        find.ancestor(
          of: value,
          matching: find.byWidgetPredicate(
            (w) => w is Ink && w.decoration == BoxDecoration(gradient: tokens.hot),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Source: Project Atlas'), findsNWidgets(2));
      expect(open, findsNWidgets(2));
      final button = find.ancestor(of: open.first, matching: find.byType(TextButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      // Its hover stays clear of the card's edge.
      final edge = tester.getRect(
        find
            .descendant(
              of: find.ancestor(of: value, matching: find.byType(Card)),
              matching: find.byType(Material),
            )
            .first,
      );
      final hover = tester.getRect(button.first);
      expect(edge.right - hover.right, Gap.s);
      expect(edge.bottom - hover.bottom, Gap.s);
      expect(
        tester.getSemantics(button),
        matchesSemantics(
          label: 'Open note Project Atlas',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(open.first);
      await tester.pumpAndSettle();
      expect(find.byType(WritableNoteView), findsOneWidget);
    });

    testWidgets('on the desktop Open shows the note in the Notes reader', (tester) async {
      desktop(tester, 1280);
      await asked(tester, atlas(asks));
      await tester.tap(open.first);
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(find.byType(NoteView), findsOneWidget);
    });

    testWidgets('in Turkish and at night, the footer in Turkish', (tester) async {
      phone(tester);
      dark(tester);
      final session = await pumpApp(tester, atlas(asks));
      await connect(tester, key: 'k');
      session.setLanguage(AppLanguage.tr);
      await tester.pumpAndSettle();
      await say(tester, 'Hangi veritabanı?', send: 'Gönder');
      expect(find.text('Kaynak: Project Atlas'), findsNothing);
      await say(tester, 'Hangi veritabanı?', send: 'Gönder');
      expect(find.text('Kaynak: Project Atlas'), findsNWidgets(2));
      expect(find.text('Notu aç →'), findsNWidgets(2));
      expect(find.text('30 Eyl'), findsNWidgets(2));
    });
  });

  BoxDecoration? decorationAbove(WidgetTester tester, Finder finder) {
    final box = tester.widget<Container>(
      find.ancestor(of: finder, matching: find.byType(Container)).first,
    );
    return box.decoration as BoxDecoration?;
  }

  final orb = find.byType(Orb);

  testWidgets('the answer sits on the page; the message on its own tint and edge', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await say(tester, 'Kitaplari rafa koy');
    final theme = Theme.of(tester.element(answerBody));
    final tokens = theme.extension<NoteloreTokens>()!;
    expect(decorationAbove(tester, answerBody), isNull);
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
    // The message actions are quiet: small, in the muted colour a little dimmed,
    // still on full-size targets.
    final copy = tester.widget<Icon>(find.byIcon(AppIcons.copy).first);
    expect(copy.size, 17);
    expect(copy.color, theme.colorScheme.onSurfaceVariant.withValues(alpha: .8));
    final target = find.ancestor(
      of: find.byIcon(AppIcons.copy).first,
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(target), const Size(48, 48));
  });

  group('an answer (#827)', () {
    const answer =
        'Planned for Notelore:\n\n'
        '- A watch app.\n'
        '- Rename the web search setting.\n'
        '  - and its hint\n'
        '- Fix the tyre note.\n\n'
        'These are notes; there is no to-do.';
    final card = find.ancestor(of: find.text('A watch app.'), matching: find.byType(Card));

    testWidgets('reads a step smaller, with room between its lines', (tester) async {
      phone(tester);
      await pumpApp(tester, Harness(answers: [answer]));
      await connect(tester, key: 'k');
      await say(tester, 'plans?');
      final body = tester.widget<MarkdownBody>(answerBody).styleSheet!.p!;
      expect(body.fontSize, AnswerStyle.size);
      expect(AnswerStyle.size, 14); // a step under the person's 15 sp bubble
      expect(body.height, AnswerStyle.lineHeight);
    });

    testWidgets('a list sits on a soft card: a row per item, a hairline between, mono numbers', (
      tester,
    ) async {
      phone(tester);
      dark(tester);
      await pumpApp(tester, Harness(answers: [answer]));
      await connect(tester, key: 'k');
      await say(tester, 'plans?');
      expect(card, findsOneWidget);
      final theme = Theme.of(tester.element(card));
      for (final item in ['A watch app.', 'Rename the web search setting.', 'Fix the tyre note.']) {
        expect(find.descendant(of: card, matching: find.text(item)), findsOneWidget);
      }
      expect(find.descendant(of: card, matching: find.byType(Divider)), findsNWidgets(2));
      final one = tester.widget<Text>(find.text('01'));
      expect(one.style!.fontFamily, 'JetBrains Mono');
      expect(one.style!.color, theme.colorScheme.primary);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      // A nested list keeps its plain bullet, inside its item's row.
      expect(find.descendant(of: card, matching: find.text('•')), findsOneWidget);
      // The lead-in and the closing line are not on the card; the closing one is quieter.
      expect(find.descendant(of: card, matching: find.text('Planned for Notelore:')), findsNothing);
      final closing = find.text('These are notes; there is no to-do.');
      expect(find.descendant(of: card, matching: closing), findsNothing);
      expect(
        tester.widget<Opacity>(find.ancestor(of: closing, matching: find.byType(Opacity))).opacity,
        AnswerStyle.closing,
      );
      expect(
        find.ancestor(of: find.text('Planned for Notelore:'), matching: find.byType(Opacity)),
        findsNothing,
      );
      // A screen reader hears a list, item by item.
      bool role(Widget w, SemanticsRole r) => w is Semantics && w.properties.role == r;
      expect(find.byWidgetPredicate((w) => role(w, SemanticsRole.list)), findsOneWidget);
      expect(find.byWidgetPredicate((w) => role(w, SemanticsRole.listItem)), findsNWidgets(3));
    });

    testWidgets('an ordered list counts from its own start; 2x text keeps the numbers whole', (
      tester,
    ) async {
      phone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, Harness(answers: ['Next:\n\n3. Ship\n   1. Build\n4. Tell']));
      await connect(tester, key: 'k');
      await say(tester, 'next?');
      expect(find.text('03'), findsOneWidget);
      expect(find.text('04'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget); // a nested one keeps its own
      // One line: the number's column grows with the text.
      final number = tester.getSize(find.text('03'));
      expect(
        number.height,
        lessThan(tester.widget<Text>(find.text('03')).style!.fontSize! * 2 * 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide window the card keeps to the answer\'s readable line', (tester) async {
      desktop(tester, 1600);
      await pumpApp(tester, Harness(answers: [answer]));
      await connect(tester, key: 'k');
      await say(tester, 'plans?');
      final context = tester.element(answerBody);
      expect(
        tester.getSize(card).width,
        lessThanOrEqualTo(Layout.bubbleFor(context, MediaQuery.sizeOf(context).width)),
      );
    });

    testWidgets('a quote closing an answer after a list is not dimmed', (tester) async {
      phone(tester);
      await pumpApp(tester, Harness(answers: ['- One\n- Two\n\n> Keep the old server.']));
      await connect(tester, key: 'k');
      await say(tester, 'hi');
      expect(find.descendant(of: answerBody, matching: find.byType(Opacity)), findsNothing);
    });

    testWidgets('an answer with no list has no card and nothing dimmed', (tester) async {
      phone(tester);
      await pumpApp(tester, Harness(answers: ['Saved.\n\nAnything else?']));
      await connect(tester, key: 'k');
      await say(tester, 'hi');
      expect(find.descendant(of: answerBody, matching: find.byType(Card)), findsNothing);
      expect(find.descendant(of: answerBody, matching: find.byType(Opacity)), findsNothing);
    });
  });

  testWidgets('the talk button is a glowing orb, in Orman too', (tester) async {
    phone(tester);
    dark(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    BoxDecoration decoration(int i) =>
        tester
                .widgetList<DecoratedBox>(
                  find.descendant(of: orb, matching: find.byType(DecoratedBox)),
                )
                .elementAt(i)
                .decoration
            as BoxDecoration;
    expect(decoration(0).boxShadow!.single.color, colors.primary.withValues(alpha: .45));
    expect((decoration(1).gradient! as RadialGradient).colors[1], colors.primary);
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
    final decoration = tester.widget<Container>(field).decoration! as FieldDecoration;
    expect(decoration.color, colors.surfaceContainerLow);
    expect(decoration.radius, 28);
    expect(find.descendant(of: field, matching: find.byTooltip('Attach a file')), findsOne);
    expect(find.descendant(of: field, matching: find.byKey(const Key('message'))), findsOne);
  });

  testWidgets('the paperclip, the text and the orb sit on the box centre line (#873)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final field = find.byKey(const Key('composer'));
    final message = find.byKey(const Key('message'));
    Rect box() =>
        (tester.widget<Container>(field).margin! as EdgeInsets).deflateRect(tester.getRect(field));
    final clip = find.descendant(of: find.byTooltip('Attach a file'), matching: find.byType(Icon));
    Rect line() =>
        tester.getRect(find.descendant(of: message, matching: find.byType(EditableText)));

    void centred() {
      final (b, o) = (box(), tester.getRect(orb));
      // The edge stays inside the box, on the column's edge, in both widths.
      final container = tester.widget<Container>(field);
      final edge = (container.decoration! as FieldDecoration).edge;
      expect(container.padding!.add(EdgeInsets.all(edge.width)), const EdgeInsets.all(Gap.xs));
      expect(tester.getRect(clip).center.dy, moreOrLessEquals(b.center.dy, epsilon: .5));
      // Lifted 1 dp: the face's capitals sit low in their line box.
      expect(line().center.dy, moreOrLessEquals(b.center.dy - 1, epsilon: .5));
      expect(o.center.dy, moreOrLessEquals(b.center.dy, epsilon: .5));
      // Concentric with the box's round end: the same inset above, below and on the right.
      expect(o.top - b.top, moreOrLessEquals(b.bottom - o.bottom, epsilon: .5));
      expect(b.right - o.right, moreOrLessEquals(b.bottom - o.bottom, epsilon: .5));
      expect(b.height / 2, moreOrLessEquals(Radii.field, epsilon: .5));
    }

    centred();
    final empty = box();
    await tester.enterText(message, 'Postgres');
    await tester.pumpAndSettle();
    centred();
    expect(box(), empty, reason: 'the focused edge does not grow the box');
    // Many lines: the buttons stay on the last line, the orb in the bottom corner.
    await tester.enterText(message, 'one\ntwo\nthree');
    await tester.pumpAndSettle();
    final (b, o) = (box(), tester.getRect(orb));
    // The last 24 dp line's centre, plus the same 1 dp lift as one line.
    final lastLine = line().bottom - 24 / 2;
    expect(o.center.dy, moreOrLessEquals(lastLine + 1, epsilon: .5));
    expect(tester.getRect(clip).center.dy, moreOrLessEquals(o.center.dy, epsilon: .5));
    expect(b.right - o.right, moreOrLessEquals(b.bottom - o.bottom, epsilon: .5));
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
    expect(tester.widget<Icon>(find.byIcon(AppIcons.insert).first).color, colors.primary);
  });

  testWidgets('the model is a bordered pill with the accent spark', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final colors = Theme.of(tester.element(orb)).colorScheme;
    final spark = find.byIcon(AppIcons.sparkle);
    expect(tester.widget<Icon>(spark).color, colors.primary);
    final pill = find.ancestor(of: spark, matching: find.byType(TextButton));
    final style = tester.widget<TextButton>(pill).style!;
    expect(style.backgroundColor!.resolve({}), colors.surfaceContainerLow);
    expect(style.shape!.resolve({}), StadiumBorder(side: BorderSide(color: colors.outlineVariant)));
    // A 48-point target; the hover tints only the slim pill inside it.
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(48));
    final ink = tester.getSize(find.descendant(of: pill, matching: find.byType(InkWell)));
    expect(ink.height, lessThan(36));
  });

  testWidgets('the model menu is a soft card; the current model has a check', (tester) async {
    phone(tester);
    dark(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await tester.tap(find.byTooltip('Change the model'));
    await tester.pumpAndSettle();
    final current = find.text('Claude Sonnet 5.5').last;
    final colors = Theme.of(tester.element(current)).colorScheme;
    final menu = tester.widget<Material>(
      find.ancestor(of: current, matching: find.byType(Material)).first,
    );
    expect(menu.shape, softBorder(colors, BorderRadius.circular(20)));
    expect(menu.clipBehavior, Clip.antiAlias);
    expect(find.byIcon(AppIcons.check), findsOneWidget);
    expect(
      find.ancestor(of: find.byIcon(AppIcons.check), matching: find.byType(PopupMenuItem<String>)),
      findsOneWidget,
    );
    final band = tester.widget<Ink>(find.ancestor(of: current, matching: find.byType(Ink)));
    expect((band.decoration! as BoxDecoration).color, colors.primaryContainer);
    expect(tester.widget<Text>(current).style!.color, colors.onPrimaryContainer);
    // A screen reader hears which one is in use, not only a sighted user.
    expect(tester.getSemantics(current).flagsCollection.isSelected, Tristate.isTrue);
    expect(tester.getSemantics(find.text('model-a')).flagsCollection.isSelected, Tristate.isFalse);
    final other = tester.widget<Ink>(
      find.ancestor(of: find.text('model-a'), matching: find.byType(Ink)),
    );
    expect((other.decoration! as BoxDecoration).color, isNull);
    await tester.tap(find.text('model-a'));
    await tester.pumpAndSettle();
    expect(find.text('model-a'), findsOneWidget);
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
    expect(tester.widget<Icon>(find.byIcon(AppIcons.warning)).color, colors.primary);
  });

  group('the chat rhythm (#850)', () {
    final decides = calls([
      ('record_decision', {'slug': 'project-atlas', 'topic': 'database', 'value': 'Postgres'}),
    ], 'Saved.');
    final looksUp = calls([
      ('get_decision', {'slug': 'project-atlas', 'topic': 'database'}),
    ], 'You picked Postgres.');

    /// The top of the nearest Copy icon under [edge].
    double copyUnder(WidgetTester tester, double edge) => find
        .byIcon(AppIcons.copy)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).top)
        .where((top) => top > edge - Gap.m)
        .reduce(min);

    testWidgets('after a card the actions sit a Gap under its edge, not on it', (tester) async {
      phone(tester);
      final harness = Harness(answers: [...decides, ...looksUp]);
      createNote(harness.paths.notes.path, 'project', 'Project Atlas', today: today);
      await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      await say(tester, 'Atlas: we picked Postgres');
      final pill = tester.getRect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('PROJECT ATLAS · DECISION ADDED'),
                matching: find.byType(Stack),
              )
              .first,
          matching: find.byType(Ink),
        ),
      );
      expect(copyUnder(tester, pill.bottom) - pill.bottom, moreOrLessEquals(Gap.s));
      await say(tester, 'Which database?');
      final card = tester.getRect(
        find
            .descendant(
              of: find.ancestor(of: find.text('Postgres'), matching: find.byType(Card)),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(copyUnder(tester, card.bottom) - card.bottom, moreOrLessEquals(Gap.s));
    });

    testWidgets("the busy row sits on the answers' edge", (tester) async {
      phone(tester);
      await pumpApp(tester, Harness(answers: [Completer<AgentResponse>().future]));
      await connect(tester, key: 'k');
      await tester.enterText(find.byKey(const Key('message')), 'selam');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(tester.getRect(find.byType(CircularProgressIndicator)).left, Gap.m);
      await tester.tap(find.byTooltip('Stop the answer'));
      await tester.pumpAndSettle();
    });

    testWidgets("the starters sit on the composer's edges", (tester) async {
      phone(tester);
      await pumpApp(tester, Harness());
      await connect(tester, key: 'k');
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final starter = tester.getRect(find.byType(OutlinedButton).first);
      expect((starter.left, starter.right), (Gap.m, width - Gap.m));
    });

    testWidgets("the error's Try again starts at its message's edge", (tester) async {
      phone(tester);
      await pumpApp(tester, Harness(answers: [const HttpError(500, 'x')]));
      await connect(tester, key: 'k');
      await say(tester, 'selam');
      final row = find.byKey(const Key('chat-error'));
      final message = find.descendant(of: row, matching: find.textContaining('having trouble'));
      final retry = find.descendant(of: row, matching: find.byIcon(AppIcons.refresh));
      expect(tester.getRect(retry).left, tester.getRect(message).left);
    });
  });
}
