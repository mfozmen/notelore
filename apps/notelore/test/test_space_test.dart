import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  testWidgets('a test space keeps notes apart, skips sync and marks feedback (#832)', (
    tester,
  ) async {
    phone(tester);
    final real = Directory.systemTemp.createTempSync('notelore_real_');
    addTearDown(() => real.deleteSync(recursive: true));
    final harness = Harness(auth: FakeAuth()..granted = true, answers: ['Saved.']);
    final switched = <bool>[];
    final session = await pumpApp(tester, harness, testSpace: true, realNotes: real);
    await connect(tester, key: 'k');
    session.switchSpace = (test) async => switched.add(test);
    expect(find.text(session.strings.testSpaceOn), findsOneWidget);

    // A note written here never reaches the real folder.
    final path = createNote(harness.paths.notes.path, 'topic', 'Deneme', today: today);
    session.index.rebuild();
    expect(File(path).existsSync(), isTrue);
    expect(real.listSync(), isEmpty);

    // A sync pass, even with Drive connected, touches nothing.
    session.driveConnected = true;
    harness.remote.failure = const NetworkError('offline');
    await session.syncNow();
    expect(session.syncFailed, isFalse);
    expect(session.lastSynced, isNull);

    // Feedback goes to the real folder, marked as a test.
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final rel = await session.reportWrong('buydu');
    expect(
      File(p.joinAll([real.path, ...rel.split('/')])).readAsStringSync(),
      contains('- Space: test\n'),
    );
    expect(
      Directory(p.join(harness.paths.notes.path, '.notelore', 'feedback')).existsSync(),
      isFalse,
    );

    // The switch leaves the space; clearing moves its notes to its own archive.
    await openSettings(tester, 'Advanced');
    await tester.ensureVisible(find.byKey(const Key('test-space')));
    await tester.tap(find.byKey(const Key('test-space')));
    await tester.pumpAndSettle();
    expect(switched, [false]);
    await tester.ensureVisible(find.byKey(const Key('clear-test-space')));
    await tester.tap(find.byKey(const Key('clear-test-space')));
    await tester.pumpAndSettle();
    expect(session.listNotes().map((n) => n.slug), isNot(contains('deneme')));
    expect(Directory(p.join(harness.paths.notes.path, '_archive')).existsSync(), isTrue);
    expect(find.text(session.strings.testSpaceCleared), findsOneWidget);
  });
}
