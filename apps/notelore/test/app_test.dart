import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/mark.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/settings.dart';
import 'package:notelore/src/share_in.dart';
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
    await choose(tester);
    expect(find.textContaining('Anthropic Console'), findsOneWidget);
    expect(find.text('Open console.anthropic.com'), findsOneWidget); // the link as a button (#337)
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
    expect(find.textContaining('only see the files it creates'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.byKey(const Key('google-sign-in')), 100);
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
    expect(find.byType(NavigationBar), findsOneWidget);
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
    final example = EnglishStrings().examples.first;
    await tester.tap(find.text(example));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('message')));
    expect(field.controller!.text, example); // in the box to edit, not sent
    expect(find.byTooltip('Send'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text(example), findsOneWidget); // the bubble; the examples are gone
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('App lock'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
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
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('message')), findsNothing);
    await tester.enterText(find.byKey(const Key('unlock')), '1357');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text("That's not it. Try again."), findsOneWidget);
    expect(find.byKey(const Key('message')), findsNothing);
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
    await tester.tap(find.text('Notes'));
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
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Secret plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    const notice = 'Moved "Secret plans" to the archive.';
    expect(find.text(notice), findsOneWidget);
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

  testWidgets('shared text opens an editable composer and waits for Send', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['Saved.']);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'My draft');
    await tester.tap(find.text('Notes'));
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
    expect(copied, ['**Merhaba!**\nİkinci satır.']); // the text as it came
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
    expect(find.descendant(of: row, matching: find.byIcon(Icons.error_outline)), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.textContaining('having trouble')),
      findsOneWidget,
    );
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
    expect(find.descendant(of: status, matching: find.byIcon(Icons.more_horiz)), findsOneWidget);
    await tester.tap(find.byTooltip('Stop')); // end the turn and its deadline
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
    expect(tester.widget<Semantics>(talk).properties.enabled, isTrue);
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
    for (final name in ['Model', 'Voice', 'Sync', 'Appearance', 'About']) {
      expect(section(name), findsOneWidget, reason: name);
    }
    // The model first, alone.
    expect(find.text('Connected models'), findsOneWidget);
    expect(find.text('Language'), findsNothing);

    await tester.tap(section('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Connected models'), findsNothing);

    await tester.tap(section('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('Whisper speech recognition'), findsOneWidget);

    await tester.tap(section('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Notes folder'), findsNothing); // no path to show (#207)

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
    expect(find.byType(NoteloreMark), findsOneWidget); // About wears the mark (#340)
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
    await connect(tester, provider: 'Ollama (local)');
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
    expect(find.text('Not almamı istediğin bir şey yaz ya da notlarına sor.'), findsOneWidget);
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
    File(p.join(root, 'attachments', '2026-10-18', 'photo.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0]);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    // The one on the device shows; the remote one is a box saying where it would come from.
    expect(tester.widgetList<Image>(find.byType(Image)).map((i) => i.image.runtimeType), [
      FileImage,
    ]);
    expect(find.text('the chart'), findsOneWidget);
    expect(find.textContaining('evil.example'), findsOneWidget);
    // Only a tap fetches it.
    await tester.tap(find.textContaining('Tap to show'));
    await tester.pump();
    expect(tester.widgetList<Image>(find.byType(Image)).map((i) => i.image), [
      isA<NetworkImage>(),
      isA<FileImage>(),
    ]);
    expect(find.textContaining('Tap to show'), findsNothing);
    // One that cannot be shown (damaged, unreachable) leaves its words.
    final shown = tester.widget<Image>(find.byType(Image).last);
    final fallback = shown.errorBuilder!(tester.element(find.byType(Image).last), 'bad', null);
    expect((fallback as Text).data, 'a photo');
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
    String shown(RenderEditable r) => r.text!.toPlainText();
    final lines = tester.allRenderObjects.whereType<RenderEditable>().map(shown).toList();
    // No Markdown marks left in the answer; the user's words stay exactly as typed.
    expect(lines, containsAll(['Saved to Mopsos.', 'Reason: single user', 'See the docs.']));
    expect(lines.where((l) => l.contains('**') && l != '**not** markdown'), isEmpty);
    expect(lines, contains('**not** markdown'));
    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.selectable, isTrue);
    // The bubble's own colour for every part, so it reads in both themes.
    final ink = Theme.of(tester.element(find.byType(MarkdownBody))).colorScheme.onSurface;
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
    final theme = Theme.of(tester.element(find.byType(MarkdownBody)));
    expect(sheet.a!.color, theme.colorScheme.primary);
    expect(sheet.a!.decoration, TextDecoration.underline);
    // Code in a monospace face on every platform, not only where "monospace" exists.
    expect(sheet.code!.fontFamilyFallback, containsAll(['Menlo', 'Consolas']));
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
    await tester.tap(find.text('Open console.anthropic.com'));
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
    expect(find.byKey(const ValueKey('connection-anthropic')), findsOneWidget);
    // The model is picked from the list, never typed: nothing to save by hand.
    final picker = tester.widget<DropdownMenu<String?>>(find.byKey(const Key('model')));
    expect(picker.requestFocusOnTap, isFalse);
    expect(find.text('Save model'), findsNothing);
    expect(session.model, 'claude-sonnet-5-5');
    // Log out sits at the end of Settings: scroll all the way down.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text(harness.paths.notes.path), findsNothing); // never shown (#207)
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a model provider'), findsOneWidget);
  });
}
