import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';
import 'theme.dart';

/// Every project and topic, newest first; a tap opens the note read-only, beside
/// the list on a wide window. The entry's trash button (or a long press, or the
/// open note's) archives it.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {super.key});

  final Session session;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  /// The note open beside the list on a wide window, read once.
  (NoteInfo, String)? _reading;

  bool _isOpen(NoteInfo note) => _reading?.$1.kind == note.kind && _reading?.$1.slug == note.slug;

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
    setState(() {
      if (_isOpen(note)) _reading = null;
    });
    if (archived == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.alreadyGone(note.title))));
      return true;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.movedToArchive(note.title)),
        // Flutter keeps a snackbar with an action until dismissed: this one goes.
        persist: false,
        duration: const Duration(seconds: 6),
        showCloseIcon: true,
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
    // The open note follows the files: archived elsewhere, it closes; else it
    // is read again (one file), so a sync or the assistant shows at once.
    if (_reading case (final open, _)?) {
      final now = notes.where((n) => n.kind == open.kind && n.slug == open.slug).firstOrNull;
      _reading = now == null ? null : (now, widget.session.readNote(now));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.notes),
        actions: [
          IconButton(
            tooltip: s.archive,
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => ArchiveScreen(widget.session))),
          ),
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final wide = Layout.isWide(context);
          final list = _list(context, notes, wide: wide);
          if (!wide) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 400, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: _reader(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<NoteInfo> notes, {required bool wide}) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    return notes.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(Gap.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 56, color: colors.primary),
                  const SizedBox(height: Gap.m),
                  Text(s.noNotes, textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.s),
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  // The kind at a glance: a folder for a project, a tag for a topic.
                  leading: CircleAvatar(
                    backgroundColor: colors.secondaryContainer,
                    foregroundColor: colors.onSecondaryContainer,
                    child: Icon(
                      note.kind == 'project' ? Icons.folder_outlined : Icons.sell_outlined,
                      size: 20,
                    ),
                  ),
                  title: Text(note.title),
                  subtitle: Text(
                    s.noteSubtitle(note.kind, note.updated == null ? '?' : isoDate(note.updated!)),
                  ),
                  onLongPress: () => _delete(note),
                  trailing: IconButton(
                    tooltip: s.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(note),
                  ),
                  selected: wide && _isOpen(note),
                  // Read once: the app rebuilds on every session change, and a
                  // deleted note must not be read again under its reader.
                  onTap: () {
                    final text = widget.session.readNote(note);
                    if (wide) {
                      setState(() => _reading = (note, text));
                    } else {
                      _open(note, text);
                    }
                  },
                ),
              );
            },
          );
  }

  /// The open note beside the list, or where it will be.
  Widget _reader(BuildContext context) {
    final s = widget.session.strings;
    final Widget content;
    if (_reading case (final note, final text)?) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The note's own heading is its title; above it only its action.
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, Gap.s, Gap.s, 0),
              child: IconButton(
                tooltip: s.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(note),
              ),
            ),
          ),
          Expanded(
            child: Markdown(data: text, selectable: true, padding: const EdgeInsets.all(Gap.m)),
          ),
        ],
      );
    } else {
      content = Center(child: Text(s.pickNote));
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.column),
        child: content,
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
        // A comfortable reading width on wide windows.
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.column),
            child: Markdown(data: text, selectable: true, padding: const EdgeInsets.all(Gap.m)),
          ),
        ),
      ),
    ),
  );
}

/// What was deleted, newest first; each opens read-only with Restore.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen(this.session, {super.key});

  final Session session;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  Future<void> _restore(BuildContext reader, ArchivedNote archived) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final done = await widget.session.restoreArchived(archived);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(done ? s.restored(archived.title) : s.restoreTaken(archived.title))),
      );
    if (done && reader.mounted) Navigator.of(reader).pop();
    if (mounted) setState(() {});
  }

  // Read once: a restore moves the file while the app rebuilds this route.
  void _open(ArchivedNote archived) => _show(archived, widget.session.readArchived(archived));

  void _show(ArchivedNote archived, String text) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (reader) => Scaffold(
        appBar: AppBar(title: Text(widget.session.strings.archivedTitle(archived))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.column),
            child: Markdown(data: text, selectable: true, padding: const EdgeInsets.all(Gap.m)),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.restore),
          label: Text(widget.session.strings.restore),
          onPressed: () => _restore(reader, archived),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final archived = widget.session.listArchived();
    return Scaffold(
      appBar: AppBar(title: Text(s.archive)),
      body: archived.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.l),
                child: Text(s.archiveEmpty, textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
              itemCount: archived.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.s),
              itemBuilder: (context, index) => Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(s.archivedTitle(archived[index])),
                  subtitle: Text(
                    '${s.archivedOn(archived[index].archivedOn)} · ${archived[index].original}',
                  ),
                  onTap: () => _open(archived[index]),
                ),
              ),
            ),
    );
  }
}
