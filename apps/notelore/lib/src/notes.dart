import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';

/// Every project and topic, newest first; a tap opens the note read-only. A
/// long press, or the open note's delete button, moves it to the archive.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {super.key});

  final Session session;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  /// Asks, then archives [note] with an Undo; true when it was deleted.
  Future<bool> _delete(NoteInfo note) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete "${note.title}"?'),
        content: const Text(
          'It moves to the archive; you can bring it back from _archive/ in the notes folder.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    final archived = await widget.session.deleteNote(note);
    setState(() {});
    messenger.showSnackBar(
      SnackBar(
        content: Text('Moved "${note.title}" to the archive.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.session.restoreNote(note, archived);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    return true;
  }

  // Listed on every build: the session rebuilds the screen after a sync, and the
  // index only rereads files that changed.
  @override
  Widget build(BuildContext context) {
    final notes = widget.session.listNotes();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: notes.isEmpty
          ? const Center(child: Text('No notes yet. Tell the assistant something to remember.'))
          : ListView(
              children: [
                for (final note in notes)
                  ListTile(
                    title: Text(note.title),
                    subtitle: Text(
                      '${note.kind} · updated ${note.updated == null ? '?' : isoDate(note.updated!)}',
                    ),
                    onLongPress: () => _delete(note),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (reader) => Scaffold(
                          appBar: AppBar(
                            title: Text(note.title),
                            actions: [
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (await _delete(note) && reader.mounted) {
                                    Navigator.of(reader).pop();
                                  }
                                },
                              ),
                            ],
                          ),
                          body: Markdown(data: widget.session.readNote(note), selectable: true),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
