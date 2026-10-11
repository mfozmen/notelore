import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';

/// Every project and topic, newest first; a tap opens the note read-only. The
/// entry's trash button (or a long press, or the open note's) archives it.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {super.key});

  final Session session;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  /// Asks, then archives [note] with an Undo; true when it was deleted.
  Future<bool> _delete(NoteInfo note) async {
    final s = widget.session.strings;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.deleteQuestion(note.title)),
        content: Text(s.deleteExplained),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.delete)),
        ],
      ),
    );
    if (sure != true || !mounted) return false;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final archived = await widget.session.deleteNote(note);
    setState(() {});
    if (archived == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.alreadyGone(note.title))));
      return true;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.movedToArchive(note.title)),
        action: SnackBarAction(
          label: s.undo,
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
    final s = widget.session.strings;
    final notes = widget.session.listNotes();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.notes),
        actions: [
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: notes.isEmpty
          ? Center(child: Text(s.noNotes))
          : ListView(
              children: [
                for (final note in notes)
                  ListTile(
                    title: Text(note.title),
                    subtitle: Text(
                      s.noteSubtitle(
                        note.kind,
                        note.updated == null ? '?' : isoDate(note.updated!),
                      ),
                    ),
                    onLongPress: () => _delete(note),
                    trailing: IconButton(
                      tooltip: s.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(note),
                    ),
                    // Read once: the app rebuilds on every session change, and a
                    // deleted note must not be read again under its reader.
                    onTap: () => _open(note, widget.session.readNote(note)),
                  ),
              ],
            ),
    );
  }

  /// The note, read-only, with its own delete button.
  void _open(NoteInfo note, String text) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (reader) => Scaffold(
        appBar: AppBar(
          title: Text(note.title),
          actions: [
            IconButton(
              tooltip: widget.session.strings.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await _delete(note) && reader.mounted) Navigator.of(reader).pop();
              },
            ),
          ],
        ),
        body: Markdown(data: text, selectable: true),
      ),
    ),
  );
}
