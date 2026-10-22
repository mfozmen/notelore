import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app.dart' show AppMenu;
import 'note_view.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart';

/// Every project and topic, newest first; a tap opens the note read-only, beside
/// the list on a wide window. The open note's header archives it.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {super.key});

  final Session session;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

enum _NotesAction { import, export, refresh }

class _NotesScreenState extends State<NotesScreen> {
  /// The note open beside the list on a wide window, read once.
  (NoteInfo, String)? _reading;

  /// What the list is narrowed to; empty shows every note.
  final _search = TextEditingController();

  /// The archive open in the content pane, on a wide window.
  var _archive = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
          FilledButton(
            // Deleting, so the error colour, not the brand's.
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.delete),
          ),
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

  /// Asks for a format, exports [notes] and says how it went (#215).
  Future<void> _export(List<NoteInfo> notes) async {
    final s = widget.session.strings;
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(s.exportAs),
        children: [
          for (final format in ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, format),
              child: Text(s.formatName(format)),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String said;
    try {
      if (!await widget.session.exportNotes(notes, format)) return; // called off
      said = s.exported(notes.length);
    } on Exception catch (error) {
      said = s.exportFailed('$error');
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(said)));
  }

  /// Several notes at once: which ones, then the format.
  Future<void> _exportSeveral(List<NoteInfo> notes) async {
    final chosen = await showDialog<List<NoteInfo>>(
      context: context,
      builder: (_) => _ChooseNotes(notes, widget.session.strings),
    );
    if (chosen != null && mounted) await _export(chosen);
  }

  Future<void> _refresh() async => setState(() {});

  Widget _refreshable(Widget child) => RefreshIndicator(onRefresh: _refresh, child: child);

  Widget _listHeader(BuildContext context, List<NoteInfo> notes) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.s, 0),
    child: Align(alignment: Alignment.centerRight, child: _listActions(context, notes)),
  );

  Widget _listActions(BuildContext context, List<NoteInfo> notes) {
    final s = widget.session.strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: s.archive,
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: () => Layout.isWide(context)
              ? setState(() => _archive = true)
              : Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => ArchiveScreen(widget.session))),
        ),
        PopupMenuButton<_NotesAction>(
          key: const Key('notes-more'),
          tooltip: s.moreNoteActions,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) async {
            switch (action) {
              case _NotesAction.import:
                await _import();
              case _NotesAction.export:
                await _exportSeveral(notes);
              case _NotesAction.refresh:
                await _refresh();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: _NotesAction.import, child: Text(s.importNotes)),
            PopupMenuItem(
              value: _NotesAction.export,
              enabled: notes.isNotEmpty,
              child: Text(s.exportNotes),
            ),
            PopupMenuItem(value: _NotesAction.refresh, child: Text(s.refresh)),
          ],
        ),
      ],
    );
  }

  /// Imports the files the person picks and says what happened to each.
  Future<void> _import() async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final reports = await widget.session.importNotes();
    if (reports.isEmpty || !mounted) return; // called off
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final report in reports) Text(_reported(s, report))],
          ),
        ),
      );
    setState(() {});
  }

  static String _reported(Strings s, ImportReport report) => switch (report.imported) {
    null => s.importRefused(report.file),
    Imported(outcome: ImportOutcome.added, :final title) => s.importedAdded(title),
    Imported(outcome: ImportOutcome.renamed, :final title) => s.importedRenamed(title),
    Imported(:final title) => s.importedSame(title),
  };

  // Listed on every build: the session rebuilds the screen after a sync, and the
  // index only rereads files that changed.
  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    if (_archive && Layout.isWide(context)) {
      // Beside the rail, like the notes; Back returns to them.
      return ArchiveScreen(widget.session, back: () => setState(() => _archive = false));
    }
    final notes = widget.session.listNotes();
    // The open note follows the files: archived elsewhere, it closes; else it
    // is read again (one file), so a sync or the assistant shows at once.
    if (_reading case (final open, _)?) {
      final now = notes.where((n) => n.kind == open.kind && n.slug == open.slug).firstOrNull;
      _reading = now == null ? null : (now, widget.session.readNote(now));
    }
    final wide = Layout.isWide(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppMenu.button(context),
        title: Text(s.notes),
        actions: wide ? null : [_listActions(context, notes)],
      ),
      body: Builder(
        builder: (context) {
          final wide = Layout.isWide(context);
          final list = _list(context, notes, wide: wide);
          if (!wide || notes.isEmpty) return list;
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

  Widget _list(BuildContext context, List<NoteInfo> all, {required bool wide}) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    if (all.isEmpty) {
      return Column(
        children: [
          if (wide) _listHeader(context, all),
          Expanded(child: _refreshable(_shown(context, all, wide: wide))),
        ],
      );
    }
    final notes = _search.text.trim().isEmpty ? all : widget.session.findNotes(_search.text, all);
    return Column(
      children: [
        if (wide) _listHeader(context, all),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, 0),
          child: TextField(
            key: const Key('notes-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: s.searchNotes,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: s.clearSearch,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        Expanded(
          child: _refreshable(
            notes.isEmpty
                // Right under the field, where the eye is after typing.
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, 0),
                    children: [
                      Text(
                        s.noNoteMentions(_search.text.trim()),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  )
                : _shown(context, notes, wide: wide),
          ),
        ),
      ],
    );
  }

  /// [notes] as cards, or the first-run hint when there are none at all.
  Widget _shown(BuildContext context, List<NoteInfo> notes, {required bool wide}) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    return notes.isEmpty
        ? CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.l),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 56, color: colors.primary),
                        const SizedBox(height: Gap.m),
                        Text(s.noNotes, textAlign: TextAlign.center),
                        const SizedBox(height: Gap.m),
                        OutlinedButton.icon(
                          onPressed: _import,
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(s.importNotes),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
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
                    s.noteSubtitle(
                      note.kind,
                      note.updated == null
                          ? '?'
                          : s.shortDate(note.updated!, widget.session.clock().toLocal()),
                    ),
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
          // The note's own heading is its title; above it only its actions.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Gap.s, Gap.s, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: s.export,
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _export([note]),
                ),
                IconButton(
                  tooltip: s.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(note),
                ),
              ],
            ),
          ),
          Expanded(
            child: NoteView(
              text,
              folder: p.dirname(notePath(widget.session.paths.notes.path, note.kind, note.slug)),
              strings: widget.session.strings,
              today: widget.session.clock().toLocal(),
            ),
          ),
        ],
      );
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: Gap.m),
            Text(
              s.pickNote,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
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
        // The note's own heading is its title: the bar only holds its actions.
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: widget.session.strings.export,
              icon: const Icon(Icons.ios_share),
              onPressed: () => _export([note]),
            ),
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
            child: NoteView(
              text,
              folder: p.dirname(notePath(widget.session.paths.notes.path, note.kind, note.slug)),
              strings: widget.session.strings,
              today: widget.session.clock().toLocal(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Picks the notes to export together.
class _ChooseNotes extends StatefulWidget {
  const _ChooseNotes(this.notes, this.strings);

  final List<NoteInfo> notes;
  final Strings strings;

  @override
  State<_ChooseNotes> createState() => _ChooseNotesState();
}

class _ChooseNotesState extends State<_ChooseNotes> {
  final _chosen = <NoteInfo>{};

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.chooseNotes),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final note in widget.notes)
              CheckboxListTile(
                title: Text(note.title),
                value: _chosen.contains(note),
                onChanged: (on) => setState(() => on! ? _chosen.add(note) : _chosen.remove(note)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final note in widget.notes)
                    if (_chosen.contains(note)) note,
                ]),
          child: Text(s.next),
        ),
      ],
    );
  }
}

