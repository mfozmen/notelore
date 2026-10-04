/// Every filesystem location Notelore uses. Nothing else may build a path to user data.
///
/// `NOTELORE_HOME` overrides the root for everything (a relative value resolves
/// against the current directory). Without it the app supplies the platform
/// defaults: on the desktop a visible `~/Notelore` for notes and the per-user data
/// folder for derived state; on a phone the app's own storage.
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

  /// Root of the Markdown notes tree (projects/, topics/, _archive/, .notelore/).
  final Directory notes;

  /// Device-local derived state: search index, sync manifest, merge bases.
  final Directory state;
}
