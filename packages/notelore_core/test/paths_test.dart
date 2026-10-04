import 'dart:io';

import 'package:notelore_core/src/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final base = Directory.systemTemp.absolute.path;
  final cwd = Directory(p.join(base, 'repo'));
  final notes = Directory(p.join(base, 'home', 'Notelore'));
  final state = Directory(p.join(base, 'data', 'notelore'));

  NotelorePaths resolve(Map<String, String> env) => NotelorePaths.resolve(
    environment: env,
    currentDirectory: cwd,
    defaultNotes: notes,
    defaultState: state,
  );

  test('NOTELORE_HOME overrides everything', () {
    final sandbox = p.join(base, 'sandbox');
    final paths = resolve({'NOTELORE_HOME': sandbox});
    expect(paths.notes.path, p.join(sandbox, 'notes'));
    expect(paths.state.path, p.join(sandbox, 'state'));
  });

  test('a relative NOTELORE_HOME resolves against the current directory', () {
    final paths = resolve({'NOTELORE_HOME': 'sandbox'});
    expect(paths.notes.path, p.join(cwd.path, 'sandbox', 'notes'));
    expect(p.isAbsolute(paths.notes.path), isTrue);
  });

  test('without the override the platform defaults are used', () {
    expect(resolve({}).notes, same(notes));
    expect(resolve({}).state, same(state));
    expect(resolve({'NOTELORE_HOME': ''}).notes, same(notes));
  });
}
