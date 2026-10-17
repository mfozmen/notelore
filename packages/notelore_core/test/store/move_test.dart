import 'dart:io';

import 'package:notelore_core/src/store/move.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory from;
  late Directory to;
  setUp(() {
    root = Directory.systemTemp.createTempSync('notelore_move_');
    from = Directory(p.join(root.path, 'Notelore'));
    to = Directory(p.join(root.path, 'support', 'notes'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(Directory base, String rel, String text) =>
      File(p.joinAll([base.path, ...rel.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
  String read(Directory base, String rel) =>
      File(p.joinAll([base.path, ...rel.split('/')])).readAsStringSync();

  test('every file moves, archive and history included; the old folder goes once empty', () {
    write(from, 'projects/a.md', 'A');
    write(from, 'topics/b.md', 'B');
    write(from, '_archive/2026-10-01/topics/c.md', 'C');
    write(from, '.notelore/history/x/topics/d.md', 'D');
    moveNotes(from, to, stamp: 'T');
    expect(read(to, 'projects/a.md'), 'A');
    expect(read(to, '_archive/2026-10-01/topics/c.md'), 'C');
    expect(read(to, '.notelore/history/x/topics/d.md'), 'D');
    expect(from.existsSync(), isFalse); // one copy only
  });

  test('nothing there, or nothing left: nothing happens', () {
    moveNotes(from, to, stamp: 'T');
    expect(to.existsSync(), isFalse);
  });

  test('a copy already in place is dropped; a different one is kept in history', () {
    write(from, 'projects/same.md', 'same');
    write(to, 'projects/same.md', 'same');
    write(from, 'projects/clash.md', 'old');
    write(to, 'projects/clash.md', 'new');
    moveNotes(from, to, stamp: 'T');
    expect(read(to, 'projects/same.md'), 'same');
    expect(read(to, 'projects/clash.md'), 'new');
    expect(read(to, '.notelore/history/T/moved/projects/clash.md'), 'old'); // never lost
    expect(from.existsSync(), isFalse);
  });

  test('a folder that is not empty after the move stays (something the user put there)', () {
    write(from, 'projects/a.md', 'A');
    Directory(p.join(from.path, 'empty')).createSync(recursive: true);
    final locked = File(p.join(from.path, 'cannot-move.txt'))..writeAsStringSync('x');
    moveNotes(
      from,
      to,
      stamp: 'T',
      move: (source, target) {
        if (source == locked.path) throw FileSystemException('in use', source);
        File(source).renameSync(target);
      },
    );
    expect(read(to, 'projects/a.md'), 'A');
    expect(locked.existsSync(), isTrue); // tried again on the next start
    expect(Directory(p.join(from.path, 'empty')).existsSync(), isFalse);
    expect(from.existsSync(), isTrue);
  });

  test('a file on another disk is copied, then the original removed', () {
    write(from, 'projects/a.md', 'A');
    final target = p.join(root.path, 'a.md');
    moveFile(
      p.join(from.path, 'projects', 'a.md'),
      target,
      rename: (_, _) => throw const FileSystemException('cross-device link'),
    );
    expect(File(target).readAsStringSync(), 'A');
    expect(File(p.join(from.path, 'projects', 'a.md')).existsSync(), isFalse);
  });
}
