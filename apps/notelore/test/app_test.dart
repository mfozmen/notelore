import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/chat.dart';
import 'package:notelore/src/empty_state.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/mark.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore/src/quick_widget.dart';
import 'package:notelore/src/section_label.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/settings.dart';
import 'package:notelore/src/share_in.dart';
import 'package:notelore/src/soft.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'audio_file_test.dart' show wav;
import 'support.dart';

/// The app on [harness]'s session. The app owns the session, so it is closed by
/// unmounting the app before the temp folders go.
Future<Session> pumpApp(WidgetTester tester, Harness harness, {DateTime Function()? clock}) async {
  final session = harness.session(owned: false, clock: clock);
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

/// The wizard's Choose step (#357): [provider], then Next.
Future<void> choose(WidgetTester tester, [String provider = 'Claude (Anthropic)']) async {
  await tester.ensureVisible(find.text(provider)); // further down the cards (#358)
  await tester.pumpAndSettle();
  await tester.tap(find.text(provider));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Next'));
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Future<void> connect(
  WidgetTester tester, {
  String provider = 'Claude (Anthropic)',
  String? key,
}) async {
  await choose(tester, provider);
  if (key != null) await tester.enterText(find.byKey(const Key('api-key')), key);
  await tester.ensureVisible(find.text('Connect')); // the end of a long card on a desk
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
  // Connected: the wizard's last step, then the chat. A refused key stays on Connect.
  if (find.text('Start').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }
}

/// The on-screen keyboard's room, as a phone reports it while one is up.
void softKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: 900);
  addTearDown(tester.view.resetViewInsets);
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

/// The starter examples built under the empty chat.
List<String> shownExamples(WidgetTester tester, Strings strings) => [
  for (final example in strings.examples)
    if (find.text(example).evaluate().isNotEmpty) example,
];

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
    await choose(tester);
    expect(find.textContaining('Sign in to the Anthropic Console'), findsOneWidget);
    expect(find.text('Open the Anthropic Console'), findsOneWidget); // the link as a button (#337)
    expect(find.textContaining('Billed per use through the Anthropic API'), findsOneWidget); // #95
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    // On the empty field itself, which takes the focus (and so comes into view).
    final field = find.byKey(const Key('api-key'));
    expect(find.descendant(of: field, matching: find.text('Paste the key first.')), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(find.byKey(const Key('setup-problem')), findsNothing);
    await tester.enterText(field, 'bad');
    await tester.pump();
    expect(find.text('Paste the key first.'), findsNothing); // gone once typing starts
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter connects too
    await tester.pumpAndSettle();
    // What the provider said, on the field it is about.
    expect(
      find.descendant(of: field, matching: find.text('Anthropic rejected the key: bad')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('setup-problem')), findsNothing);
    expect(find.text('Step 2 of 3'), findsOneWidget); // still on Connect
  });

  testWidgets('setup: on a short window the action scrolls with the rest (#337)', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = Harness(rejected: const TransientValidationError('OpenAI is not reachable'));
    await pumpApp(tester, harness);
    await connect(tester, provider: 'GPT (OpenAI)', key: 'sk'); // a two-line problem
    tester.view.viewInsets = const FakeViewPadding(bottom: 260); // and the keyboard up
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.widgetWithText(FilledButton, 'Connect'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('setup: a small phone keeps the action pinned over the keyboard (#337)', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = Harness(rejected: const TransientValidationError('OpenAI is not reachable'));
    await pumpApp(tester, harness);
    await connect(tester, provider: 'GPT (OpenAI)', key: 'sk'); // a two-line problem
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    final button = find.widgetWithText(FilledButton, 'Connect');
    expect(find.descendant(of: find.byType(SingleChildScrollView), matching: button), findsNothing);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(640 - 260));
  });

  testWidgets('setup: a screen reader hears the key being checked (#337)', (tester) async {
    phone(tester);
    final harness = Harness()..connectHold = Completer<void>();
    await pumpApp(tester, harness);
    await choose(tester);
    await tester.enterText(find.byKey(const Key('api-key')), 'k');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(
      tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)),
      isA<CircularProgressIndicator>().having((p) => p.semanticsLabel, 'label', 'Signing in…'),
    );
    harness.connectHold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('setup: a network failure says so', (tester) async {
    phone(tester);
    final harness = Harness(rejected: const TransientValidationError('OpenAI is not reachable'));
    await pumpApp(tester, harness);
    await connect(tester, provider: 'GPT (OpenAI)', key: 'sk');
    expect(find.textContaining('OpenAI is not reachable'), findsOneWidget);
  });

  testWidgets('setup: a Google consent with a box unticked says to tick them all (#484)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness(auth: FakeAuth()..failSignIn = const PartialGrant()));
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('leave every box ticked'), findsOneWidget);
  });

  testWidgets('setup: Google sign-in comes first, and without an account it stops (#208)', (
    tester,
  ) async {
    phone(tester);
    final auth = FakeAuth()..failSignIn = const SignInFailed('access_denied');
    await pumpApp(tester, Harness(auth: auth));
    // A welcome first (#296): who we are, what it does, why Google.
    expect(find.text('Welcome to Notelore'), findsOneWidget);
    expect(find.byType(NoteloreMark), findsOneWidget); // its own mark (#340)
    expect(find.bySemanticsLabel('Notelore'), findsWidgets);
    expect(find.textContaining('your own Google Drive'), findsOneWidget);
    expect(find.textContaining('its own hidden space'), findsOneWidget);
    expect(find.textContaining('Google (Gmail) account'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    // Google's own button: its G, its words; in the thumb's reach on a phone.
    final button = find.byKey(const Key('google-sign-in'));
    expect(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (w) => w is Image && '${w.image}'.contains('assets/google/g_light.png'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: button, matching: find.text('Sign in with Google')), findsOneWidget);
    expect(tester.getBottomLeft(button).dy, greaterThan(960 * 0.75));
    expect(find.text('Claude (Anthropic)'), findsNothing); // no provider before Google
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    final problem = find.byKey(const Key('google-problem'));
    expect(
      find.descendant(
        of: problem,
        matching: find.text('Notelore needs a Google account to continue. Sign in to go on.'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(problem),
      matchesSemantics(
        isLiveRegion: true,
        label: 'Notelore needs a Google account to continue. Sign in to go on.',
      ),
    );
    expect(find.textContaining('access_denied'), findsNothing); // no raw codes (#302)
    expect(find.text('Claude (Anthropic)'), findsNothing);
    // Not a refusal: said as it is, not as a missing account.
    auth.failSignIn = const NetworkError('offline');
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not reach the service. Check the connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('offline'), findsNothing);
    expect(find.textContaining('needs a Google account'), findsNothing);
    auth.failSignIn = null;
    // While Google answers, the button waits: a spinner in the G's place.
    auth.hold = Completer<void>();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    expect(
      find.descendant(of: button, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    auth.hold!.complete();
    await tester.pumpAndSettle();
    expect(auth.granted, isTrue);
    expect(find.text('Claude (Anthropic)'), findsOneWidget); // on to the provider
  });

  testWidgets('setup: a short window (a phone on its side) scrolls the sign-in, never overflows', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 280)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2; // and large text
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = FakeAuth()..failSignIn = const SignInFailed('access_denied');
    await pumpApp(tester, Harness(auth: auth));
    // Too short for it all: the button is further down, reached by scrolling.
    await tester.scrollUntilVisible(find.byKey(const Key('google-sign-in')), 100);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow with the error card shown
    expect(find.byKey(const Key('google-problem')), findsOneWidget);
    // The page's own list: the error's selectable text scrolls too.
    await tester.scrollUntilVisible(
      find.byKey(const Key('google-sign-in')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    // Busy, a screen reader hears that it is signing in.
    auth
      ..failSignIn = null
      ..hold = Completer<void>();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Signing in…')), findsOneWidget); // the button reads it
    auth.hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('setup: Ollama has no key field', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await choose(tester, 'Ollama (local)');
    expect(find.byKey(const Key('api-key')), findsNothing);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.byType(SoftNavBar), findsOneWidget);
  });

  testWidgets('the phone headers: the menu and the Notes actions are soft round buttons', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await choose(tester, 'Ollama (local)');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final fill = Theme.of(tester.element(find.byType(SoftNavBar))).colorScheme.surfaceContainerLow;
    void round(String tooltip) {
      final button = find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(Material));
      expect(tester.widget<Material>(button.first).color, fill, reason: tooltip);
      expect(tester.getSize(button.first), const Size.square(38), reason: tooltip);
    }

    round('Open navigation menu');
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    for (final tooltip in ['Open navigation menu', 'Archive', 'Refresh', 'More note actions']) {
      round(tooltip);
    }
  });

  testWidgets('setup: Ollama with no model installed says which one to pull (#471)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness()..models = []);
    await choose(tester, 'Ollama (local)');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ollama pull qwen3:4b'), findsWidgets);
    expect(find.textContaining('No model is installed in Ollama'), findsOneWidget);
  });

  testWidgets('chat: on a phone, sending closes the keyboard; the box opens it again (#497)', (
    tester,
  ) async {
    phone(tester);
    softKeyboard(tester);
    // An answer longer than the screen, so the conversation scrolls.
    final harness = Harness(answers: [List.generate(40, (i) => 'Satır $i.').join('\n\n')]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse); // the answer has the room
    await tester.tap(find.byKey(const Key('message')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    // Dragging the conversation puts it away too.
    await tester.dragFrom(const Offset(200, 200), const Offset(0, 150)); // on the conversation
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('chat: a suggested answer tapped puts the keyboard away too (#497)', (tester) async {
    phone(tester);
    softKeyboard(tester);
    final harness = Harness(answers: ['Hangi proje?\n[[Mopsos]] [[Atlas]]', 'Kaydedildi.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'not al');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message'))); // about to type, then picks a button
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mopsos'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['not al', 'Mopsos']);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('chat: a reply the background cut off arrives on return (#226)', (tester) async {
    phone(tester);
    final harness = Harness(answers: [const NetworkError('offline'), 'Geldi.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump();
    void go(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);
    // The phone puts Notelore away, the way Android does: step by step.
    go([AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    go([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pumpAndSettle();
    expect(find.text('Geldi.'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing); // never shown as an error
  });

  testWidgets('chat: offline, a message waits in sight and goes out with Try now (#214)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: [const NetworkError('offline'), 'Kaydettim.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'kitabı kaydet');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('kitabı kaydet'), findsOneWidget);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing); // not an error
    await tester.tap(find.text('Try now'));
    await tester.pumpAndSettle();
    expect(find.text('Kaydettim.'), findsOneWidget);
    expect(find.text('Waiting to send'), findsNothing);
  });

  testWidgets('chat: an empty chat offers examples; a tap puts one in the box (#289)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    final shown = shownExamples(tester, EnglishStrings());
    expect(shown, hasLength(3));
    expect(shown.toSet(), hasLength(3));
    final example = shown.first;
    await tester.tap(find.text(example));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('message')));
    expect(field.controller!.text, example); // in the box to edit, not sent
    expect(find.byTooltip('Send'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text(example), findsOneWidget); // the bubble; the examples are gone
  });

  testWidgets('chat: the first-run examples fit a phone at large text (#567)', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    expect(tester.takeException(), isNull); // no overflow
    expect(shownExamples(tester, EnglishStrings()), hasLength(3));
  });

  testWidgets('chat: the first-run examples fit a desktop at large text (#567)', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    expect(tester.takeException(), isNull); // no overflow
    expect(shownExamples(tester, EnglishStrings()), hasLength(3));
  });

  testWidgets('chat: the longest first-run example fits at large text (#577)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    final longest = EnglishStrings().examples.reduce((a, b) => a.length >= b.length ? a : b);
    for (final (size, ratio) in [(const Size(1080, 2400), 2.5), (const Size(1280, 900), 1.0)]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = ratio;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyChat(
              EnglishStrings(),
              example: (_) {},
              starters: [longest, longest, longest],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // no overflow
    }
  });

  testWidgets('chat: message buttons are full-size targets; bubbles leave a gutter (#289)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Merhaba!']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam ' * 40);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    for (final button in find.byTooltip('Copy').evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)).height, greaterThanOrEqualTo(48));
    }
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final bubble = find.ancestor(
      of: find.text(('selam ' * 40).trim()),
      matching: find.byType(Container),
    );
    expect(tester.getSize(bubble.first).width, lessThanOrEqualTo(width * 0.85));
  });

  testWidgets('chat: send a message, see the answer and errors', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Merhaba!', const HttpError(500, 'offline')]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'sk-ant');
    expect(find.text('Write something to note, or ask about your notes.'), findsOneWidget);
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
    expect(find.textContaining('having trouble'), findsOneWidget); // said kindly, not "HTTP 500"
  });

  /// Opens Settings and brings the app lock card into view.
  Future<void> openLock(WidgetTester tester) async {
    await openSettings(tester, 'App lock');
  }

  /// Closes the app and opens it again on the same folders and keystore.
  Future<void> restart(WidgetTester tester, Harness harness) async {
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness);
  }

  testWidgets('lock: set a PIN in Settings; the next start asks for it first', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openLock(tester);
    expect(find.textContaining('opens without asking'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A PIN for Notelore'));
    await tester.pumpAndSettle();
    FilledButton confirm() => tester.widget<FilledButton>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );
    await tester.enterText(find.byKey(const Key('lock-new')), '24');
    await tester.pump();
    expect(find.text('At least 4 digits.'), findsOneWidget);
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('lock-new')), '2468');
    await tester.enterText(find.byKey(const Key('lock-repeat')), '2469');
    await tester.pump();
    expect(find.text("They don't match."), findsOneWidget);
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('lock-repeat')), '2468');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Turn on')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('On: a PIN opens Notelore.'), findsOneWidget);

    // The next start: locked, nothing of the notes or the chat shows.
    await restart(tester, harness);
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(find.byType(SoftNavBar), findsNothing);
    expect(find.byKey(const Key('message')), findsNothing);
    await tester.enterText(find.byKey(const Key('unlock')), '1357');
    await tester.tap(find.text('Unlock'));
    await tester.pump(); // while the PIN is checked: the field keeps the focus
    final checking = tester.widget<TextField>(find.byKey(const Key('unlock')));
    expect(checking.enabled, isNot(false)); // a disabled field drops its focus
    expect(checking.readOnly, isFalse); // read-only would close the keyboard for a moment
    expect(checking.focusNode!.hasFocus, isTrue);
    await tester.pumpAndSettle();
    expect(find.text("That's not it. Try again."), findsOneWidget);
    expect(find.byKey(const Key('message')), findsNothing);
    // The field keeps the focus, so the next try needs no tap (#508).
    final unlock = tester.widget<TextField>(find.byKey(const Key('unlock')));
    expect(unlock.focusNode!.hasFocus, isTrue);
    expect(unlock.decoration!.errorText, "That's not it. Try again.");
    await tester.enterText(find.byKey(const Key('unlock')), '2468');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsNothing);
    expect(find.byKey(const Key('message')), findsOneWidget);
  });

  /// The app goes to the background the way a phone sends it there.
  void toBackground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void toForeground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('lock: back from a minute in the background it asks again; a short trip not', (
    tester,
  ) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    await session.lock.set('2468');
    await tester.pumpAndSettle();
    toBackground(tester);
    now = now.add(const Duration(seconds: 59));
    toForeground(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget); // still open
    // Losing focus alone (a desktop window behind another) is not the background.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget);
    toBackground(tester);
    now = now.add(const Duration(minutes: 1));
    toForeground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(find.byKey(const Key('message')), findsNothing);
    await tester.enterText(find.byKey(const Key('unlock')), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget);
  });

  testWidgets('lock: a note left open is not shown over the lock (#309)', (tester) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Secret plans', today: today);
    await session.lock.set('2468');
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secret plans'));
    await tester.pumpAndSettle();
    toBackground(tester);
    now = now.add(const Duration(minutes: 1));
    toForeground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(find.text('Secret plans'), findsNothing); // nothing of the note, above or below
    // A notice from just before (here: one note archived) does not wait over the lock.
    await tester.enterText(find.byKey(const Key('unlock')), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secret plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    const notice = 'Moved "Secret plans" to the archive.';
    expect(find.text(notice), findsWidgets);
    toBackground(tester);
    now = now.add(const Duration(minutes: 1));
    toForeground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(find.text(notice), findsNothing);
  });

  testWidgets('lock: a file picked after the app locked is not sent (#387)', (tester) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    await session.lock.set('2468');
    harness.files
      ..hold = Completer<void>()
      ..picked = [XFile.fromData(Uint8List.fromList(utf8.encode('notes')), path: 'a.txt')];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump();
    // A minute in the picker: the app locks on the way back.
    toBackground(tester);
    now = now.add(const Duration(minutes: 1));
    toForeground(tester);
    await tester.pumpAndSettle();
    harness.files.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
  });

  testWidgets('lock: after five wrong tries the screen waits, then lets one try again', (
    tester,
  ) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final first = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    await first.lock.set('2468');
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness, clock: () => now);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byKey(const Key('unlock')), '0000');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('unlock'))).enabled, isFalse);
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many tries. Try again in 0:20.'), findsOneWidget);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Too many tries'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('unlock'))).enabled, isTrue);
    await tester.enterText(find.byKey(const Key('unlock')), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget);
  });

  testWidgets('lock: at 2x the wait message keeps its countdown (#706)', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final first = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    await first.lock.set('2468');
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness, clock: () => now);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byKey(const Key('unlock')), '0000');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('unlock'))).decoration?.errorMaxLines, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets('lock: turning it off asks for the PIN; Cancel keeps it', (tester) async {
    phone(tester);
    final harness = Harness();
    final first = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await first.lock.set('2468');
    await tester.pumpAndSettle();
    await openLock(tester);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(first.lock.enabled, isTrue);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lock-current')), '0000');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Turn off')),
    );
    await tester.pumpAndSettle();
    expect(find.text("That's not it. Try again."), findsOneWidget);
    expect(first.lock.enabled, isTrue);
    await tester.enterText(find.byKey(const Key('lock-current')), '2468');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(first.lock.enabled, isFalse);
    expect(find.textContaining('opens without asking'), findsOneWidget);
    // Setting it up can be called off too.
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(first.lock.enabled, isFalse);
    await restart(tester, harness);
    expect(find.text('Notelore is locked'), findsNothing);
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
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), 'yarım kalan');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty);
    await tester.tap(tab('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty); // the sent text does not come back
    // Clearing it by hand is a draft too: an empty one.
    await tester.enterText(find.byKey(const Key('message')), 'x');
    await tester.enterText(find.byKey(const Key('message')), '');
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), isEmpty);
  });

  testWidgets('shared text opens an editable composer and waits for Send', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Saved.']);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'My draft');
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    final delivery = ShareDelivery(session, () async => {'text': 'Shared words'});
    addTearDown(delivery.dispose);
    await delivery.check();
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('message')));
    expect(field.controller!.text, 'My draft\n\nShared words');
    expect(harness.provider.asked, isEmpty);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['My draft\n\nShared words']);
    await delivery.check(); // the chat is already open this time
    await tester.pumpAndSettle();
    expect(field.controller!.text, 'Shared words');
    expect(harness.provider.asked, hasLength(1));
  });

  testWidgets('the home-screen widget opens the composer, voice mode or a note (#799)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Saved.']);
    harness.speech.phrases.add('sesli');
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'project', 'Atlas', today: DateTime(2026));
    session.index.markChanged(path);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    session.openQuick(QuickOpen.write);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('message')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(session.quickOpen, isNull);
    session.openQuick(const QuickOpen.note('project', 'atlas'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pin'), findsOneWidget); // the note's reader
    expect(session.quickOpen, isNull);
    // From the open note: back to the chat, listening until a tap sends.
    session.openQuick(QuickOpen.talk);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pin'), findsNothing);
    expect(find.byTooltip('Stop and send'), findsOneWidget);
    expect(session.quickOpen, isNull);
    // A note gone since the widget drew it: the list, nothing open.
    File(path).deleteSync();
    session.index.markChanged(path);
    await tester.tap(find.byTooltip('Stop and send'));
    await tester.pumpAndSettle();
    session.openQuick(const QuickOpen.note('project', 'atlas'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pin'), findsNothing);
    expect(session.quickOpen, isNull);
  });

  testWidgets('chat: a question offers its answers as buttons, sent once (#210)', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Hangi proje?\n[[Mopsos]] [[Atlas]]', 'Kaydedildi.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'not al');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Hangi proje?'), findsOneWidget); // without the answer line
    expect(find.textContaining('[['), findsNothing);
    final atlas = find.widgetWithText(OutlinedButton, 'Atlas');
    expect(atlas, findsOneWidget);
    expect(
      tester.getSemantics(atlas),
      matchesSemantics(
        label: 'Atlas',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mopsos'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mopsos'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['not al', 'Mopsos']); // once
    expect(find.text('Kaydedildi.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing); // answered: gone
    expect(find.byKey(const Key('message')), findsOneWidget); // typing stays
  });

  testWidgets('chat: attach an image; the model sees it; not while a turn runs (#278)', (
    tester,
  ) async {
    phone(tester);
    final answer = Completer<AgentResponse>();
    final harness = Harness(answers: [answer.future]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // GIF's first bytes are plain ASCII: an image all the same, not text.
    final gif = [...'GIF89a'.codeUnits, 1, 0, 1, 0];
    harness.files.picked = [XFile.fromData(Uint8List.fromList(gif), path: 'r.gif')];
    await tester.enterText(find.byKey(const Key('message')), 'what is it');
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump();
    expect(harness.provider.asked.single, allOf(contains('what is it'), contains('image/gif')));
    expect(
      harness.provider.asked.single,
      contains(RegExp(r'<attached image="r\.gif" original="attachments/[\d-]+/r\.gif"/>')),
    );
    final kept = Directory(p.join(harness.paths.notes.path, 'attachments'))
        .listSync(recursive: true)
        .whereType<File>()
        .single;
    expect(kept.readAsBytesSync(), gif);
    expect(find.text('r.gif'), findsOneWidget); // its name in the bubble, not its bytes
    expect(find.bySemanticsLabel('Image: r.gif'), findsOneWidget); // told apart from a file
    // While that turn runs, another image cannot join it.
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump();
    expect(find.textContaining('Images go when nothing else'), findsOneWidget);
    expect(harness.provider.asked, hasLength(1));
    answer.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'A chart.'},
      ], 'end_turn'),
    );
    await tester.pumpAndSettle();
    expect(find.text('A chart.'), findsOneWidget);
  });

  testWidgets('chat: an image that fails offline leaves no original (#534)', (tester) async {
    phone(tester);
    final harness = Harness(answers: [const NetworkError('offline')]);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final gif = [...'GIF89a'.codeUnits, 1, 0, 1, 0];
    harness.files.picked = [XFile.fromData(Uint8List.fromList(gif), path: 'r.gif')];
    await tester.enterText(find.byKey(const Key('message')), 'what is it');
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Images cannot wait'), findsOneWidget);
    final folder = Directory(p.join(harness.paths.notes.path, 'attachments'));
    final kept = folder.existsSync()
        ? folder.listSync(recursive: true).whereType<File>()
        : <File>[];
    expect(kept, isEmpty);
  });

  testWidgets('chat: a provider that cannot see images says so (#278)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, provider: 'Ollama (local)');
    // Over the providers' 5 MB, counted over every image of the message: too
    // large, whoever would look at it.
    Uint8List jpeg() => Uint8List(3 * 1024 * 1024)..setAll(0, [0xff, 0xd8, 0xff]);
    harness.files.picked = [
      XFile.fromData(jpeg(), path: 'one.jpg'),
      XFile.fromData(jpeg(), path: 'big.jpg'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('big.jpg is too large'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // the notice goes
    await tester.pumpAndSettle();
    harness.files.picked = [
      XFile.fromData(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0]), path: 'r.png'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot look at images'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
  });

  testWidgets('chat: attach a text file; the model files it; other files are refused (#222)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Filed under Mopsos.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Not text: refused with a reason, nothing sent.
    harness.files.picked = [
      XFile.fromData(Uint8List.fromList([0xff, 0xfe, 0x00, 0x89]), path: 'photo.jpg'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('photo.jpg'), findsOneWidget);
    expect(find.textContaining('text files'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5)); // the notice goes
    await tester.pumpAndSettle();
    // Valid UTF-8, but binary: a NUL byte.
    harness.files.picked = [
      XFile.fromData(Uint8List.fromList([0x61, 0x00, 0x62]), path: 'x.bin'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('x.bin is none of them'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Text, but too much to send: the limit counts every file of the message.
    harness.files.picked = [
      XFile.fromData(Uint8List.fromList(utf8.encode('a' * 120000)), path: 'one.log'),
      XFile.fromData(Uint8List.fromList(utf8.encode('b' * 120000)), path: 'two.log'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('two.log is too large'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Text: sent with what is typed as its explanation.
    await tester.enterText(find.byKey(const Key('message')), 'for Mopsos');
    harness.files.picked = [
      XFile.fromData(Uint8List.fromList(utf8.encode('Ship in May.\n')), path: 'plan.txt'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, [
      'for Mopsos\n\n<attached file="plan.txt">\nShip in May.\n</attached>',
    ]);
    expect(find.text('for Mopsos'), findsOneWidget); // the bubble: words and the file's name
    expect(find.text('plan.txt'), findsOneWidget);
    expect(find.bySemanticsLabel('File: plan.txt'), findsOneWidget);
    expect(find.textContaining('Ship in May'), findsNothing); // not the whole file
    expect(find.text('Filed under Mopsos.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('message'))).controller!.text, isEmpty);
    // Called off: nothing happens.
    harness.files.picked = [];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, hasLength(1));
  });

  testWidgets('chat: a PDF goes as its text; one with no text layer is refused (#284)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Filed.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 ...'));
    Future<void> attach(String name) async {
      harness.files.picked = [XFile.fromData(pdf, path: name)];
      await tester.tap(find.byTooltip('Attach a file'));
      await tester.pumpAndSettle();
    }

    // Scanned (no text layer) or damaged: refused with a reason, nothing sent.
    harness.pdfText = (_) async => '  \n';
    await attach('scan.pdf');
    expect(find.textContaining('scan.pdf has no text'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    harness.pdfText = (_) async => throw Exception('bad xref');
    await attach('broken.pdf');
    expect(find.textContaining('broken.pdf has no text'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // One that never finishes is given up after 30 seconds (#389).
    harness.pdfText = (_) => Completer<String>().future;
    harness.files.picked = [XFile.fromData(pdf, path: 'endless.pdf')];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.textContaining('endless.pdf has no text'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Text inside: sent like a text file.
    harness.pdfText = (_) async => 'Budget: 40k';
    await attach('report.pdf');
    // Its original is kept beside the notes, for the note to link (#279).
    expect(
      harness.provider.asked.single,
      matches(
        RegExp(
          r'^<attached file="report.pdf" original="attachments/[\d-]+/report.pdf">\nBudget: 40k\n</attached>$',
        ),
      ),
    );
    // Two of the same name, from two folders: each links its own original.
    harness.provider.answers.add('Saved.');
    harness.files.picked = [
      XFile.fromData(pdf, path: 'report.pdf'),
      XFile.fromData(pdf, path: 'report.pdf'),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(
      harness.provider.asked.last,
      allOf(
        contains('<attached file="report.pdf" original="attachments/2026-09-30/report-2.pdf">'),
        contains(
          '<attached file="report (2).pdf" original="attachments/2026-09-30/report-2-2.pdf">',
        ),
      ),
    );
  });

  testWidgets('chat: the newest answer can be told wrong, kept for training, undone (#753)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Tamam.', 'Peki.']);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.byTooltip('This was wrong'), findsNothing); // no answer yet
    await tester.enterText(find.byKey(const Key('message')), 'Kahve aldım');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final feedback = Directory(p.join(harness.paths.notes.path, '.notelore', 'feedback'));
    List<File> kept() =>
        feedback.existsSync() ? feedback.listSync().whereType<File>().toList() : [];

    await tester.tap(find.byTooltip('This was wrong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(kept(), isEmpty);

    await tester.tap(find.byTooltip('This was wrong'));
    await tester.pumpAndSettle();
    expect(find.text('Optional'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('expected-field')), 'Tick the todo');
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter keeps it
    await tester.pumpAndSettle();
    expect(find.text("Kept for the model's training"), findsOneWidget);
    expect(kept().single.readAsStringSync(), contains('Tick the todo'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(kept(), isEmpty);

    // Reported, the button says so, and a second tap takes it back: never kept twice.
    await tester.tap(find.byTooltip('This was wrong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(kept(), hasLength(1));
    expect(find.byTooltip('This was wrong'), findsNothing);
    await tester.tap(find.byTooltip('Take back the report'));
    await tester.pumpAndSettle();
    expect(kept(), isEmpty);
    await tester.tap(find.byTooltip('This was wrong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    // The next answer can be told wrong on its own.
    await session.send('Bir de çay');
    await tester.pumpAndSettle();
    expect(find.byTooltip('This was wrong'), findsOneWidget);
    expect(kept(), hasLength(1));
  });

  testWidgets('chat: copy a message or an answer, with a short confirmation (#225)', (
    tester,
  ) async {
    phone(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpApp(tester, Harness(answers: ['**Merhaba!**\nİkinci satır.']));
    await connect(tester, key: 'k');
    expect(find.byTooltip('Copy'), findsNothing); // nothing to copy yet
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy'), findsNWidgets(2)); // the message and the answer
    await tester.tap(find.byTooltip('Copy').first); // newest at the bottom: the answer
    await tester.pump();
    // An answer copies as words a messenger shows as they are (#335), not its Markdown.
    expect(copied, ['Merhaba!\nİkinci satır.']);
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy').last);
    await tester.pump();
    expect(copied.last, 'selam');
    expect(
      tester.getSemantics(find.byTooltip('Copy').last),
      matchesSemantics(
        tooltip: 'Copy',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
  });

  testWidgets('chat: Cmd +, - and 0 zoom the text and reset it (#696)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    phone(tester);
    final session = await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'Kitaplari rafa koy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final message = find.text('Kitaplari rafa koy');
    final before = tester.getSize(message).height;
    await tester.tap(find.byKey(const Key('message')));
    await tester.pump();
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.equal);
    expect(session.chatTextStep, 2);
    expect(tester.getSize(message).height, greaterThan(before));
    await press(LogicalKeyboardKey.digit0);
    expect(session.chatTextStep, 1);
    await press(LogicalKeyboardKey.minus);
    expect(session.chatTextStep, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chat: Ctrl and the wheel step the text size (#696)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    phone(tester);
    final session = await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'Kitaplari rafa koy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    session.transcript.addAll([
      for (var i = 0; i < 30; i++)
        (role: ChatRole.user, text: 'line $i', cards: const <AnswerCard>[]),
    ]);
    session.notifyListeners();
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final offset = scrollable.position.pixels;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final center = tester.getCenter(find.byType(ListView).first);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pumpAndSettle();
    expect(session.chatTextStep, 2);
    expect(scrollable.position.pixels, offset); // the wheel zoomed, not scrolled
    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
    );
    await tester.pumpAndSettle();
    expect(session.chatTextStep, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('settings: the chat text control steps, resets and is saved (#696)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    await tester.ensureVisible(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(find.text('115%'), findsOneWidget);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(find.text('130%'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    final again = harness.session();
    await again.load();
    expect(again.chatTextStep, Session.chatTextDefault);
  });

  testWidgets('settings: the chat text control fits a phone at large text (#782)', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    await tester.ensureVisible(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    // The percentage on one line, as tall as the Reset beside it.
    final percent = tester.getSize(find.byKey(const Key('chat-text-percent')));
    expect(percent.height, tester.getSize(find.text('Reset')).height);
    await tester.ensureVisible(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('chat: the largest size over the system scale does not overflow (#696)', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    session.setChatTextStep(Session.chatTextSteps.length - 1);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message')),
      'Kitaplari rafa koy ve uzun bir cumle daha yaz ki sarsin',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat: a sent message selects word by word and copies on macOS (#695)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'Kitaplari rafa koy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final message = find.text('Kitaplari rafa koy');
    // The person's words select through the answers' surface, not a bare
    // SelectableText (#695).
    expect(find.ancestor(of: message, matching: find.byType(SelectionArea)), findsOneWidget);
    final rect = tester.getRect(message);
    final drag = await tester.startGesture(
      Offset(rect.centerLeft.dx + 2, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(Offset(rect.centerRight.dx - 8, rect.center.dy));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(copied.last, contains('Kitaplari'));

    // A double-click takes one word (#695).
    copied.clear();
    final word = Offset(rect.centerLeft.dx + 12, rect.center.dy);
    await tester.tapAt(word);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(word);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(copied.last.trim(), 'Kitaplari');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chat: a sent message selects and copies on Windows (#695)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'Kitaplari rafa koy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text('Kitaplari rafa koy'));
    final drag = await tester.startGesture(
      Offset(rect.centerLeft.dx + 2, rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(Offset(rect.centerRight.dx - 8, rect.center.dy));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied.last, contains('Kitaplari'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chat: a selected message shows a visible highlight (#702)', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'Kitaplari rafa koy');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final message = find.text('Kitaplari rafa koy');
    final text = tester.widget<Text>(message);
    final scheme = Theme.of(tester.element(message)).colorScheme;
    expect(text.selectionColor, isNotNull);
    // Not the bubble's own colour: a different hue stands off the teal.
    final selected = HSLColor.fromColor(text.selectionColor!);
    final bubble = HSLColor.fromColor(scheme.primary);
    double hueGap(double a, double b) {
      final gap = (a - b).abs() % 360;
      return gap > 180 ? 360 - gap : gap;
    }

    expect(hueGap(selected.hue, bubble.hue), greaterThan(60));
  });

  testWidgets('chat: Copy under every answer; an older message shows it on a tap (#508)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Eski cevap.', 'Yeni cevap.']));
    await connect(tester, key: 'k');
    for (final message in ['ilk', 'ikinci']) {
      await tester.enterText(find.byKey(const Key('message')), message);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
    }
    final copies = find.byTooltip('Copy').hitTestable();
    // Every answer, which is what one copies; of the person's own, the newest.
    expect(copies, findsNWidgets(3));
    double gap() =>
        tester.getTopLeft(find.text('Eski cevap.')).dy - tester.getTopLeft(find.text('ilk')).dy;
    final closed = gap(); // no empty action row under an older message (#708)
    await tester.tap(find.text('ilk'));
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(4)); // the tapped message has its own now
    expect(gap() - closed, greaterThanOrEqualTo(48));
    await tester.tap(find.text('ilk')); // a second tap puts it away
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(3));
    expect(gap(), closed);
    await tester.longPress(find.text('ilk')); // a long press selects text: no toggle
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(3));
    // On a desktop, a pointer over it shows them, and they go when it leaves.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('ilk')));
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(4));
    await mouse.down(tester.getCenter(find.text('ilk'))); // a click does not close it
    await mouse.up();
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(4));
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(copies, findsNWidgets(3));
    // A screen reader can copy any of them, shown or not.
    for (final text in ['ilk', 'Eski cevap.', 'ikinci', 'Yeni cevap.']) {
      expect(
        find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.customSemanticsActions?.isNotEmpty ?? false),
          ),
        ),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('chat: on Android the new answer or failure is a live region, once (#502)', (
    tester,
  ) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    final harness = Harness(
      answers: [const HttpError(500, 'down'), 'Birinci cevap.', 'İkinci cevap.'],
    );
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    bool live(Finder finder) => tester.getSemantics(finder).flagsCollection.isLiveRegion;
    Future<void> say(String message) async {
      await tester.enterText(find.byKey(const Key('message')), message);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
    }

    await say('bir');
    expect(live(find.textContaining('having trouble')), isTrue); // the failure, read out
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(live(find.text('Birinci cevap.')), isTrue); // the answer that replaced it
    await say('iki');
    expect(live(find.text('İkinci cevap.')), isTrue);
    expect(live(find.text('Birinci cevap.')), isFalse); // the earlier one stays quiet
    // Read once: back on the tab, it is history, not news.
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    expect(live(find.text('İkinci cevap.')), isFalse);
    semantics.dispose();
  });

  testWidgets('chat: elsewhere the new answer is announced, with its suggested answers (#502)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    phone(tester);
    final semantics = tester.ensureSemantics();
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        if (message case {'type': 'announce', 'data': {'message': final String text}}) {
          announced.add(text);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      ),
    );
    final harness = Harness(answers: ['**Hangi** proje?\n[[Mopsos]] [[Atlas]]']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'not al');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    // The whole answer as words, and the answers it offers: once.
    expect(announced, ['Hangi proje? Answers: Mopsos, Atlas.']);
    expect(
      tester.getSemantics(find.text('Hangi proje?')).flagsCollection.isLiveRegion,
      isFalse, // not twice: no live region where the announcement already spoke
    );
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    expect(announced, hasLength(1));
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chat: an error is a status row with Try again beside it, not an answer (#306)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: [const HttpError(500, 'upstream exploded'), 'Merhaba!']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.byTooltip('Resend'), findsNothing); // nothing sent yet
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('chat-error'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(AppIcons.error)), findsOneWidget);
    final notice = find.descendant(of: row, matching: find.textContaining('having trouble'));
    expect(notice, findsOneWidget);
    expect(
      tester.widget<Text>(notice).textAlign,
      TextAlign.start,
    ); // the icon stays beside it (#709)
    expect(find.textContaining('upstream exploded'), findsNothing); // no raw provider text
    expect(find.textContaining('HTTP'), findsNothing);
    // The way out sits with the error, not under the message above it.
    expect(find.byTooltip('Resend'), findsNothing);
    final tryAgain = find.descendant(of: row, matching: find.text('Try again'));
    expect(tryAgain, findsOneWidget);
    await tester.tap(tryAgain);
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['selam', 'selam']);
    expect(find.text('selam'), findsNWidgets(2)); // the resend shows, then its answer
    expect(find.text('Merhaba!'), findsOneWidget);
    expect(find.byTooltip('Resend'), findsOneWidget); // only under the last message
  });

  testWidgets('chat: with less motion asked for, the working status does not spin (#290)', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, Harness(answers: [Completer<AgentResponse>().future]));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    final status = find.byKey(const Key('working'));
    expect(
      find.descendant(of: status, matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
    expect(find.descendant(of: status, matching: find.byIcon(AppIcons.moreHoriz)), findsOneWidget);
    await tester.tap(find.byTooltip('Stop the answer')); // end the turn and its deadline
    await tester.pumpAndSettle();
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
    // A passing status, not an answer (#290): no bubble, muted italic text,
    // and one steady announcement for screen readers (not each playful line).
    final status = find.byKey(const Key('working'));
    expect(status, findsOneWidget);
    expect(
      find.descendant(
        of: status,
        matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null),
      ),
      findsNothing,
    );
    final line = tester.widget<Text>(find.text(first!));
    expect(line.style?.fontStyle, FontStyle.italic);
    expect(
      tester.getSemantics(status),
      matchesSemantics(isLiveRegion: true, label: 'Working on it…'),
    );
    expect(find.byTooltip('Resend'), findsNothing); // not while a turn runs
    expect(
      tester.widget<TextField>(find.byKey(const Key('message'))).enabled,
      isNot(false),
    ); // open: writing meanwhile joins the turn
    await tester.pump(const Duration(seconds: 4));
    expect(waiting(), allOf(isNotNull, isNot(first)));
    // Its own button, never another one's state reused in its place (#508).
    expect(find.byKey(const Key('stop')), findsOneWidget);
    // Stop is the one thing to do now: in the talk button's place, not beside a
    // talk button that does nothing meanwhile (#525).
    expect(find.byTooltip('Tap or hold to talk'), findsNothing);
    final stopAt = tester.getTopRight(find.byKey(const Key('stop'))).dx;
    expect(stopAt, greaterThanOrEqualTo(tester.getTopRight(find.byKey(const Key('message'))).dx));
    expect(tester.getSize(find.byKey(const Key('stop'))), const Size(48, 48));
    // Something typed meanwhile: Send leads, Stop stays at hand before it.
    await tester.enterText(find.byKey(const Key('message')), 've bir de');
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const Key('stop'))).dx,
      lessThan(tester.getCenter(find.byKey(const Key('send'))).dx),
    );
    await tester.enterText(find.byKey(const Key('message')), '');
    await tester.pump();
    await tester.tap(find.byTooltip('Stop the answer'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped.'), findsOneWidget);
    expect(waiting(), isNull);
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget); // the box is empty again
  });

  testWidgets('chat: one button, Send with text and the microphone without (#231)', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Tamam.']);
    harness.speech.phrases.add('sesli not');
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Empty: the button records.
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
    // Text: the same place sends.
    await tester.enterText(find.byKey(const Key('message')), 'yazı');
    await tester.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('Tap or hold to talk'), findsNothing);
    await tester.enterText(find.byKey(const Key('message')), '');
    await tester.pump();

    // Held with the keyboard open: the field gives way to the recording, the
    // keyboard closes and the layout moves, and the press still sends once (#212).
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pump();
    final hold = await tester.createGesture();
    await hold.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
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

  testWidgets('chat: a turn that starts during a hold does not strand the recording (#525)', (
    tester,
  ) async {
    phone(tester);
    // The shared text's turn stays open; the spoken note gets its own answer.
    final harness = Harness(answers: [Completer<AgentResponse>().future, 'Tamam.']);
    harness.speech.phrases.add('sesli not');
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final hold = await tester.createGesture();
    await hold.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 10),
    );
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    // A turn starts by itself meanwhile: a shared text, or a waiting message's retry.
    unawaited(session.send('paylaşılan'));
    await tester.pump();
    expect(session.busy, isTrue);
    // The held button is still there, so the let-go reaches it.
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget);
    await hold.up(timeStamp: const Duration(seconds: 12));
    await tester.pump();
    expect(find.text('Listening…'), findsNothing); // the recording ended with the let-go
    await tester.tap(find.byTooltip('Stop the answer'));
    await tester.pumpAndSettle();
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
        tester.getCenter(find.byTooltip('Tap or hold to talk')),
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
      (w) => w is Semantics && w.properties.label == 'Tap or hold to talk',
    );
    expect(tester.widget<Semantics>(talk).properties.enabled, isTrue);
    tester.widget<Semantics>(talk).properties.onTap!();
    await tester.pump();
    expect(find.text('Listening… tap to send'), findsOneWidget);
    final stop = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Stop and send',
    );
    tester.widget<Semantics>(stop).properties.onTap!();
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['klavyeden', 'okuyucudan']);
  });

  testWidgets('chat: hold to talk, let go to send; the answer is read aloud', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Cevap.', 'Yazdın.', 'Dokundun.', 'Yeniden.', 'A', 'B']);
    harness.speech.phrases.add('merhaba');
    final reading = Completer<void>();
    harness.voice.holding = reading;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    expect(find.byKey(const Key('voice-state')), findsNothing);
    final hold = await tester.createGesture();
    await hold.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
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
    // A tap starts it and leaves it on; the button turns to Stop, a tap there sends (#452).
    harness.speech.phrases.add('dokunarak');
    final tap = await tester.createGesture();
    await tap.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 13),
    );
    await tester.pump();
    await tap.up(timeStamp: const Duration(seconds: 13, milliseconds: 100));
    await tester.pump();
    expect(find.text('Listening… tap to send'), findsOneWidget); // on after the finger is up
    expect(find.byTooltip('Stop and send'), findsOneWidget);
    expect(find.byIcon(AppIcons.send), findsOneWidget);
    final stop = await tester.createGesture();
    await stop.down(
      tester.getCenter(find.byTooltip('Stop and send')),
      timeStamp: const Duration(seconds: 16),
    );
    await tester.pump();
    await stop.up(timeStamp: const Duration(seconds: 16, milliseconds: 80));
    await tester.pumpAndSettle();
    expect(find.text('dokunarak'), findsOneWidget);
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget);
    // Started by a tap but ended elsewhere: the button is the talk button again.
    harness.speech.phrases.add('yeniden');
    final again1 = await tester.createGesture();
    await again1.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 17),
    );
    await tester.pump();
    await again1.up(timeStamp: const Duration(seconds: 17, milliseconds: 50));
    await tester.pump();
    await harness.speech.finish(); // the recognizer ended by itself (silence)
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget);
    // A tap-started recording can be dropped: nothing is sent.
    final asked = harness.provider.asked.length;
    final drop = await tester.createGesture();
    await drop.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 18),
    );
    await tester.pump();
    await drop.up(timeStamp: const Duration(seconds: 18, milliseconds: 50));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.provider.asked, hasLength(asked));
    expect(find.byTooltip('Tap or hold to talk'), findsOneWidget);
    // The press on Stop taken away by the system: the next hold still sends on let-go.
    final tapped = await tester.createGesture();
    await tapped.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 19),
    );
    await tester.pump();
    await tapped.up(timeStamp: const Duration(seconds: 19, milliseconds: 50));
    await tester.pump();
    final taken2 = await tester.startGesture(tester.getCenter(find.byTooltip('Stop and send')));
    await tester.pump();
    await taken2.cancel();
    await tester.pumpAndSettle();
    harness.speech.phrases.add('sonra');
    final later = await tester.createGesture();
    await later.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 25),
    );
    await tester.pump();
    await later.up(timeStamp: const Duration(seconds: 27));
    await tester.pumpAndSettle();
    expect(find.text('sonra'), findsOneWidget);
    // A hold the system takes away (a call, say) ends like a let-go.
    final taken = await tester.startGesture(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
    );
    await tester.pump();
    await taken.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-state')), findsNothing);
    // No recognizer: says so.
    harness.speech.failure = const VoiceUnavailable();
    final again = await tester.createGesture();
    await again.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 20),
    );
    await tester.pumpAndSettle();
    await again.up(timeStamp: const Duration(seconds: 22));
    await tester.pumpAndSettle();
    expect(find.textContaining('Speech recognition is not available'), findsOneWidget);
  });

  testWidgets('chat: a tap-started recording shows how long it has listened (#573)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final tap = await tester.createGesture();
    await tap.down(
      tester.getCenter(find.byTooltip('Tap or hold to talk')),
      timeStamp: const Duration(seconds: 10),
    );
    await tester.pump();
    await tap.up(timeStamp: const Duration(seconds: 10, milliseconds: 100));
    await tester.pump();
    expect(find.text('0:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:02'), findsOneWidget);
    await tester.pump(const Duration(seconds: 58));
    expect(find.text('1:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1:00'), findsNothing);
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
    for (final name in ['Model', 'Voice', 'Sync', 'Appearance', 'About']) {
      expect(section(name), findsOneWidget, reason: name);
    }
    // The model first, alone.
    expect(find.text('CONNECTED MODELS'), findsOneWidget);
    expect(find.text('App language'), findsNothing);

    await tester.tap(section('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('App language'), findsOneWidget);
    expect(find.text('CONNECTED MODELS'), findsNothing);

    await tester.tap(section('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Speech recognition on this device'), findsOneWidget);

    await tester.tap(section('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Notes folder'), findsNothing); // no path to show (#207)

    // About holds the version and updates only (#514, #566).
    await tester.tap(section('About'));
    await tester.pumpAndSettle();
    expect(find.text('Notelore · development build'), findsOneWidget);
    expect(find.text('Remove all models from this device'), findsNothing);

    await tester.tap(section('Model'));
    await tester.pumpAndSettle();
    expect(find.text('Remove all models from this device'), findsOneWidget);
  });

  testWidgets('settings: the app version at the bottom', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'About');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Notelore · development build'), findsOneWidget); // no release version
    expect(find.byType(NoteloreMark), findsOneWidget); // About wears the mark (#340)
    // A release build names its version.
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(session, version: '0.7.0')));
    await tester.tap(find.text('About')); // a narrow window lists the categories
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Notelore 0.7.0'), findsOneWidget);
  });

  testWidgets('settings: web search can be turned off', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Model');
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
    await openSettings(tester, 'Model');
    expect(find.textContaining('like the author of a book'), findsOneWidget);
  });

  testWidgets('settings: Ollama cannot search the web', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, provider: 'Ollama (local)');
    await openSettings(tester, 'Model');
    expect(find.text('Not available with this provider.'), findsOneWidget);
  });

  testWidgets('settings: pick dark mode', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(session.appearance, Appearance.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme!.colorScheme.primary, noteloreTheme(Brightness.dark).colorScheme.primary);
  });

  testWidgets('settings: the appearance choices wrap at 2x without breaking a word (#714)', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    final system = tester.getSize(find.text('System'));
    final dark = tester.getSize(find.text('Dark'));
    expect(system.height, dark.height); // a two-line System would be twice as tall
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings: switch the app to Turkish and back', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Türkçe').last);
    await tester.pumpAndSettle();
    expect(find.text('Görünüm'), findsOneWidget); // the page, in Turkish at once
    expect(find.text('Uygulama dili'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sohbet'), findsOneWidget);
    expect(find.text('Not almamı istediğin bir şey yaz ya da notlarına sor.'), findsOneWidget);
    await openSettings(tester, 'Görünüm');
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
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
    expect(
      find.text('Claude Sonnet 5.5'),
      findsOneWidget,
    ); // the provider's default, readable (#722)
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
    await tester.tap(find.byTooltip('Stop the answer'));
    await tester.pumpAndSettle();
  });

  testWidgets('chat: with one model the chip names it, with no menu (#511, #757)', (tester) async {
    phone(tester);
    final harness = Harness()..models = ['claude-sonnet-5-5'];
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Nothing to switch to: the model is chosen in Settings > Model.
    expect(find.byTooltip('Change the model'), findsNothing);
    expect(find.text('Claude Sonnet 5.5'), findsOneWidget);
    await openSettings(tester, 'Model');
    expect(find.text('Claude Sonnet 5.5'), findsWidgets);
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

  testWidgets('chat: a banner keeps to the chat column on a desktop (#769)', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    harness.models = ['model-a', 'model-b'];
    await session.refreshModels();
    await tester.pumpAndSettle();
    final banner = tester.getRect(find.byType(MaterialBanner));
    expect(banner.width, lessThanOrEqualTo(Layout.column));
    expect(banner.center.dx, closeTo(tester.getCenter(find.byKey(const Key('message'))).dx, 8));
    expect(find.widgetWithText(FilledButton, 'Change model'), findsOneWidget);
  });

  testWidgets('notes: the sync state follows a sync under the title (#774)', (tester) async {
    phone(tester);
    final auth = FakeAuth()..granted = true;
    final harness = Harness(auth: auth);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await session.connectDrive();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
    harness.remote.hold = Completer();
    unawaited(session.syncNow());
    await tester.pump();
    expect(find.text('Syncing…'), findsOneWidget);
    harness.remote.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
    await tester.tap(find.text('Synced just now'));
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsOneWidget); // the state opens Settings › Sync
    await tester.pageBack();
    await tester.pumpAndSettle();
    session.lastSynced = null;
    session.notifyListeners();
    await tester.pump();
    expect(find.text('Not synced yet'), findsOneWidget);
    harness.remote.failure = const NetworkError('offline');
    await session.syncNow();
    await tester.pumpAndSettle();
    expect(find.text('Not synced'), findsOneWidget);
  });
  testWidgets('notes: the sync state time moves on (#774)', (tester) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 1, 12);
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    await session.connectDrive();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Synced 2 min ago'), findsOneWidget);
  });
  testWidgets('notes: a note opened on a phone names itself once (#508)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget); // its heading, not the bar as well
  });

  testWidgets('notes: search by title or by what a note says; none says so (#508)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final books = createNote(harness.paths.notes.path, 'topic', 'Books', today: today);
    addEntry(books, 'Sinekli Bakkal by Halide Edib', today: today);
    createNote(harness.paths.notes.path, 'project', 'Garden shed', today: today);
    createNote(harness.paths.notes.path, 'project', 'İş planı', today: today);
    session.notifyListeners();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('notes-search'));
    await tester.enterText(search, 'sinekli'); // in a note's words
    await tester.pumpAndSettle();
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Garden shed'), findsNothing);
    await tester.enterText(search, 'GARDEN'); // in a title, any case
    await tester.pumpAndSettle();
    expect(find.text('Garden shed'), findsOneWidget);
    expect(find.text('Books'), findsNothing);
    // More words narrow it: every word, in the title or the words.
    await tester.enterText(search, 'shed garden');
    await tester.pumpAndSettle();
    expect(find.text('Garden shed'), findsOneWidget);
    await tester.enterText(search, 'garden sinekli');
    await tester.pumpAndSettle();
    expect(find.text('Garden shed'), findsNothing);
    expect(find.text('Books'), findsNothing);
    await tester.enterText(search, 'iş'); // Turkish capitals fold too
    await tester.pumpAndSettle();
    expect(find.text('İş planı'), findsOneWidget);
    await tester.enterText(search, 'zeppelin');
    await tester.pumpAndSettle();
    expect(find.textContaining('No note mentions "zeppelin"'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Garden shed'), findsOneWidget);
  });

  testWidgets('notes: a related note opens on its own page (#802)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'topic', 'Okunan kitaplar', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('RELATED NOTES'), findsOneWidget);
    await tester.tap(find.text('Okunan kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget); // the related card of the new page
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Okunan kitaplar'), findsOneWidget); // back on the first one's page
  });

  testWidgets('notes: a search shows the line that matched, its words marked (#803)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final books = createNote(harness.paths.notes.path, 'topic', 'Books', today: today);
    addEntry(books, 'Sinekli Bakkal by Halide Edib', today: today);
    addEntry(books, 'Bought a reading lamp', today: today);
    session.notifyListeners();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Bought a reading lamp'), findsOneWidget); // the newest words
    final search = find.byKey(const Key('notes-search'));
    await tester.enterText(search, 'SİNEKLİ halide');
    await tester.pumpAndSettle();
    expect(find.text('Bought a reading lamp'), findsNothing);
    final line = find.text('Sinekli Bakkal by Halide Edib', findRichText: true);
    final spans = <TextSpan>[];
    tester.widget<RichText>(line).text.visitChildren((span) {
      if (span case TextSpan(text: _?)) spans.add(span);
      return true;
    });
    final accent = Theme.of(tester.element(line)).colorScheme.primary;
    expect(
      [for (final span in spans) (span.text, span.style?.color == accent)],
      [('Sinekli', true), (' Bakkal by ', false), ('Halide', true), (' Edib', false)],
    );
    expect(spans.first.style?.fontWeight, FontWeight.w600);
    await tester.enterText(search, 'books'); // only the title: the newest words stay
    await tester.pumpAndSettle();
    expect(find.text('Bought a reading lamp', findRichText: true), findsOneWidget);
  });

  testWidgets('notes: the archive lists what was deleted and restores it', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    // In the look every empty screen has.
    expect(
      find.widgetWithText(EmptyState, 'The archive is empty. Deleted notes go here.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);
    expect(find.byTooltip('Restore'), findsOneWidget); // on the row, not only in the reader
    // A date as people say it, and no file path (#508).
    expect(find.text('archived 30 Sep'), findsOneWidget);
    expect(find.textContaining('topics/'), findsNothing);
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    // Its heading names it, once; Restore is in the bar, clear of any notice.
    expect(find.text('Kitaplar'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Restore')),
      findsOneWidget,
    );
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored "Kitaplar".'), findsOneWidget);
    expect(find.text('The archive is empty. Deleted notes go here.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget); // back in the notes
  });

  testWidgets('notes: a pinned note shows under Pinned, above the others (#775)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'topic', 'Filmler', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('OTHERS'), findsNothing);
    // Filmler comes first (same day, by slug); pinned, Kitaplar goes above it.
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin'), findsOneWidget);
    // Coloured in the app bar too, not only filled.
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.pinOn)).color,
      Theme.of(tester.element(find.byIcon(AppIcons.pinOn))).colorScheme.primary,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('PINNED'), lessThan(top('Kitaplar')));
    expect(top('Kitaplar'), lessThan(top('OTHERS')));
    expect(top('OTHERS'), lessThan(top('Filmler')));
    expect(
      tester.getSemantics(find.text('PINNED')),
      matchesSemantics(label: 'Pinned', isHeader: true),
    );
    // Only pinned notes found: no empty Others under them.
    await tester.enterText(find.byKey(const Key('notes-search')), 'Kitaplar');
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('OTHERS'), findsNothing);
    await tester.enterText(find.byKey(const Key('notes-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pin'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
  });

  testWidgets('notes: Coming up lists the next open todos, soonest first, at most 3 (#782)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness, clock: () => DateTime(2026, 11, 7, 10));
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    final day = DateTime(2026, 11, 1);
    final atlas = createNote(root, 'project', 'Atlas', today: day);
    addTodo(atlas, 'Book the room', due: DateTime(2026, 11, 4), today: day); // late: not coming
    addTodo(atlas, 'Kick-off notes', due: DateTime(2026, 11, 12), today: day);
    addTodo(atlas, 'Done already', due: DateTime(2026, 11, 8), today: day);
    completeTodo(atlas, 3, today: day);
    final trip = createNote(root, 'project', 'Lisbon trip', today: day);
    addTodo(trip, 'Check in', due: DateTime(2026, 11, 18), today: day);
    addTodo(trip, 'Pack', due: DateTime(2026, 11, 7), today: day); // today counts
    addTodo(trip, 'Taxi home', due: DateTime(2026, 11, 20), today: day); // the fourth
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('COMING UP'), findsOneWidget);
    expect(find.text('4 todos'), findsOneWidget);
    expect(find.text('Book the room'), findsNothing);
    expect(find.text('Done already'), findsNothing);
    expect(find.text('Taxi home'), findsNothing);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Pack'), lessThan(top('Kick-off notes')));
    expect(top('Kick-off notes'), lessThan(top('Check in')));
    expect(find.text('12'), findsOneWidget); // the day, its month under it
    expect(find.text('NOV'), findsNWidgets(3));
    // Above the notes, and a row opens its note.
    expect(top('Check in'), lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Atlas')).dy));
    // A search shows only what it found.
    await tester.enterText(find.byKey(const Key('notes-search')), 'Lisbon');
    await tester.pumpAndSettle();
    expect(find.text('COMING UP'), findsNothing);
    await tester.enterText(find.byKey(const Key('notes-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kick-off notes'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsOneWidget);
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('COMING UP'), findsNothing);
  });

  testWidgets('notes: at 2x text a Coming up day keeps its digits on one line (#782)', (
    tester,
  ) async {
    phone(tester);
    tester.view.physicalSize = const Size(900, 2400); // 360 dp
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = Harness();
    await pumpApp(tester, harness, clock: () => DateTime(2026, 11, 7, 10));
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Books', today: today);
    addTodo(path, 'Return it', due: DateTime(2026, 11, 12), today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    final day = tester.getSize(find.text('12'));
    expect(day.width, greaterThan(day.height)); // "12" side by side, not stacked
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes: chips filter by kind and tag, with search and Coming up (#793)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => DateTime(2026, 11, 7, 10));
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    final day = DateTime(2026, 11, 1);
    final atlas = createNote(root, 'project', 'Atlas', tags: ['work'], today: day);
    addTodo(atlas, 'Kick-off notes', due: DateTime(2026, 11, 12), today: day);
    final trip = createNote(root, 'project', 'Lisbon trip', tags: ['family'], today: day);
    addTodo(trip, 'Pack', due: DateTime(2026, 11, 8), today: day);
    createNote(root, 'topic', 'Desk setup', tags: ['work', 'home'], today: day);
    createNote(root, 'topic', 'Books', today: day);
    await session.pinNote(
      session.listNotes().firstWhere((n) => n.title == 'Desk setup'),
      pinned: true,
    );
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    Finder chip(String label) => find.widgetWithText(FilterChip, label);
    bool on(String label) => tester.widget<FilterChip>(chip(label)).selected;
    Future<void> pick(String label) async {
      await tester.ensureVisible(chip(label));
      await tester.tap(chip(label));
    }

    // All, the kinds, then the tags, the most used first.
    double left(String label) => tester.getTopLeft(chip(label)).dx;
    expect(left('All'), lessThan(left('Projects')));
    expect(left('Projects'), lessThan(left('Topics')));
    expect(left('Topics'), lessThan(left('#work')));
    expect(left('#work'), lessThan(left('#family')));
    expect(left('#family'), lessThan(left('#home')));
    expect(on('All'), isTrue);
    expect(tester.getSize(chip('Topics')).height, greaterThanOrEqualTo(48));
    Finder note(String title) => find.widgetWithText(ListTile, title);
    await pick('Projects');
    await tester.pumpAndSettle();
    expect(on('All'), isFalse);
    expect(note('Atlas'), findsOneWidget);
    expect(note('Lisbon trip'), findsOneWidget);
    expect(note('Desk setup'), findsNothing);
    expect(find.text('PINNED'), findsNothing);
    // One tag joins the kind; Coming up follows.
    await pick('#work');
    await tester.pumpAndSettle();
    expect(note('Atlas'), findsOneWidget);
    expect(note('Lisbon trip'), findsNothing);
    expect(find.text('Kick-off notes'), findsOneWidget);
    expect(find.text('Pack'), findsNothing);
    // One kind at a time, and the tag stays.
    await pick('Topics');
    await tester.pumpAndSettle();
    expect(on('Projects'), isFalse);
    expect(note('Desk setup'), findsOneWidget);
    expect(note('Books'), findsNothing);
    expect(find.text('COMING UP'), findsNothing);
    expect(find.text('PINNED'), findsOneWidget);
    // A tag tapped again comes off; one tag at a time.
    await pick('#work');
    await tester.pumpAndSettle();
    expect(note('Books'), findsOneWidget);
    await pick('#family');
    await tester.pumpAndSettle();
    expect(find.text('No notes here. Pick another filter, or All.'), findsOneWidget);
    await pick('Topics');
    await tester.pumpAndSettle();
    expect(note('Lisbon trip'), findsOneWidget);
    await pick('#home');
    await tester.pumpAndSettle();
    expect(on('#family'), isFalse);
    expect(note('Desk setup'), findsOneWidget);
    // The chosen tag moves first, in sight when the screen opens again.
    expect(left('#home'), lessThan(left('#work')));
    expect(left('Topics'), lessThan(left('#home')));
    // With search: both narrow.
    await tester.enterText(find.byKey(const Key('notes-search')), 'Atlas');
    await tester.pumpAndSettle();
    expect(find.textContaining('No note mentions "Atlas"'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('notes-search')), '');
    await tester.pumpAndSettle();
    // Kept while the app runs, across tabs.
    await tester.tap(tab('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(on('#home'), isTrue);
    expect(note('Atlas'), findsNothing);
    // All clears both.
    await pick('Projects');
    await tester.pumpAndSettle();
    await pick('All');
    await tester.pumpAndSettle();
    expect(on('All'), isTrue);
    expect(on('Projects'), isFalse);
    expect(on('#home'), isFalse);
    for (final title in ['Atlas', 'Lisbon trip', 'Desk setup', 'Books']) {
      expect(note(title), findsOneWidget);
    }
  });

  testWidgets('notes: the eight most used tags, and a chosen one always (#793)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    for (var i = 0; i < 10; i++) {
      createNote(root, 'topic', 'Note $i', tags: ['t$i', 'common'], today: today);
    }
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    // #common, then by name.
    expect(find.widgetWithText(FilterChip, '#common'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '#t6'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '#t7'), findsNothing);
    session.notesTag = 't9';
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Note 9'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Note 8'), findsNothing);
    final chosen = find.widgetWithText(FilterChip, '#t9', skipOffstage: false);
    expect(tester.widget<FilterChip>(chosen).selected, isTrue);
  });

  testWidgets('notes: on Sunday the week looks back over Coming up, and closes (#804)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => DateTime(2026, 11, 8, 10));
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    final day = DateTime(2026, 11, 1);
    final atlas = createNote(root, 'project', 'Atlas', today: day);
    recordDecision(atlas, 'db', 'SQLite', today: DateTime(2026, 11, 3));
    recordDecision(atlas, 'host', 'Fly', today: DateTime(2026, 11, 5));
    recordDecision(atlas, 'auth', 'Passkeys', today: DateTime(2026, 11, 6));
    recordDecision(atlas, 'ci', 'Actions', today: DateTime(2026, 11, 7)); // the fourth
    addTodo(atlas, 'Book the room', due: DateTime(2026, 11, 2), today: day);
    addTodo(atlas, 'Shipped it', due: DateTime(2026, 11, 4), today: day);
    addTodo(atlas, 'Kick-off notes', due: DateTime(2026, 11, 12), today: day);
    completeTodo(atlas, 2, today: DateTime(2026, 11, 4));
    final books = createNote(root, 'topic', 'Books', today: day);
    addTodo(books, 'Return it', due: DateTime(2026, 10, 30), today: day);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    String count(String group) => tester
        .widget<Text>(
          find.descendant(of: find.byKey(Key('week-$group')), matching: find.byType(Text)).last,
        )
        .data!;
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('2–8 NOV'), findsOneWidget);
    expect(count('decided'), '4');
    expect(count('done'), '1');
    expect(count('overdue'), '2');
    expect(find.text('db: SQLite'), findsOneWidget);
    expect(find.text('auth: Passkeys'), findsOneWidget);
    expect(find.text('ci: Actions'), findsNothing);
    expect(find.text('Shipped it'), findsOneWidget);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Return it'), lessThan(top('Book the room'))); // the oldest first
    expect(top('THIS WEEK'), lessThan(top('COMING UP')));
    // The filters narrow it; a search hides it.
    await tester.tap(find.widgetWithText(FilterChip, 'Topics'));
    await tester.pumpAndSettle();
    expect(count('decided'), '0');
    expect(count('overdue'), '1');
    expect(find.text('Book the room'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.enterText(find.byKey(const Key('notes-search')), 'Atlas');
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
    await tester.enterText(find.byKey(const Key('notes-search')), '');
    await tester.pumpAndSettle();
    // A row opens its note.
    await tester.tap(find.text('host: Fly'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Closed for this week, on this device.
    await tester.tap(find.byTooltip('Hide for this week'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
    expect(session.lookBackClosed, '2026-11-08');
    expect(find.text('COMING UP'), findsOneWidget);
  });

  testWidgets('notes: no week look back on other days, an empty week, or once closed (#804)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    var now = DateTime(2026, 11, 7, 10);
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Books', today: today);
    addTodo(path, 'Return it', due: DateTime(2026, 11, 1), today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing); // a Saturday
    now = DateTime(2026, 11, 15, 10);
    session.closeLookBack('2026-11-08'); // last week's
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsOneWidget);
    // At 2x text on a narrow phone nothing overflows.
    tester.view.physicalSize = const Size(900, 2400); // 360 dp
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    session.closeLookBack('2026-11-15');
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
    now = DateTime(2026, 11, 22, 10);
    completeTodo(path, 1, today: now); // dated in an older week: nothing to look back on
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
  });

  testWidgets('notes: no Coming up without open todos ahead (#782)', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness, clock: () => DateTime(2026, 11, 7, 10));
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Books', today: today);
    addTodo(path, 'Return the old one', due: DateTime(2026, 11, 1), today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('COMING UP'), findsNothing);
  });

  testWidgets('notes: restore directly from the archive row (#508)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await session.deleteNote(session.listNotes().single);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored "Kitaplar".'), findsOneWidget);
    expect(find.text('Kitaplar'), findsNothing); // the row left the archive
    expect(session.listNotes().single.title, 'Kitaplar');
  });

  testWidgets('notes: an archive folder that is not a date still lists, as it is named (#508)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    // Put there by hand, or by an older app: the folder is not a date.
    final odd = Directory(p.join(harness.paths.notes.path, '_archive', 'old stuff', 'topics'))
      ..createSync(recursive: true);
    createNote(odd.parent.parent.parent.path, 'topic', 'Kitaplar', today: today);
    File(p.join(harness.paths.notes.path, 'topics', 'kitaplar.md'))
        .renameSync(p.join(odd.path, 'kitaplar.md'));
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);
    expect(find.text('archived old stuff'), findsOneWidget);
  });

  testWidgets('notes: the archive deletes a note for good, or all of it, after asking (#438)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    for (final title in ['Kitaplar', 'Filmler', 'Diziler']) {
      createNote(harness.paths.notes.path, 'topic', title, today: today);
    }
    for (final note in session.listNotes()) {
      await session.deleteNote(note);
    }
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    // One, from its row menu: asked first; Cancel keeps it.
    var first = session.listArchived().first;
    await tester.tap(find.byKey(ValueKey('archive-note-more-${first.original}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for good'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.listArchived(), hasLength(3));
    first = session.listArchived().first;
    await tester.tap(find.byKey(ValueKey('archive-note-more-${first.original}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for good'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted "${first.title}" for good.'), findsOneWidget);
    expect(session.listArchived(), hasLength(2));
    // One, from its page: back to the list once gone.
    await tester.tap(find.text(session.listArchived().first.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete for good'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsNothing);
    expect(session.listArchived(), hasLength(1));
    // All the rest, from the archive menu, with how many.
    await tester.tap(find.byKey(const Key('archive-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty the archive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 note'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Empty the archive'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted 1 note from the archive for good.'), findsOneWidget);
    expect(find.text('The archive is empty. Deleted notes go here.'), findsOneWidget);
    expect(find.byKey(const Key('archive-more')), findsNothing);
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
    await tester.tap(tab('Notes'));
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
    await tester.tap(tab('Notes'));
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
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Moved "Kitaplar" to the archive.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Moved "Kitaplar" to the archive.'), findsNothing);
  });

  testWidgets('chat: an audio file is heard on the device and goes as its words (#285)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(answers: ['Saved.']);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final memo = wav(List.filled(16000, 0.1));
    Future<void> attach(String name, List<int> bytes) async {
      harness.files.picked = [XFile.fromData(Uint8List.fromList(bytes), path: name)];
      await tester.tap(find.byTooltip('Attach a file'));
      await tester.pumpAndSettle();
    }

    // Before Whisper is on this device: said why, nothing sent.
    await attach('memo.wav', memo);
    expect(find.textContaining('memo.wav needs on-device speech recognition'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    File(p.join(harness.paths.state.path, 'models', 'whisper-small', 'w.onnx'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('whisper bytes');
    expect(session.whisper.ready, isTrue);
    // A format this device cannot open (an M4A here, no decoder): said so.
    await attach('call.m4a', [0, 0, 0, 0x20, ...'ftypM4A '.codeUnits, 0, 0]);
    expect(find.textContaining('call.m4a cannot be opened on this device'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Heard, but no words in it: never sent as something.
    harness.fileTranscriber.answers.add('[BLANK_AUDIO]');
    await attach('quiet.wav', memo);
    expect(find.textContaining('No words were heard in quiet.wav'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Words: they go to the model like a text file, its name in the bubble.
    harness.fileTranscriber.answers.add('Buy milk on Friday.');
    await attach('memo.wav', memo);
    // The original is kept beside the notes, and the model is told where, to link it (#279).
    final kept = Directory(p.join(harness.paths.notes.path, 'attachments'))
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect([for (final f in kept) p.basename(f.path)], ['memo.wav']);
    expect(kept.single.readAsBytesSync(), memo);
    expect(
      harness.provider.asked.single,
      matches(
        RegExp(r'<attached file="memo.wav" original="attachments/[\d-]+/memo.wav">\nBuy milk'),
      ),
    );
    expect(harness.fileTranscriber.heard.last, 16000);
    expect(find.text('memo.wav'), findsOneWidget);
    // Another format, opened by the platform's decoder.
    harness
      ..decodeAudio = ((_) async => Float32List(16000))
      ..fileTranscriber.answers.add('Call the bank.');
    harness.provider.answers.add('Saved.');
    await attach('call.m4a', [0, 0, 0, 0x20, ...'ftypM4A '.codeUnits, 0, 0]);
    expect(harness.provider.asked.last, contains('Call the bank.'));
    await tester.pumpAndSettle();
    // A recording whose words run past the limit for one message: refused like a long text.
    harness.fileTranscriber.answers.add('word ' * 50000);
    await attach('lecture.wav', memo);
    expect(find.textContaining('lecture.wav is too large'), findsOneWidget);
    expect(harness.provider.asked, hasLength(2));
  });

  testWidgets('chat: audio heard while the app locked is not sent (#285, #387)', (tester) async {
    phone(tester);
    var now = DateTime.utc(2026, 10, 17, 12);
    final harness = Harness();
    final session = await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    File(p.join(harness.paths.state.path, 'models', 'whisper-small', 'w.onnx'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('whisper bytes');
    await session.lock.set('2468');
    harness.fileTranscriber
      ..hold = Completer<void>()
      ..answers.add('Private words.');
    harness.files.picked = [XFile.fromData(wav(List.filled(16000, 0.1)), path: 'memo.wav')];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump();
    toBackground(tester);
    now = now.add(const Duration(minutes: 1));
    toForeground(tester);
    await tester.pumpAndSettle();
    harness.fileTranscriber.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
  });

  testWidgets('chat: a file too big to attach is refused, and nothing is sent (#315)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    harness.files.picked = [
      XFile.fromData(Uint8List(0), path: 'huge.pdf', length: 30 * 1024 * 1024),
    ];
    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pump();
    expect(find.textContaining('huge.pdf is too big'), findsOneWidget);
    expect(harness.provider.asked, isEmpty);
  });

  testWidgets('notes: a remote image loads only on a tap; one on the device shows (#311, #339)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    final path = createNote(root, 'topic', 'Kitaplar', today: today);
    addEntry(path, 'See ![the chart](https://evil.example/p.png?q=notes)', today: today);
    addEntry(path, 'And ![a photo](../attachments/2026-10-18/photo.png)', today: today);
    addEntry(path, 'Not ![outside](../../secret.png)', today: today);
    File(p.join(root, 'attachments', '2026-10-18', 'photo.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0]);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    // The one on the device shows; the remote one is a box saying where it would come from.
    expect(tester.widgetList<Image>(find.byType(Image)).map((i) => i.image.runtimeType), [
      FileImage,
    ]);
    expect(find.text('the chart'), findsOneWidget);
    expect(find.textContaining('evil.example'), findsOneWidget);
    // One outside the notes folder is never read.
    expect(find.text('outside'), findsOneWidget);
    expect(find.text("Couldn't load"), findsOneWidget);
    // Only a tap fetches it.
    await tester.tap(find.textContaining('Tap to show'));
    await tester.pump();
    expect(tester.widgetList<Image>(find.byType(Image)).map((i) => i.image), [
      isA<NetworkImage>(),
      isA<FileImage>(),
    ]);
    expect(find.textContaining('Tap to show'), findsNothing);
    // One that cannot be shown (damaged, unreachable) says so, with its words.
    final shown = tester.widget<Image>(find.byType(Image).last);
    final fallback = shown.errorBuilder!(tester.element(find.byType(Image).last), 'bad', null);
    // While a remote one comes, the same box turns.
    final remote = tester.widget<Image>(find.byType(Image).first);
    final coming = remote.loadingBuilder!(
      tester.element(find.byType(Image).first),
      const SizedBox(),
      const ImageChunkEvent(cumulativeBytesLoaded: 1, expectedTotalBytes: 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: Column(children: [fallback, coming])),
      ),
    );
    expect(find.text('a photo'), findsOneWidget);
    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('notes: delete from the reader, with undo', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    expect(find.text('Moved "Kitaplar" to the archive.'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget); // a close button too
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);

    // From the open note: the reader's delete button, and back to the list.
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsNothing);
    expect(session.listNotes().map((n) => n.title), ['Kitaplar']);

    // Gone meanwhile (a sync, a chat turn): says so instead of failing.
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    File(notePath(harness.paths.notes.path, 'topic', 'kitaplar')).deleteSync();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('"Kitaplar" was already gone.'), findsOneWidget);
  });

  testWidgets('notes: a row shows its newest words, tags and open todos (#773)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(
      harness.paths.notes.path,
      'project',
      'Mopsos',
      tags: ['investing'],
      today: today,
    );
    addEntry(path, 'Picked SQLite for the database.', today: today);
    addEntry(path, 'Considered crypto, postponed.', today: today);
    addTodo(path, 'Add Drive backup', today: today);
    addTodo(path, 'Write the README', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(session.listNotes().single.openTodos, 2);
    expect(find.text('Considered crypto, postponed.'), findsOneWidget); // the newest words
    // On the row; the filter chip above is another (#793).
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.textContaining('#investing')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('2')),
      findsOneWidget,
    ); // the open-todo count
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
        'Created, nothing to add yet.',
      ],
    );
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet. Tell the assistant something to remember.'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing); // nothing to filter (#793)
    expect(find.widgetWithText(OutlinedButton, 'Import notes'), findsOneWidget);
    // The way to make one: the chat, as the main action (#721).
    await tester.tap(find.text('Go to chat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message')), 'Mopsos diye proje aç');
    await tester.pump(); // the Send button appears with the text
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsOneWidget);
    expect(find.text('Project · updated 30 Sep'), findsOneWidget);
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsOneWidget);
    expect(find.text('Decisions'), findsNothing); // a new note's empty sections have no heading
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView).last, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsOneWidget);
  });

  testWidgets('notes: a checkbox completes a todo and a second tap reopens it (#512)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    addTodo(path, 'Return the book', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(File(path).readAsStringSync(), contains('- [x] '));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(File(path).readAsStringSync(), contains('- [ ] '));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    // The note gone since it opened: the page keeps its words (#512).
    File(path).deleteSync();
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Return the book'), findsOneWidget);
  });

  testWidgets('notes: list actions sit in one overflow; the reader owns export and delete (#555)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Archive'), findsOneWidget);
    expect(find.byTooltip('Import notes'), findsNothing);
    expect(find.byTooltip('Export notes'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);

    // Refresh is in sight (#640); the overflow keeps import and export.
    await tester.tap(find.byTooltip('Refresh'));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(RefreshProgressIndicator), findsOneWidget); // up long enough to see
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.ancestor(of: find.byTooltip('Refresh'), matching: find.byType(IconButton)))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const Key('notes-more')));
    await tester.pumpAndSettle();
    expect(find.text('Import notes'), findsOneWidget);
    expect(find.text('Export notes'), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Export'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  /// The words of a line of text on screen: an answer's (in its SelectionArea)
  /// or a selectable one's.
  String? shownText(RenderObject r) => switch (r) {
    RenderParagraph() => r.text.toPlainText(),
    RenderEditable() => r.text!.toPlainText(),
    _ => null,
  };

  /// Taps the middle of [part] inside the one line that shows it.
  Future<void> tapOnPart(WidgetTester tester, String part) async {
    // Every element over a line reports its render object: once each.
    final line = tester.allRenderObjects.toSet().singleWhere(
      (r) => shownText(r)?.contains(part) ?? false,
    );
    final start = shownText(line)!.indexOf(part);
    final selection = TextSelection(baseOffset: start, extentOffset: start + part.length);
    final box = switch (line) {
      RenderParagraph() => line.getBoxesForSelection(selection),
      _ => (line as RenderEditable).getBoxesForSelection(selection),
    }.first;
    await tester.tapAt((line as RenderBox).localToGlobal(box.toRect().center));
  }

  testWidgets('chat: the Markdown of an answer is formatted, not shown raw; links open (#305)', (
    tester,
  ) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    const answer =
        'Saved to **Mopsos**.\n\n- Reason: _single user_\n\nSee [the docs](https://example.com/d).';
    await pumpApp(tester, Harness(answers: [answer]));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), '**not** markdown');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final lines = tester.allRenderObjects.map(shownText).nonNulls.toList();
    // No Markdown marks left in the answer; the user's words stay exactly as typed.
    expect(lines, containsAll(['Saved to Mopsos.', 'Reason: single user', 'See the docs.']));
    expect(lines.where((l) => l.contains('**') && l != '**not** markdown'), isEmpty);
    expect(lines, contains('**not** markdown'));
    final body = tester.widget<MarkdownBody>(answerBody);
    // One selection across the whole answer (#335), not one per paragraph.
    expect(body.selectable, isFalse);
    expect(find.ancestor(of: answerBody, matching: find.byType(SelectionArea)), findsOneWidget);
    // The bubble's own colour for every part, so it reads in both themes.
    final ink = Theme.of(tester.element(answerBody)).colorScheme.onSurface;
    final sheet = body.styleSheet!;
    expect(
      [
        sheet.p,
        sheet.listBullet,
        sheet.strong,
        sheet.em,
        sheet.h1,
        sheet.h3,
        sheet.code,
      ].map((s) => s!.color),
      everyElement(ink),
    );
    // A link looks like one: the theme's primary colour, underlined.
    final theme = Theme.of(tester.element(answerBody));
    expect(sheet.a!.color, theme.colorScheme.primary);
    expect(sheet.a!.decoration, TextDecoration.underline);
    // Code in a monospace face on every platform, not only where "monospace" exists,
    // on a tint that still shows in dark mode (#335).
    expect(sheet.code!.fontFamilyFallback, containsAll(['Menlo', 'Consolas']));
    expect(sheet.code!.backgroundColor, ink.withValues(alpha: AnswerStyle.tint));
    // List items sit closer than paragraphs, and a list stays under its lead-in (#335).
    expect(sheet.blockSpacing, Gap.xs);
    expect(sheet.pPadding, const EdgeInsets.only(top: Gap.xs));
    // No heading outgrows the bubble's few type sizes (#335).
    expect(sheet.h1!.fontSize, theme.textTheme.titleMedium!.fontSize);
    expect(sheet.h3!.fontWeight, AnswerStyle.headingWeight);
    // A heading stands as far from the words above it as a paragraph does.
    expect([
      sheet.h1Padding,
      sheet.h2Padding,
      sheet.h3Padding,
    ], everyElement(const EdgeInsets.only(top: Gap.xs)));
    // A code block is tinted once, by its box, not again behind its letters.
    final block = body.syntaxHighlighter!.format('cache.ttl = 24h');
    expect(block.text, 'cache.ttl = 24h');
    expect(block.style!.backgroundColor, isNull);
    expect(block.style!.fontFamily, 'monospace');
    // The paragraph's own step makes up the top of the bubble, so it is even.
    final bubble = tester.widget<Container>(
      find.ancestor(of: answerBody, matching: find.byType(Container)).first,
    );
    expect(bubble.padding!.vertical, (Gap.m - Gap.xs) * 2 - Gap.xs);
    await tapOnPart(tester, 'the docs');
    await tester.pump();
    expect(launcher.opened, ['https://example.com/d']);
  });

  testWidgets('chat: an image in an answer is never fetched; its words show instead (#305)', (
    tester,
  ) async {
    phone(tester);
    // A page the model read could ask for this: the address would carry the notes away.
    await pumpApp(
      tester,
      Harness(answers: ['Done. ![a chart](https://evil.example/p.png?q=notes)']),
    );
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'hi');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('a chart'), findsOneWidget);
  });

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

    await tester.tap(tab('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget); // and still selectable
    // Tapped where they are drawn, like a user would.
    await tester.tapOnText(find.textRange.ofSubstring('Example'));
    await tester.tapOnText(find.textRange.ofSubstring('https://example.com/bare'));
    await tester.pump();
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody).first);
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
    await openSettings(tester, 'Model');
    await tester.tap(find.byKey(const Key('model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b').last);
    await tester.pumpAndSettle();
    expect(session.model, 'model-b');
    expect(find.text('Model saved.'), findsOneWidget);
    expect(find.byTooltip('Refresh the model list'), findsNothing);
    final hold = Completer<void>();
    harness
      ..models = ['model-c']
      ..connectHold = hold;
    await tester.tap(find.byKey(const Key('model')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    hold.complete();
    await tester.pumpAndSettle();
    harness.connectHold = null;
    expect(session.models, ['model-c']);
    await tester.tap(find.text('Model').first); // close it again
    await tester.pumpAndSettle();
    harness.rejected = const TransientValidationError('Anthropic is not reachable');
    await tester.tap(find.byKey(const Key('model')));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic is not reachable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(session.models, ['model-c']);
    expect(find.text('model-c'), findsWidgets); // the stale list is still open
    harness
      ..rejected = null
      ..models = ['model-d'];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(session.models, ['model-d']);
    expect(find.text('model-d'), findsWidgets); // the fresh list is open
  });

  testWidgets('setup: only the step in a slim bar, the action pinned at the bottom (#337, #357)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Step 1 of 3'), findsOneWidget); // in the step header
    expect(find.text('Choose a model provider'), findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold).first);
    final button = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
    expect(screen.height - button.bottom, lessThanOrEqualTo(Gap.l));
    expect(find.byKey(const Key('setup-card')), findsNothing);
  });

  testWidgets('setup: the key page opens in the browser', (tester) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await pumpApp(tester, Harness());
    await choose(tester);
    await tester.tap(find.text('Open the Anthropic Console'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['https://console.anthropic.com/settings/keys']);
  });

  testWidgets('settings: change the model, then remove every model', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Model');
    expect(find.byKey(const ValueKey('connection-anthropic')), findsOneWidget);
    // The model is picked from the list, never typed: nothing to save by hand.
    final picker = tester.widget<DropdownMenu<String?>>(find.byKey(const Key('model')));
    expect(picker.requestFocusOnTap, isFalse);
    expect(find.text('Save model'), findsNothing);
    expect(session.model, 'claude-sonnet-5-5');
    // Removing every model sits beside the models, and asks first (#514).
    await tester.tap(find.text('Remove all models from this device'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a model provider'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text(harness.paths.notes.path), findsNothing); // never shown (#207)
    expect(find.text('Choose a model provider'), findsOneWidget);
  });

  testWidgets('settings: removing every model can be cancelled (#514)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester, 'Model');
    await tester.tap(find.text('Remove all models from this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.spec, isNotNull);
    expect(find.text('CONNECTED MODELS'), findsOneWidget);
    expect(find.text('Choose a model provider'), findsNothing);
  });

  testWidgets('the chat says when the device model is getting ready (#595)', (tester) async {
    phone(tester);
    final harness = Harness()..deviceModels = true;
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    final gate = Completer<void>();
    harness.deviceEngine.prefillGate = gate.future;
    final session = await pumpApp(tester, harness);
    await tester.runAsync(() => session.downloadDeviceModel());
    await session.connect(findProvider('device'), '');
    await tester.pump(const Duration(milliseconds: 1));
    expect(session.preparing, isTrue);
    expect(find.text(session.strings.devicePreparing), findsOneWidget);
    gate.complete();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(session.preparing, isFalse);
    expect(find.text(session.strings.devicePreparing), findsNothing);
  });

  group('a new on-device model in an app update (#767)', () {
    const url = 'https://models.test/q.gguf';

    /// The model of the version before is in use: old.gguf, not the pinned q.gguf.
    Future<Harness> updated(WidgetTester tester, {required bool metered}) async {
      final harness = Harness()
        ..deviceModels = true
        ..metered = metered;
      harness.pages[url] = 'model bytes';
      await tester.runAsync(() async {
        final before = harness.session(owned: false);
        await before.downloadDeviceModel();
        await before.connect(findProvider('device'), '');
        before.dispose();
        File(before.deviceModel.path('q.gguf')).renameSync(before.deviceModel.path('old.gguf'));
      });
      return harness;
    }

    testWidgets('on mobile data the chat asks first, then says it is done', (tester) async {
      phone(tester);
      final session = await pumpApp(tester, await updated(tester, metered: true));
      await tester.pumpAndSettle();
      expect(find.text(session.strings.deviceUpdateAsk(11)), findsOneWidget);
      await tester.tap(find.text('Download'));
      await settleUntil(tester, () => session.deviceUpdate == DeviceUpdate.done);
      expect(find.text(session.strings.deviceUpdated), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text(session.strings.deviceUpdated), findsNothing);
    });

    testWidgets('on Wi-Fi it shows the download, and a failure', (tester) async {
      phone(tester);
      final harness = await updated(tester, metered: false);
      final served = Completer<String>();
      harness.pages[url] = served.future;
      final session = await pumpApp(tester, harness);
      await tester.pump();
      expect(find.text(session.strings.deviceUpdating(0)), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      served.complete('other bytes');
      await settleUntil(tester, () => session.deviceUpdate == DeviceUpdate.failed);
      expect(find.text(session.strings.deviceUpdateFailed), findsOneWidget);
    });
  });

  testWidgets('app: the phone bar wears the brand label, the menu the surface (#782)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final theme = Theme.of(tester.element(find.text('Notelore')));
    final label = theme.extension<NoteloreTokens>()!.label;
    expect(tester.widget<Text>(find.text('Notelore')).style!.fontFamily, label.fontFamily);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(Star)), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.menu));
    await tester.pumpAndSettle();
    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.backgroundColor, theme.colorScheme.surface);
    expect((drawer.shape! as RoundedRectangleBorder).side.color, theme.colorScheme.outlineVariant);
    final settings = find.descendant(of: find.byType(Drawer), matching: find.text('Settings'));
    expect(tester.widget<Text>(settings).style!.fontFamily, label.fontFamily);
  });

  testWidgets('app: Orman glows at the top of the main screens (#782)', (tester) async {
    phone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final glow = Theme.of(tester.element(find.byType(ChatScreen)))
        .extension<NoteloreTokens>()!
        .glow;
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient == glow,
      ),
      findsOneWidget,
    );
    // Every tab's page and bar are clear, so the glow shows behind them all.
    for (final name in ['Chat', 'Notes', 'Calendar', 'About me']) {
      await tester.tap(tab(name));
      await tester.pumpAndSettle();
      final page = find.descendant(
        of: find.byType(Scaffold).first,
        matching: find.byType(Scaffold),
      );
      final bar = find.descendant(of: page.first, matching: find.byType(AppBar));
      for (final painted in [page, bar]) {
        final material = find.descendant(of: painted.first, matching: find.byType(Material));
        expect(tester.widget<Material>(material.first).color, Colors.transparent, reason: name);
      }
    }
  });
}
