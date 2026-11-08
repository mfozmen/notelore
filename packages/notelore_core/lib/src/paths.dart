/// Every filesystem location Notelore uses. Nothing else may build a path to user data.
///
/// `NOTELORE_HOME` overrides the root for everything (a relative value resolves
/// against the current directory). Without it the app supplies the platform
/// defaults: the notes and the derived state in the app's own support folder,
/// which the user never has to see.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class NotelorePaths {
  const NotelorePaths({required this.notes, required this.state});

  factory NotelorePaths.resolve({
    required Map<String, String> environment,
    required Directory currentDirectory,
    required Directory defaultNotes,
    required Directory defaultState,
  }) {
    final home = environment['NOTELORE_HOME'] ?? '';
    if (home.isEmpty) return NotelorePaths(notes: defaultNotes, state: defaultState);
    final root = p.normalize(p.join(currentDirectory.path, home)); // join keeps an absolute home
    return NotelorePaths(
      notes: Directory(p.join(root, 'notes')),
      state: Directory(p.join(root, 'state')),
    );
  }

  /// The same installation's test space (#832): its own notes and state under
  /// `test/`, beside the real ones, so the real notes are never touched.
  factory NotelorePaths.test(NotelorePaths real) {
    final root = real.notes.parent.path;
    return NotelorePaths(
      notes: Directory(p.join(root, 'test', 'notes')),
      state: Directory(p.join(root, 'test')),
    );
  }

  /// The switch between the real notes and the test space; `test` means the
  /// test space is open.
  File get spaceMarker => File(p.join(notes.parent.path, 'space'));

  /// Root of the Markdown notes tree (projects/, topics/, _archive/, .notelore/).
  final Directory notes;

  /// Device-local derived state: search index, sync manifest, merge bases.
  final Directory state;
}
