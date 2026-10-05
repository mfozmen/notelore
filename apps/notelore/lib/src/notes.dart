import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';

/// Every project and topic, newest first; a tap opens the note read-only.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {super.key});

  final Session session;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late List<NoteInfo> _notes = widget.session.listNotes();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notes'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() => _notes = widget.session.listNotes()),
        ),
      ],
    ),
    body: _notes.isEmpty
        ? const Center(child: Text('No notes yet. Tell the assistant something to remember.'))
        : ListView(
            children: [
              for (final note in _notes)
                ListTile(
                  title: Text(note.title),
                  subtitle: Text(
                    '${note.kind} · updated ${note.updated == null ? '?' : isoDate(note.updated!)}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(note.title)),
                        body: Markdown(data: widget.session.readNote(note), selectable: true),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}
