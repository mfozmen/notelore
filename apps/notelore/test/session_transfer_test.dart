import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/transfer.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export: a note or several, in the chosen format, to the share sheet', () async {
    final harness = Harness();
    final session = harness.session();
    final root = harness.paths.notes.path;
    createNote(root, 'project', 'Mopsos', today: today);
    createNote(root, 'topic', 'Kitaplar', today: today);
    final notes = session.listNotes();
    final mopsos = notes.firstWhere((n) => n.title == 'Mopsos');
    expect(await session.exportNotes([mopsos], ExportFormat.markdown), isTrue);
    expect(harness.share.shared.last.subject, 'Mopsos');
    expect(
      utf8.decode(harness.share.contents['mopsos.md']!),
      File(notePath(root, 'project', 'mopsos')).readAsStringSync(),
    );
    expect(await session.exportNotes(notes, ExportFormat.pdf), isTrue);
    expect(harness.share.shared.last.subject, 'Notelore');
    expect(latin1.decode(harness.share.contents['notelore-notes.pdf']!), startsWith('%PDF'));
    harness.share.status = ShareResultStatus.dismissed;
    expect(await session.exportNotes([mopsos], ExportFormat.html), isFalse);
  });

  test('import: new notes come in, taken names get a number, nothing is overwritten', () async {
    final harness = Harness();
    final session = harness.session(reminders: false); // one change for the import alone
    final root = harness.paths.notes.path;
    final mine = createNote(root, 'project', 'Mopsos', today: today);
    final mineText = File(mine).readAsStringSync();
    expect(session.listNotes(), hasLength(1)); // warm the index before importing
    var changes = 0;
    session.addListener(() => changes++);

    File picked(String name, List<int> bytes) =>
        File(p.join(harness.scratch.path, name))..writeAsBytesSync(bytes);
    final sent = createNote(harness.scratch.path, 'topic', 'Kitaplar', today: today);
    final theirs = mineText.replaceFirst('# Mopsos', '# Mopsos\nTheir own words.');
    harness.files.picked = [
      XFile(sent),
      XFile(picked('theirs.md', utf8.encode(theirs)).path),
      XFile(picked('photo.md', [0xff, 0xd8, 0xff]).path), // not text at all
      XFile(picked('plain.md', utf8.encode('just a thought')).path),
    ];
    final reports = await session.importNotes();
    expect([for (final r in reports) r.file], ['kitaplar.md', 'theirs.md', 'photo.md', 'plain.md']);
    expect(
      [for (final r in reports) r.imported?.outcome],
      [ImportOutcome.added, ImportOutcome.renamed, null, null],
    );
    expect(reports[1].imported!.title, 'Mopsos (2)');
    expect(File(mine).readAsStringSync(), mineText); // untouched
    expect(session.listNotes().map((n) => n.title), containsAll(['Kitaplar', 'Mopsos (2)']));
    expect(changes, 1); // the notes list hears about it

    // The same again: already there, nothing to tell the screens.
    harness.files.picked = [XFile(sent)];
    final again = await session.importNotes();
    expect(again.single.imported!.outcome, ImportOutcome.alreadyThere);
    expect(changes, 1);
    // Called off: nothing.
    harness.files.picked = [];
    expect(await session.importNotes(), isEmpty);
  });

  test('a session on a phone shares; on a desktop it saves', () async {
    final harness = Harness();
    expect(harness.session().exchange.mobile, isTrue);
    final real = Session(harness.paths);
    addTearDown(real.dispose);
    expect(real.exchange.mobile, Platform.isAndroid || Platform.isIOS);
  });
}
