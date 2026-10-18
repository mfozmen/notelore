import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'session.dart' show withoutFrontMatter;
import 'strings.dart';
import 'theme.dart';
import 'web_link.dart';

/// A note as a page (#426): its title and what it is, then each known section
/// in its own form: decisions as cards, todos as checkboxes, notes as a dated
/// timeline. The file stays plain Markdown; only the reading changes. A file
/// the parser cannot read shows as Markdown. Images resolve against [folder],
/// the note's own; [today] marks late todos.
class NoteView extends StatelessWidget {
  const NoteView(
    this.source, {
    required this.folder,
    required this.strings,
    required this.today,
    super.key,
  });

  final String source;
  final String folder;
  final Strings strings;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final Note note;
    try {
      note = parse(source);
    } on NotANote {
      return Markdown(
        data: withoutFrontMatter(source),
        selectable: true,
        padding: const EdgeInsets.all(Gap.m),
        onTapLink: (_, href, _) => openWebLink(href),
        imageBuilder: _image,
      );
    }
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.l),
        children: [
          ..._header(context, note),
          if (note.preamble.join('\n').trim() case final intro when intro.isNotEmpty) ...[
            const SizedBox(height: Gap.m),
            _markdown(intro),
          ],
          for (final section in note.sections) ...[
            const SizedBox(height: Gap.l),
            _Heading(section.heading),
            const SizedBox(height: Gap.s),
            ..._section(context, section),
          ],
        ],
      ),
    );
  }

  Widget _image(Uri uri, String? title, String? alt) => _NoteImage(uri, alt ?? '', folder, strings);

  String _date(DateTime date) => strings.shortDate(date, today);

  /// Inline Markdown: bold, links and images work in every line.
  Widget _markdown(String text, {TextStyle? style}) => MarkdownBody(
    data: text,
    onTapLink: (_, href, _) => openWebLink(href),
    imageBuilder: _image,
    styleSheet: style == null ? null : MarkdownStyleSheet(p: style),
  );

  List<Widget> _header(BuildContext context, Note note) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final tags = [for (final tag in (note.meta['tags'] as List?) ?? const []) '#$tag'];
    // The front matter reader hands a date back as one; anything else is not shown.
    final updated = note.meta['updated'] is DateTime ? note.meta['updated']! as DateTime : null;
    return [
      Text(note.title, style: theme.textTheme.headlineSmall),
      const SizedBox(height: Gap.s),
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(Gap.s),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs / 2),
              child: Text(
                strings.noteKind('${note.meta['kind']}'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          if (tags.isNotEmpty) Text(tags.join('  '), style: muted),
          if (updated != null) Text(strings.updatedOn(_date(updated)), style: muted),
        ],
      ),
    ];
  }

  List<Widget> _section(BuildContext context, Section section) {
    final raw = [
      for (final entry in section.entries)
        if (entry is Raw && entry.text.trim().isNotEmpty) entry.text,
    ];
    return [
      ...switch (section.key) {
        'decisions' => _decisions(context, section.entries.whereType<Decision>().toList()),
        'todo' => _todos(context, section.entries.whereType<Todo>().toList()),
        'notes' => _notes(context, section.entries.whereType<Entry>().toList()),
        // A section someone wrote by hand: as written.
        _ => [_markdown(section.entries.map((e) => e.render()).join('\n'))],
      },
      if (section.key != null && raw.isNotEmpty) _markdown(raw.join('\n')),
    ];
  }

  List<Widget> _decisions(BuildContext context, List<Decision> decisions) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final earlier = decisions.where((d) => d.superseded != null).toList();
    return [
      for (final decision in decisions.where((d) => d.superseded == null))
        Card.filled(
          margin: const EdgeInsets.only(bottom: Gap.s),
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(Gap.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        decision.topic,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(_date(decision.date), style: muted),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Text(decision.value, style: theme.textTheme.titleMedium),
                if (decision.reason case final reason?) ...[
                  const SizedBox(height: Gap.xs),
                  _markdown(
                    reason,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (earlier.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: Gap.s),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(strings.earlierDecisions(earlier.length), style: theme.textTheme.bodyMedium),
          children: [
            for (final decision in earlier)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Text(
                  '${decision.topic}: ${decision.value}  ·  ${_date(decision.date)}, '
                  '${strings.supersededOn(_date(decision.superseded!))}',
                  style: muted?.copyWith(decoration: TextDecoration.lineThrough),
                ),
              ),
          ],
        ),
    ];
  }

  List<Widget> _todos(BuildContext context, List<Todo> todos) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final open = todos.where((t) => !t.done).toList()..sort((a, b) => a.date.compareTo(b.date));
    final done = todos.where((t) => t.done);
    final day = DateTime(today.year, today.month, today.day);
    return [
      for (final todo in [...open, ...done])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                todo.done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: todo.done ? colors.outline : colors.primary,
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: _markdown(
                  todo.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: todo.done ? colors.onSurfaceVariant : null,
                    decoration: todo.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: Gap.s),
              _todoDate(theme, todo, late: !todo.done && todo.date.isBefore(day)),
            ],
          ),
        ),
    ];
  }

  /// A late one in the error colour, and said so to a screen reader.
  Widget _todoDate(ThemeData theme, Todo todo, {required bool late}) => Text(
    _date(todo.date),
    semanticsLabel: late ? strings.overdue(_date(todo.date)) : null,
    style: theme.textTheme.bodySmall?.copyWith(
      color: late ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
    ),
  );

  /// Newest first, a day's entries under one date, on a rail.
  List<Widget> _notes(BuildContext context, List<Entry> entries) {
    final theme = Theme.of(context);
    final days = <DateTime, List<Entry>>{};
    for (final entry in entries.reversed) {
      days.putIfAbsent(entry.date, () => []).add(entry);
    }
    return [
      for (final MapEntry(key: date, value: texts) in days.entries)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  _date(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              VerticalDivider(width: Gap.m, thickness: 2, color: theme.colorScheme.outlineVariant),
              const SizedBox(width: Gap.s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in texts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xs),
                          // Continuation lines are indented in the file.
                          child: _markdown(entry.text.replaceAll('\n  ', '\n')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// A section's own heading, as the note names it.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// An image in a note. One on the device shows; a remote one waits for a tap:
/// a planted image's address could carry the note away (#311, #339).
class _NoteImage extends StatefulWidget {
  const _NoteImage(this.uri, this.alt, this.folder, this.s);

  final Uri uri;
  final String alt;
  final String folder;
  final Strings s;

  @override
  State<_NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<_NoteImage> {
  var _shown = false;

  @override
  Widget build(BuildContext context) {
    final uri = widget.uri;
    final s = widget.s;
    Widget failed(BuildContext context, _, _) =>
        _card(context, const Icon(Icons.broken_image_outlined), s.imageFailed);
    if (!uri.hasScheme) {
      final path = p.normalize(p.join(widget.folder, Uri.decodeComponent(uri.path)));
      // Only inside the notes folder (the note's folder's parent): a note never probes the disk.
      if (!p.isWithin(p.dirname(widget.folder), path)) return failed(context, null, null);
      return Image.file(File(path), semanticLabel: widget.alt, errorBuilder: failed);
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return Text(widget.alt);
    if (_shown) {
      return Image.network(
        '$uri',
        semanticLabel: widget.alt,
        errorBuilder: failed,
        // The same box while it comes, so the tap never seems to do nothing.
        loadingBuilder: (context, image, progress) => progress == null
            ? image
            : _card(
                context,
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                '',
              ),
      );
    }
    return _card(
      context,
      Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.primary),
      s.tapToShow,
      onTap: () => setState(() => _shown = true),
    );
  }

  /// The box an image stands in: its words, where it comes from, and [state].
  Widget _card(BuildContext context, Widget leading, String state, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final host = widget.uri.host;
    final line = [if (host.isNotEmpty) host, if (state.isNotEmpty) state].join(' · ');
    return Semantics(
      button: onTap != null,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: Gap.s),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.alt.isNotEmpty) Text(widget.alt),
                        Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
