import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/quick_window.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/settings.dart';
import 'package:notelore/src/strings.dart' show AppLanguage;
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app_test.dart' show pumpApp;
import 'support.dart';

class FakeHost implements QuickHost {
  final calls = <String>[];
  var free = true;

  @override
  String get keys => 'Ctrl+Alt+N';

  @override
  Future<bool> listen({required bool on}) async {
    calls.add(on ? 'listen' : 'unlisten');
    return free;
  }

  @override
  Future<void> compact() async => calls.add('compact');

  @override
  Future<void> restore() async => calls.add('restore');

  @override
  Future<void> front() async => calls.add('front');
}

void main() {
  late Harness harness;
  late Session session;
  late FakeHost host;
  late QuickWindow quick;

  setUp(() {
    harness = Harness(answers: ['Hatırlatıcı eklendi.']);
    session = harness.session();
    host = FakeHost();
    quick = QuickWindow(session, host);
    addTearDown(quick.dispose);
  });

  test('the shortcut follows Settings, and says when another app holds it', () async {
    await quick.start();
    expect(host.calls, ['listen']);
    expect(quick.taken, isFalse);
    session.setQuickShortcut(on: false);
    await pumpEventQueue();
    expect(host.calls.last, 'unlisten');
    expect(quick.taken, isFalse);
    expect(
      File(p.join(harness.paths.state.path, 'ui.json')).readAsStringSync(),
      contains('"quickShortcut":false'),
    );
    host.free = false;
    session.setQuickShortcut(on: true);
    await pumpEventQueue();
    expect(quick.taken, isTrue);
  });

  test('an app not set up, or locked, comes to the front as itself', () async {
    await quick.pressed();
    expect(host.calls, ['front']);
    expect(session.quickAddOpen, isFalse);
    await session.connect(findProvider('anthropic'), 'k');
    await session.lock.set('2468');
    session.lock.locked = true;
    await quick.pressed();
    expect(host.calls, ['front', 'front']);
  });

  test('pressed opens the small window and again closes it; locking closes it', () async {
    await session.connect(findProvider('anthropic'), 'k');
    await quick.pressed();
    expect(session.quickAddOpen, isTrue);
    expect(host.calls, ['compact']);
    await quick.pressed();
    expect(session.quickAddOpen, isFalse);
    expect(host.calls, ['compact', 'restore']);
    await quick.pressed();
    await session.lock.set('2468');
    session.lock.locked = true;
    session.setQuickShortcut(on: true); // any change: the lock is noticed
    await pumpEventQueue();
    expect(session.quickAddOpen, isFalse);
    expect(host.calls.last, 'restore');
  });

  test('sending gives the window back first, then joins the chat; blank is ignored', () async {
    await session.connect(findProvider('anthropic'), 'k');
    await quick.pressed();
    await quick.send('   ');
    expect(session.quickAddOpen, isTrue);
    await quick.send(' Yarın dişçiyi ara ');
    expect(session.quickAddOpen, isFalse);
    expect(harness.provider.asked, ['Yarın dişçiyi ara']);
  });

  test('the last receipt, as one line', () {
    expect(lastReceipt(session), isNull);
    session.transcript.add((
      role: ChatRole.assistant,
      text: 'Eklendi.',
      cards: const [
        NoteReceipt('saglik', 'topic', 'Sağlık', ['add_reminder']),
      ],
    ));
    expect(
      lastReceipt(session),
      'Last: ${session.strings.noteChange(const NoteReceipt('saglik', 'topic', 'Sağlık', ['add_reminder']))} · Sağlık',
    );
    session.transcript.add((role: ChatRole.assistant, text: 'Merhaba.', cards: const []));
    expect(lastReceipt(session), isNull);
  });

  testWidgets('the quick window: Enter sends, Esc closes, the orb talks (#800)', (tester) async {
    final harness = Harness(answers: ['Kaydedildi.', 'Sesli kaydedildi.']);
    harness.speech.phrases.add('sesle not');
    final session = await pumpApp(tester, harness);
    await session.connect(findProvider('anthropic'), 'k');
    final host = FakeHost();
    final quick = session.quickWindow = QuickWindow(session, host);
    addTearDown(quick.dispose);
    session.transcript.add((
      role: ChatRole.assistant,
      text: 'Eklendi.',
      cards: const [
        NoteReceipt('saglik', 'topic', 'Sağlık', ['add_reminder']),
      ],
    ));
    await quick.pressed();
    await tester.pumpAndSettle();
    expect(find.text('Notelore · Quick note'), findsOneWidget);
    expect(find.text('Ctrl+Alt+N'), findsOneWidget);
    expect(find.textContaining('Last: '), findsOneWidget);
    await tester.enterText(find.byKey(const Key('quick-message')), 'Süt al');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(session.quickAddOpen, isFalse);
    expect(harness.provider.asked, ['Süt al']);
    expect(find.text('Notelore · Quick note'), findsNothing);
    // Esc closes without sending.
    await quick.pressed();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(session.quickAddOpen, isFalse);
    expect(host.calls.last, 'restore');
    // The orb: listening until a second tap, then the window goes.
    await quick.pressed();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tap or hold to talk'));
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop and send'));
    await tester.pumpAndSettle();
    expect(session.quickAddOpen, isFalse);
    expect(harness.provider.asked, ['Süt al', 'sesle not']);
    expect(harness.voice.spoken, isEmpty, reason: 'the answer is read later');
  });

  testWidgets('the quick window fits its 460×260 size, in Turkish too, with a long receipt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(460, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.setLanguage(AppLanguage.tr);
    session.transcript.add((
      role: ChatRole.assistant,
      text: 'Eklendi.',
      cards: const [
        NoteReceipt('x', 'project', 'Annemin 70. yaş günü için sürpriz parti ve davetliler', [
          'add_todo',
        ]),
      ],
    ));
    await tester.pumpWidget(MaterialApp(home: QuickAddScreen(quick)));
    await tester.pumpAndSettle();
    expect(find.text('Notelore · Hızlı not'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings › Advanced turns the shortcut off, and says when it is taken', (
    tester,
  ) async {
    host.free = false;
    await quick.start();
    session.quickWindow = quick;
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(session, section: SettingsSection.advanced)),
    );
    expect(find.text('Quick note shortcut'), findsOneWidget);
    expect(find.textContaining('Ctrl+Alt+N opens a small window'), findsOneWidget);
    expect(find.textContaining('Another app uses this shortcut'), findsOneWidget);
    await tester.tap(find.text('Quick note shortcut'));
    await tester.pumpAndSettle();
    expect(session.quickShortcut, isFalse);
    expect(host.calls.last, 'unlisten');
  });
}
