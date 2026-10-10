import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'drive_auth_test.dart' show FakeLauncher;
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
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('selam'), findsOneWidget);
    expect(find.text('Merhaba!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message')), 'again');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('chat: input is locked while the model works', (tester) async {
    phone(tester);
    final harness = Harness(answers: ['done']);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session.busy = true;
    session.notifyListeners();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed,
      isNull,
    );
    session.busy = false;
    session.notifyListeners();
    await tester.pump();
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
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.text(harness.paths.notes.path), findsOneWidget);
    await tester.enterText(find.byKey(const Key('model')), 'claude-x');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // close the list over the button
    await tester.tap(find.text('Save model'));
    await tester.pumpAndSettle();
    expect(session.model, 'claude-x');
    expect(find.text('Model saved.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('model')), '');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.text('Save model'));
    await tester.pumpAndSettle();
    expect(session.model, 'claude-sonnet-5-5');
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a model provider'), findsOneWidget);
  });
}