/// What was deleted, newest first; each opens read-only with Restore.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen(this.session, {this.back, super.key});

  final Session session;

  /// In a pane rather than a page of its own: what its Back does.
  final VoidCallback? back;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  /// The archived note open in the pane, on a wide window; read once.
  (ArchivedNote, String)? _reading;

  Future<void> _restore(ArchivedNote archived, VoidCallback close) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final done = await widget.session.restoreArchived(archived);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(done ? s.restored(archived.title) : s.restoreTaken(archived.title))),
      );
    if (done) close();
    if (mounted) setState(() {});
  }

  /// Asks, then deletes [archived] for good; true when it went.
  Future<bool> _deleteForever(ArchivedNote archived) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final title = s.archivedTitle(archived);
    if (!await _confirm(s.deleteForeverTitle(title), s.deleteForeverBody, s.deleteForever)) {
      return false;
    }
    await widget.session.deleteArchived(archived);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.deletedForever(title))));
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _empty(int count) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(s.emptyArchive, s.emptyArchiveBody(count), s.emptyArchive)) return;
    final gone = await widget.session.emptyArchive();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.archiveEmptied(gone))));
    if (mounted) setState(() {});
  }

  /// A destructive step, said plainly, with its button in the error colour.
  Future<bool> _confirm(String title, String body, String action) async {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(Icons.delete_forever_outlined, color: colors.error),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return sure ?? false;
  }

  // Read once: a restore moves the file while the app rebuilds this route.
  void _open(ArchivedNote archived) {
    final text = widget.session.readArchived(archived);
    if (widget.back != null) return setState(() => _reading = (archived, text));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (reader) => _reader(archived, text, () => Navigator.of(reader).pop()),
      ),
    );
  }

  /// [archived], read-only, with Restore and Delete forever in its bar, clear
  /// of the notices they leave. Its heading is its title; the bar names only
  /// archived entries, which the heading alone would not say.
  Widget _reader(ArchivedNote archived, String text, VoidCallback close) {
    final s = widget.session.strings;
    return Scaffold(
      appBar: AppBar(
        leading: widget.back == null ? null : BackButton(onPressed: close),
        title: archived.entries ? Text(s.archivedTitle(archived)) : null,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restore),
            label: Text(s.restore),
            onPressed: () => _restore(archived, close),
          ),
          IconButton(
            tooltip: s.deleteForever,
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () async {
              if (await _deleteForever(archived)) close();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.column),
          child: NoteView(
            text,
            // As it was: its images were linked from where it lived.
            folder: p.dirname(p.join(widget.session.paths.notes.path, archived.original)),
            strings: s,
            today: widget.session.clock().toLocal(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    if (widget.back case final back?) {
      // In a pane, not a route: the system's back steps out of it too.
      void close() => setState(() => _reading = null);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => _reading == null ? back() : close(),
        child: switch (_reading) {
          (final archived, final text) => _reader(archived, text, close),
          null => _list(context, s),
        },
      );
    }
    return _list(context, s);
  }

  Widget _list(BuildContext context, Strings s) {
    final archived = widget.session.listArchived();
    return Scaffold(
      appBar: AppBar(
        leading: widget.back == null ? null : BackButton(onPressed: widget.back),
        title: Text(s.archive),
        actions: [
          if (archived.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('archive-more'),
              tooltip: s.moreNoteActions,
              onSelected: (_) => _empty(archived.length),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'empty', child: Text(s.emptyArchive)),
              ],
            ),
        ],
      ),
      // A readable width on a wide window, like the reader's; in a pane, from
      // the left edge, under its title.
      body: Align(
        alignment: widget.back == null ? Alignment.topCenter : Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.column),
          child: archived.isEmpty
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
                        s.archivedOn(
                          // A folder that is not a date (made by hand) shows as named.
                          switch (DateTime.tryParse(archived[index].archivedOn)) {
                            null => archived[index].archivedOn,
                            final day => s.shortDate(day, widget.session.clock().toLocal()),
                          },
                        ),
                      ),
                      onTap: () => _open(archived[index]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: s.restore,
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restore(archived[index], () {}),
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey('archive-note-more-${archived[index].original}'),
                            tooltip: s.moreNoteActions,
                            onSelected: (_) => _deleteForever(archived[index]),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'delete', child: Text(s.deleteForever)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
