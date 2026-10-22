import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'desktop_test.dart' show desktop;
import 'support.dart';

/// Until [text] shows: real file work (reading, writing, the share sheet's
/// copies) finishes between frames, as long as it takes (#365).
Future<void> settleUntilText(WidgetTester tester, String text) =>
    settleUntil(tester, () => find.textContaining(text).evaluate().isNotEmpty);

Future<void> openNotesMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notes-more')));
  await tester.pumpAndSettle();
}

void main() {
  Future<Harness> notesOpen(WidgetTester tester, {bool mobile = true}) async {
    final harness = Harness()..mobile = mobile;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('a phone shares the open note as a PDF', (tester) async {
    phone(tester);
    final harness = await notesOpen(tester);
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Markdown (can be imported again)'), findsOneWidget);
    expect(find.text('Web page (HTML)'), findsOneWidget);
    await tester.tap(find.text('PDF'));
    await settleUntilText(tester, 'Exported 1 note.');
    expect(harness.share.contents.keys, ['mopsos.pdf']);
    expect(find.text('Exported 1 note.'), findsOneWidget);
    // Called off at the format: nothing is shared.
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pumpAndSettle();
    expect(harness.share.shared, hasLength(1));
  });

  testWidgets('several notes at once: pick them, then the format', (tester) async {
    phone(tester);
    final harness = await notesOpen(tester);
    await openNotesMenu(tester);
    await tester.tap(find.text('Export notes'));
    await tester.pumpAndSettle();
    expect(find.text('Which notes?'), findsOneWidget);
    FilledButton next() => tester.widget<FilledButton>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );
    expect(next().onPressed, isNull); // nothing chosen yet
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Mopsos')));
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Kitaplar')),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Kitaplar')),
    );
    await tester.pump(); // changed its mind
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Kitaplar')),
    );
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (can be imported again)'));
    await settleUntilText(tester, 'Exported 2 notes.');
    expect(harness.share.contents.keys.toSet(), {'mopsos.md', 'kitaplar.md'});
    expect(find.text('Exported 2 notes.'), findsOneWidget);
    // Cancel in the list exports nothing.
    await openNotesMenu(tester);
    await tester.tap(find.text('Export notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.share.shared, hasLength(1));
  });

  testWidgets('a share called off says nothing; a failed export says why', (tester) async {
    phone(tester);
    final harness = await notesOpen(tester);
    harness.share.status = ShareResultStatus.dismissed;
    await tester.tap(find.text('Mopsos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web page (HTML)'));
    // A dismissed share shows nothing to wait for: wait until the share sheet
    // has read the file it was handed (real IO, a handle the teardown needs).
    await settleUntil(tester, () => harness.share.contents.isNotEmpty);
    expect(find.textContaining('Exported'), findsNothing);
    // The note went missing under the open page: the export reports it.
    File(notePath(harness.paths.notes.path, 'project', 'mopsos')).deleteSync();
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web page (HTML)'));
    await settleUntilText(tester, 'The export failed');
    expect(find.textContaining('The export failed'), findsOneWidget);
  });

  testWidgets('import: says what happened to each file', (tester) async {
    phone(tester);
    final harness = await notesOpen(tester);
    final root = harness.paths.notes.path;
    File put(String name, String text) =>
        File(p.join(harness.scratch.path, name))..writeAsStringSync(text);
    final mine = File(notePath(root, 'project', 'mopsos')).readAsStringSync();
    final fresh = createNote(harness.scratch.path, 'topic', 'Filmler', today: today);
    harness.files.picked = [
      XFile(fresh),
      XFile(put('mopsos.md', mine.replaceFirst('# Mopsos', '# Mopsos\nTheirs.')).path),
      XFile(put('same.md', mine).path),
      XFile(put('notes.txt', 'just text').path),
    ];
    await openNotesMenu(tester);
    await tester.tap(find.text('Import notes'));
    await settleUntilText(tester, 'Imported "Filmler".');
    expect(find.text('Imported "Filmler".'), findsOneWidget);
    expect(
      find.text('Imported as "Mopsos (2)": a different note already had the name.'),
      findsOneWidget,
    );
    expect(find.text('"Mopsos" is already here, unchanged.'), findsOneWidget);
    expect(find.text('"notes.txt" is not a Notelore note.'), findsOneWidget);
    // The list shows the new notes.
    expect(find.text('Filmler'), findsOneWidget);
    expect(find.text('Mopsos (2)'), findsOneWidget);
    // Called off: no message.
    harness.files.picked = [];
    ScaffoldMessenger.of(tester.element(find.byType(ListView).first)).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await openNotesMenu(tester);
    await tester.tap(find.text('Import notes'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a desktop saves the open note where the person says', (tester) async {
    desktop(tester, 1600);
    final harness = await notesOpen(tester, mobile: false);
    final at = p.join(harness.scratch.path, 'saved.md');
    harness.files.saveAt = at;
    await tester.tap(find.text('Mopsos')); // opens beside the list
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (can be imported again)'));
    await settleUntil(
      tester,
      () => File(at).existsSync() && File(at).readAsStringSync().contains('# Mopsos'),
    );
    expect(harness.files.suggested, ['mopsos.md']);
    expect(
      File(at).readAsStringSync(),
      File(notePath(harness.paths.notes.path, 'project', 'mopsos')).readAsStringSync(),
    );
    expect(utf8.decode(File(at).readAsBytesSync()), contains('# Mopsos'));
  });
}
