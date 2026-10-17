import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/settings.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support.dart';

/// The app on [harness]'s session. The app owns the session, so it is closed by
/// unmounting the app before the temp folders go.
Future<Session> pumpApp(WidgetTester tester, Harness harness) async {
  final session = harness.session(owned: false);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    NoteloreApp(
      open: () async {
        await session.load();
        return session;
      },
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> connect(
  WidgetTester tester, {
  String provider = 'Claude (Anthropic)',
  String? key,
}) async {
  await tester.tap(find.text(provider));
  await tester.pumpAndSettle();
  if (key != null) await tester.enterText(find.byKey(const Key('api-key')), key);
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
}

/// A phone-sized screen (432 x 960 logical pixels); a tap that misses its widget fails.
void phone(WidgetTester tester) {
  WidgetController.hitTestWarningShouldBeFatal = true;
  addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opening shows progress, then the setup screen', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = harness.session(owned: false);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(NoteloreApp(open: () async => session));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Choose a model provider'), findsOneWidget);
  });

  testWidgets('a session that opens after the app is gone is closed', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = harness.session(owned: false);
    final opening = Completer<Session>();
    await tester.pumpWidget(NoteloreApp(open: () => opening.future));
    await tester.pumpWidget(const SizedBox()); // the app goes away first
    opening.complete(session);
    await tester.pump();
    expect(session.listNotes, throwsA(anything)); // the index is closed
  });

  testWidgets('a failure while opening is shown, not swallowed', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      NoteloreApp(open: () async => throw const FileSystemException('disk full')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('setup: the key steps, a rejected key, then a good one', (tester) async {
    phone(tester);
    final harness = Harness(rejected: const KeyValidationError('Anthropic rejected the key: bad'));
    await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anthropic Console'), findsOneWidget);
    expect(find.text('https://console.anthropic.com/settings/keys'), findsOneWidget);
    expect(find.textContaining('Billed per use through the Anthropic API'), findsOneWidget); // #95
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Paste the key first.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('api-key')), 'bad');
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter connects too
    await tester.pumpAndSettle();
    expect(find.text('Anthropic rejected the key: bad'), findsOneWidget);
    expect(find.text('Choose a model provider'), findsOneWidget);
  });

  testWidgets('setup: a network failure says so', (tester) async {
    phone(tester);
    final harness = Harness(rejected: const TransientValidationError('OpenAI is not reachable'));
    await pumpApp(tester, harness);
    await connect(tester, provider: 'GPT (OpenAI)', key: 'sk');
    expect(find.textContaining('OpenAI is not reachable'), findsOneWidget);
  });

  testWidgets('setup: Ollama has no key field', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await tester.tap(find.text('Ollama (local)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key')), findsNothing);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('chat: send a message, see the answer and errors', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Merhaba!', const NetworkError('offline')]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'sk-ant');
    expect(find.text('Ask or tell me something.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('selam'), findsOneWidget);
    expect(find.text('Merhaba!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message')), 'again');
    await tester.pump(); // the Send button appears with the text
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('chat: an unsent draft survives a trip to another tab; sending clears it', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Tamam.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    String draft() => tester.widget<TextField>(find.byKey(const Key('message'))).controller!.text;
    await tester.enterText(find.byKey(const Key('message')), 'yarım kalan');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), 'yarım kalan');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty); // the sent text does not come back
    // Clearing it by hand is a draft too: an empty one.
    await tester.enterText(find.byKey(const Key('message')), 'x');
    await tester.enterText(find.byKey(const Key('message')), '');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty);
  });

  testWidgets('chat: one tap resends the last message, also after a failure', (tester) async {
    phone(tester);
    final harness = Harness(answers: [const NetworkError('offline'), 'Merhaba!']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.byTooltip('Resend'), findsNothing); // nothing sent yet
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    await tester.tap(find.byTooltip('Resend'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['selam', 'selam']);
    expect(find.text('selam'), findsNWidgets(2)); // the resend shows, then its answer
    expect(find.text('Merhaba!'), findsOneWidget);
    expect(find.byTooltip('Resend'), findsOneWidget); // only under the last message
  });

  testWidgets('chat: while the model works it says so, and Stop ends the turn', (tester) async {
    phone(tester);
    final harness = Harness(answers: [Completer<AgentResponse>().future]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    // A playful line instead of a plain "Thinking", a new one every few seconds.
    final lines = EnglishStrings().waitingLines;
    String? waiting() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where(lines.contains)
        .firstOrNull;
    final first = waiting();
    expect(first, isNotNull);
    expect(find.textContaining('Thinking'), findsNothing);
    expect(find.byTooltip('Resend'), findsNothing); // not while a turn runs
    expect(
      tester.widget<TextField>(find.byKey(const Key('message'))).enabled,
      isNot(false),
    ); // open: writing meanwhile joins the turn
    await tester.pump(const Duration(seconds: 4));
    expect(waiting(), allOf(isNotNull, isNot(first)));
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped.'), findsOneWidget);
    expect(waiting(), isNull);
    expect(find.byTooltip('Hold to talk'), findsOneWidget); // the box is empty again
  });

  testWidgets('chat: one button, Send with text and the microphone without (#231)', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Tamam.']);
    harness.speech.phrases.add('sesli not');
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Empty: the button records.
    expect(find.byTooltip('Hold to talk'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
    // Text: the same place sends.
    await tester.enterText(find.byKey(const Key('message')), 'yazı');
    await tester.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('Hold to talk'), findsNothing);
    await tester.enterText(find.byKey(const Key('message')), '');
    await tester.pump();

    // Held with the keyboard open: the field gives way to the recording, the
    // keyboard closes and the layout moves, and the press still sends once (#212).
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pump();
    final hold = await tester.createGesture();
    await hold.down(
      tester.getCenter(find.byTooltip('Hold to talk')),
      timeStamp: const Duration(seconds: 10),
    );
    await tester.pump();
    expect(find.byKey(const Key('message')), findsNothing);
    expect(find.text('Listening…'), findsOneWidget);
    tester.view.resetViewInsets(); // the keyboard went away
    await tester.pump();
    await hold.moveBy(const Offset(0, 300)); // the finger is no longer on the button
    await hold.up(timeStamp: const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['sesli not']);
    expect(find.byKey(const Key('message')), findsOneWidget);
  });

  testWidgets('chat: a hold that starts while an answer is read aloud still sends', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Birinci.', 'İkinci.']);
    harness.speech.phrases.addAll(['bir', 'iki']);
    harness.voice.holding = Completer<void>(); // reads the first answer aloud until stopped
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    Future<void> talk(int at) async {
      final hold = await tester.createGesture();
      await hold.down(
        tester.getCenter(find.byTooltip('Hold to talk')),
        timeStamp: Duration(seconds: at),
      );
      await tester.pump();
      await hold.up(timeStamp: Duration(seconds: at + 2));
      await tester.pump();
      await tester.pump();
    }

    await talk(10);
    expect(find.byTooltip('Stop reading aloud'), findsOneWidget); // speaking
    // Pressed while it speaks: the Stop button goes and the row shifts mid-hold.
    harness.voice.holding = null;
    await talk(20);
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['bir', 'iki']);
  });

  testWidgets('chat: push to talk by keyboard (hold Space) and by screen reader (#201)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Bir.', 'İki.']);
    harness.speech.phrases.addAll(['klavyeden', 'okuyucudan']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Keyboard: from the message box, Tab reaches the button; Space held talks.
    await tester.tap(find.byKey(const Key('message')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['klavyeden']);

    // A screen reader taps: once to start, once to send.
    final talk = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Hold to talk',
    );
    tester.widget<Semantics>(talk).properties.onTap!();
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    tester.widget<Semantics>(talk).properties.onTap!();
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['klavyeden', 'okuyucudan']);
  });

  testWidgets('chat: hold to talk, let go to send; the answer is read aloud', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Cevap.', 'Yazdın.']);
    harness.speech.phrases.add('merhaba');
    final reading = Completer<void>();
    harness.voice.holding = reading;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.byKey(const Key('voice-state')), findsNothing);
    final hold = await tester.createGesture();
    await hold.down(
      tester.getCenter(find.byTooltip('Hold to talk')),
      timeStamp: const Duration(seconds: 10),
    );
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    await hold.up(timeStamp: const Duration(seconds: 12)); // held two seconds
    await tester.pump();
    await tester.pump();
    expect(find.text('merhaba'), findsOneWidget);
    expect(find.text('Cevap.'), findsOneWidget);
    expect(harness.voice.spoken, [('Cevap.', 'en')]);
    expect(find.text('Speaking…'), findsOneWidget);
    // Typing quiets the voice; a typed message is answered on screen.
    await tester.enterText(find.byKey(const Key('message')), 'yaz');
    await tester.pump(); // the Send button appears with the text
    expect(harness.voice.stops, greaterThan(0));
    await tester.tap(find.byTooltip('Stop reading aloud'));
    await tester.pump();
    reading.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-state')), findsNothing);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Yazdın.'), findsOneWidget);
    expect(harness.voice.spoken, hasLength(1)); // typed: not read aloud
    // A plain click records nothing: it says to hold.
    await tester.tap(find.byTooltip('Hold to talk'));
    await tester.pumpAndSettle();
    expect(find.text('Hold the button while you talk.'), findsOneWidget);
    // A hold the system takes away (a call, say) ends like a let-go.
    final taken = await tester.startGesture(tester.getCenter(find.byTooltip('Hold to talk')));
    await tester.pump();
    await taken.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-state')), findsNothing);
    // No recognizer: says so.
    harness.speech.failure = const VoiceUnavailable();
    final again = await tester.createGesture();
    await again.down(
      tester.getCenter(find.byTooltip('Hold to talk')),
      timeStamp: const Duration(seconds: 20),
    );
    await tester.pumpAndSettle();
    await again.up(timeStamp: const Duration(seconds: 22));
    await tester.pumpAndSettle();
    expect(find.textContaining('Speech recognition is not available'), findsOneWidget);
  });

  testWidgets('settings: a wide window lists the sections and shows one at a time', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final sections = find.byKey(const Key('settings-sections'));
    Finder section(String name) => find.descendant(of: sections, matching: find.text(name));
    for (final name in ['Model', 'Voice', 'Sync and files', 'Appearance', 'About']) {
      expect(section(name), findsOneWidget, reason: name);
    }
    // The model first, alone.
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Language'), findsNothing);

    await tester.tap(section('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Provider'), findsNothing);

    await tester.tap(section('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Whisper speech recognition'), findsOneWidget);

    await tester.tap(section('Sync and files'));
    await tester.pumpAndSettle();
    expect(find.text('Notes folder'), findsOneWidget);

    // Updates and log out live under About, with the version.
    await tester.tap(section('About'));
    await tester.pumpAndSettle();
    final version = tester.getTopLeft(find.text('Notelore · development build'));
    expect(tester.getTopLeft(find.text('Log out')).dy, greaterThan(version.dy));
  });

  testWidgets('settings: the app version at the bottom', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Notelore · development build'), findsOneWidget); // no release version
    // A release build names its version.
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(session, version: '0.7.0')));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Notelore 0.7.0'), findsOneWidget);
  });

  testWidgets('settings: web search can be turned off', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bills each search'), findsOneWidget); // Claude
    await tester.tap(find.text('Look things up on the web'));
    await tester.pumpAndSettle();
    expect(session.webSearch, isFalse);
    expect(harness.searches.last, isFalse);
  });

  testWidgets('settings: what web search says for GPT and for Ollama', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, provider: 'GPT (OpenAI)', key: 'sk');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('like the author of a book'), findsOneWidget);
  });

  testWidgets('settings: Ollama cannot search the web', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await tester.tap(find.text('Ollama (local)'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Not available with this provider.'), findsOneWidget);
  });

  testWidgets('settings: pick a nature theme and dark mode', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Pine forest'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Pine forest'));
    await tester.pumpAndSettle();
    expect(session.palette, Palette.forest);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(session.appearance, Appearance.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.darkTheme!.colorScheme.primary,
      noteloreTheme(Brightness.dark, Palette.forest).colorScheme.primary,
    );
  });

  testWidgets('settings: switch the app to Turkish and back', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Türkçe').last);
    await tester.pumpAndSettle();
    expect(find.text('Sohbet'), findsOneWidget);
    expect(find.text('Ayarlar'), findsWidgets);
    expect(find.text('Dil'), findsOneWidget);
    await tester.tap(find.text('Sohbet'));
    await tester.pumpAndSettle();
    expect(find.text('Bana bir şey sor ya da anlat.'), findsOneWidget);
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('chat: the message box stays open while it works', (tester) async {
    phone(tester);
    final first = Completer<AgentResponse>();
    final harness = Harness(answers: [first.future, 'İkisi de.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'bir');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    // Still open (no longer disabled while the model works).
    expect(tester.widget<TextField>(find.byKey(const Key('message'))).enabled, isNot(false));
    await tester.enterText(find.byKey(const Key('message')), 'iki');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.text('iki'), findsOneWidget);
    first.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'Bir.'},
      ], 'end_turn'),
    );
    await tester.pumpAndSettle();
    expect(find.text('İkisi de.'), findsOneWidget);
  });

  testWidgets('chat: switch the model at any time, not while it works', (tester) async {
    phone(tester);
    final harness = Harness(answers: [Completer<AgentResponse>().future]);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.text('claude-sonnet-5-5'), findsOneWidget); // the provider's default
    await tester.tap(find.byTooltip('Change the model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b').last);
    await tester.pumpAndSettle();
    expect(session.model, 'model-b');
    expect(find.text('model-b'), findsOneWidget);
    // While a turn runs the menu is off.
    await tester.enterText(find.byKey(const Key('message')), 'x');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      tester.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>)).enabled,
      isFalse,
    );
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
  });

  testWidgets('chat: a model the provider no longer offers asks for another', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.text('Change model'), findsNothing);
    // The provider drops the chosen claude-sonnet-5-5.
    harness.models = ['model-a', 'model-b'];
    await session.refreshModels();
    await tester.pumpAndSettle();
    expect(
      find.text('Claude (Anthropic) no longer offers claude-sonnet-5-5. Pick another model.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Change model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-a').last);
    await tester.pumpAndSettle();
    expect(session.model, 'model-a');
    expect(find.text('Change model'), findsNothing);
  });

  testWidgets('notes: the archive lists what was deleted and restores it', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('The archive is empty. Deleted notes go here.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);
    expect(find.textContaining('archived 2026-09-30'), findsOneWidget);
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored "Kitaplar".'), findsOneWidget);
    expect(find.text('The archive is empty. Deleted notes go here.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget); // back in the notes
  });

  testWidgets('notes: archived entries are shown as such and go back into their note', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    addEntry(path, 'Dune', today: today);
    archiveEntries(harness.paths.notes.path, path, {
      'notes': [1],
    }, today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entries from Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('Entries from Kitaplar'), findsOneWidget); // the reader's title
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(session.readNote(session.listNotes().single), contains('Dune'));
  });

  testWidgets('notes: restoring over a note that took the name says so', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    for (final note in session.listNotes()) {
      await session.deleteNote(note); // two in the archive
    }
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('notes: the archived notice goes away by itself', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Moved "Kitaplar" to the archive.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Moved "Kitaplar" to the archive.'), findsNothing);
  });

  testWidgets('notes: delete from the list or the reader, with undo', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    // Long press, then Cancel: nothing changes.
    await tester.longPress(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Kitaplar"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);

    // The entry's own trash button (#129), Delete, then Undo.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Kitaplar'),
        matching: find.byTooltip('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    expect(find.text('Moved "Kitaplar" to the archive.'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget); // a close button too
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);

    // From the open note: the app bar's delete button, and back to the list.
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsNothing);
    expect(session.listNotes().map((n) => n.title), ['Kitaplar']);

    // Gone meanwhile (a sync, a chat turn): says so instead of failing.
    File(notePath(harness.paths.notes.path, 'topic', 'kitaplar')).deleteSync();
    await tester.longPress(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('"Kitaplar" was already gone.'), findsOneWidget);
  });

  testWidgets('notes: the list, a reader, and an empty state', (tester) async {
    phone(tester);
    final harness = Harness(
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'project', 'title': 'Mopsos'},
          },
        ], 'tool_use'),
        'Created.',
      ],
    );
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet. Tell the assistant something to remember.'), findsOneWidget);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('message')), 'Mopsos diye proje aç');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsOneWidget);
    expect(find.text('project · updated 2026-09-30'), findsOneWidget);
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    expect(find.byType(Markdown), findsOneWidget);
    expect(find.text('Decisions'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsOneWidget);
  });

  /// Taps the middle of [part] inside the one selectable line that shows it.
  Future<void> tapOnPart(WidgetTester tester, String part) async {
    final line = tester.allRenderObjects.whereType<RenderEditable>().singleWhere(
      (r) => r.text!.toPlainText().contains(part),
    );
    final start = line.text!.toPlainText().indexOf(part);
    final box = line
        .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + part.length))
        .first;
    await tester.tapAt(line.localToGlobal(box.toRect().center));
  }

  testWidgets('notes: saved links open in the browser', (tester) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Links', today: today);
    addEntry(path, '[Example](https://example.com/page)', today: today);
    addEntry(path, 'https://example.com/bare', today: today); // a bare URL is a link too

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();
    final markdown = tester.widget<Markdown>(find.byType(Markdown));
    expect(markdown.selectable, isTrue); // and still selectable
    // Tapped where they are drawn, like a user would.
    await tapOnPart(tester, 'Example');
    await tapOnPart(tester, 'https://example.com/bare');
    await tester.pump();
    expect(launcher.opened, ['https://example.com/page', 'https://example.com/bare']);
    expect(launcher.modes.toSet(), {PreferredLaunchMode.externalApplication});
    // Other schemes and empty links open nothing.
    markdown.onTapLink!('Unsafe', 'javascript:alert(1)', '');
    markdown.onTapLink!('Missing', null, '');
    await tester.pump();
    expect(launcher.opened, ['https://example.com/page', 'https://example.com/bare']);
  });

  testWidgets('settings: pick a model from the list, refresh the list', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b').last);
    await tester.pumpAndSettle();
    expect(session.model, 'model-b');
    expect(find.text('Model saved.'), findsOneWidget);
    harness.models = ['model-c'];
    await tester.tap(find.byTooltip('Refresh the model list'));
    await tester.pumpAndSettle();
    expect(session.models, ['model-c']);
    harness.rejected = const TransientValidationError('Anthropic is not reachable');
    await tester.tap(find.byTooltip('Refresh the model list'));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic is not reachable'), findsOneWidget);
    expect(session.models, ['model-c']);
  });

  testWidgets('setup: the key page opens in the browser', (tester) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await pumpApp(tester, Harness());
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://console.anthropic.com/settings/keys'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['https://console.anthropic.com/settings/keys']);
  });

  testWidgets('settings: change the model, then log out', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Claude (Anthropic) · API key'), findsOneWidget);
    // The model is picked from the list, never typed: nothing to save by hand.
    final picker = tester.widget<DropdownMenu<String?>>(find.byKey(const Key('model')));
    expect(picker.requestFocusOnTap, isFalse);
    expect(find.text('Save model'), findsNothing);
    expect(session.model, 'claude-sonnet-5-5');
    // Log out sits at the end of Settings: scroll all the way down.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text(harness.paths.notes.path), findsOneWidget);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a model provider'), findsOneWidget);
  });
}
