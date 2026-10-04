/// SQLite index derived from the notes folder.
///
/// Derived state only: delete the database at any time and [NoteIndex.rebuild]
/// recreates it from the Markdown files. Full-text search uses FTS5 when the
/// SQLite build has it and falls back to `LIKE` over case-folded text otherwise.
/// Ported from the Python reference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'format.dart';
import 'notes.dart';

const _schema = '''
CREATE TABLE files(
    path TEXT PRIMARY KEY, slug TEXT, kind TEXT, title TEXT, updated TEXT,
    stamp TEXT, hash TEXT);
CREATE TABLE decisions(path TEXT, date TEXT, topic TEXT, text TEXT, superseded TEXT);
CREATE INDEX decisions_by_topic ON decisions(path, topic);
''';
const _ftsTable =
    'CREATE VIRTUAL TABLE content USING fts5('
    'slug, title, section, text, kind UNINDEXED, path UNINDEXED, superseded UNINDEXED);';
const _plainTable =
    'CREATE TABLE content(slug, title, section, text, kind, path, superseded, folded);';
// Bump when the tables change; the FTS flag is part of it because the content
// table has a different shape per backend. A mismatch drops and recreates everything.
const _schemaVersion = 2;

bool fts5Available(Database db) {
  try {
    db.execute('CREATE VIRTUAL TABLE temp.fts5_probe USING fts5(x)');
  } on SqliteException {
    return false;
  }
  db.execute('DROP TABLE temp.fts5_probe');
  return true;
}

final class NoteInfo {
  const NoteInfo(this.slug, this.kind, this.title, this.updated);

  final String slug;
  final String kind;
  final String title;
  final DateTime? updated;

  @override
  bool operator ==(Object other) =>
      other is NoteInfo &&
      other.slug == slug &&
      other.kind == kind &&
      other.title == title &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(slug, kind, title, updated);

  @override
  String toString() => 'NoteInfo($kind/$slug, $title, $updated)';
}

final class Hit {
  const Hit(this.slug, this.kind, this.title, this.section, this.text, {required this.superseded});

  final String slug;
  final String kind;
  final String title;
  final String section;
  final String text;

  /// A crossed-out decision, never to be presented as current.
  final bool superseded;

  @override
  bool operator ==(Object other) =>
      other is Hit &&
      other.slug == slug &&
      other.kind == kind &&
      other.title == title &&
      other.section == section &&
      other.text == text &&
      other.superseded == superseded;

  @override
  int get hashCode => Object.hash(slug, kind, title, section, text, superseded);

  @override
  String toString() => 'Hit($kind/$slug, $section: $text${superseded ? ', superseded' : ''})';
}

class NoteIndex {
  /// Opens (or creates) the index at [dbPath] for the notes under [root]. [fts5]
  /// forces a backend; by default the SQLite build is probed.
  NoteIndex(String dbPath, this.root, {bool? fts5}) {
    Directory(p.dirname(dbPath)).createSync(recursive: true);
    _db = sqlite3.open(dbPath);
    try {
      fts = fts5 ?? fts5Available(_db);
      final version = _schemaVersion * 2 + (fts ? 1 : 0);
      if (_db.userVersion != version) {
        _db
          ..execute(
            'DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS decisions;'
            'DROP TABLE IF EXISTS content;$_schema${fts ? _ftsTable : _plainTable}',
          )
          ..userVersion = version;
      }
    } catch (_) {
      _db.close(); // a corrupt or locked database must not leak the handle
      rethrow;
    }
  }

  final String root;
  late final Database _db;
  late final bool fts;

  void close() => _db.close();

  // ------------------------------------------------------------ building

  /// Brings the index up to date: reparses only files whose stamp and hash changed.
  ///
  /// The stamp is mtime plus size: a rewrite inside the filesystem's mtime
  /// granularity usually changes the size, so it is not missed.
  void rebuild() {
    final known = {
      for (final row in _db.select('SELECT path, stamp, hash FROM files'))
        row.columnAt(0) as String: (row.columnAt(1) as String, row.columnAt(2) as String),
    };
    final seen = <String>{};
    _db.execute('BEGIN');
    for (final MapEntry(key: kind, value: folder) in kinds.entries) {
      for (final file in markdownFiles(p.join(root, folder))) {
        final rel = p.posix.joinAll(p.split(p.relative(file.path, from: root)));
        final String stamp;
        final String text;
        try {
          final stat = file.statSync();
          stamp = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
          if (known[rel]?.$1 == stamp) {
            seen.add(rel);
            continue;
          }
          text = unorm.nfc(utf8.decode(file.readAsBytesSync()));
        } on FileSystemException {
          continue; // gone: one bad file never takes down the index
        } on FormatException {
          continue; // not UTF-8 text
        }
        seen.add(rel);
        final digest = sha256.convert(utf8.encode(text)).toString();
        if (known[rel]?.$2 == digest) {
          _db.execute('UPDATE files SET stamp = ? WHERE path = ?', [stamp, rel]);
          continue;
        }
        _indexFile(rel, kind, p.basenameWithoutExtension(file.path), text, stamp, digest);
      }
    }
    known.keys.where((rel) => !seen.contains(rel)).forEach(_forget);
    _db.execute('COMMIT');
  }

  void _forget(String rel) {
    for (final table in ['files', 'decisions', 'content']) {
      _db.execute('DELETE FROM $table WHERE path = ?', [rel]);
    }
  }

  void _indexFile(String rel, String kind, String slug, String text, String stamp, String digest) {
    _forget(rel);
    final Note note;
    try {
      note = parse(text);
    } on NotANote {
      // A Markdown file that is not a note: remembered (so it is not reparsed on
      // every rebuild) but with no title, which keeps it out of every listing.
      _db.execute("INSERT INTO files VALUES (?, ?, ?, NULL, '', ?, ?)", [
        rel,
        slug,
        kind,
        stamp,
        digest,
      ]);
      return;
    }
    final updated = switch (note.meta['updated']) {
      // NULL when not a date: sorts last
      final DateTime day when day == DateTime.utc(day.year, day.month, day.day) => isoDate(day),
      _ => null,
    };
    _db.execute('INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?)', [
      rel,
      slug,
      kind,
      note.title,
      updated,
      stamp,
      digest,
    ]);
    for (final section in note.sections) {
      for (final entry in section.entries) {
        var superseded = false;
        final String body;
        switch (entry) {
          case Raw(:final text):
            if (text.trim().isEmpty) continue;
            body = text;
          case Decision():
            superseded = entry.superseded != null;
            _db.execute('INSERT INTO decisions VALUES (?, ?, ?, ?, ?)', [
              rel,
              isoDate(entry.date),
              entry.topic,
              entry.text,
              if (entry.superseded case final day?) isoDate(day) else null,
            ]);
            body = '${entry.topic}: ${entry.text}';
          case Entry(:final text) || Todo(:final text):
            body = text;
        }
        final row = [
          slug,
          note.title,
          section.key ?? section.heading,
          body,
          kind,
          rel,
          if (superseded) 1 else 0,
        ];
        if (fts) {
          _db.execute('INSERT INTO content VALUES (?, ?, ?, ?, ?, ?, ?)', row);
        } else {
          _db.execute('INSERT INTO content VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
            ...row,
            _fold('${note.title}\n$body'),
          ]);
        }
      }
    }
  }

  // ------------------------------------------------------------ queries

  List<NoteInfo> listNotes({String? kind}) => [
    for (final row in _db.select(
      'SELECT slug, kind, title, updated FROM files'
      ' WHERE title IS NOT NULL AND (?1 IS NULL OR kind = ?1) ORDER BY updated DESC, slug',
      [kind],
    ))
      NoteInfo(
        row.columnAt(0) as String,
        row.columnAt(1) as String,
        row.columnAt(2) as String,
        _day(row.columnAt(3) as String?),
      ),
  ];

  /// The one file for [slug]; a slug present as both project and topic needs [kind].
  String? _path(String slug, String? kind) {
    final rows = _db.select(
      'SELECT path, kind FROM files WHERE slug = ?1 AND title IS NOT NULL'
      ' AND (?2 IS NULL OR kind = ?2) ORDER BY kind',
      [unorm.nfc(slug), kind],
    );
    if (rows.length > 1) {
      throw StateError(
        "'$slug' exists as ${rows.map((r) => r.columnAt(1)).join(' and ')}; pass kind",
      );
    }
    return rows.isEmpty ? null : rows.single.columnAt(0) as String;
  }

  /// The current decision for [topic] in [slug]: the newest entry not superseded.
  Decision? getDecision(String slug, String topic, {String? kind}) {
    final rows = _db.select(
      'SELECT date, topic, text, superseded FROM decisions'
      ' WHERE path = ? AND topic = ? AND superseded IS NULL'
      ' ORDER BY date DESC, rowid DESC LIMIT 1',
      [_path(slug, kind), _topic(topic)],
    );
    return rows.isEmpty ? null : _decision(rows.single);
  }

  List<Decision> decisionHistory(String slug, {String? topic, String? kind}) => [
    for (final row in _db.select(
      'SELECT date, topic, text, superseded FROM decisions'
      ' WHERE path = ?1 AND (?2 IS NULL OR topic = ?2) ORDER BY date, rowid',
      [_path(slug, kind), if (topic != null) _topic(topic) else null],
    ))
      _decision(row),
  ];

  /// Hits containing every word of [query] in any order.
  List<Hit> search(String query, {String? kind}) {
    final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    const columns = 'SELECT slug, kind, title, section, text, superseded FROM content WHERE ';
    final ResultSet rows;
    if (fts) {
      // Every word as a quoted phrase: user text never hits FTS5 query syntax.
      final match = words.map((w) => '"${w.replaceAll('"', '""')}"').join(' ');
      rows = _db.select('${columns}content MATCH ?1 AND (?2 IS NULL OR kind = ?2) ORDER BY rank', [
        match,
        kind,
      ]);
    } else {
      final clauses = List.filled(words.length, r"folded LIKE ? ESCAPE '\'").join(' AND ');
      rows = _db.select('$columns$clauses AND (? IS NULL OR kind = ?) ORDER BY path, rowid', [
        for (final word in words) '%${_escapeLike(_fold(word))}%',
        kind,
        kind,
      ]);
    }
    return [
      for (final row in rows)
        Hit(
          row.columnAt(0) as String,
          row.columnAt(1) as String,
          row.columnAt(2) as String,
          row.columnAt(3) as String,
          row.columnAt(4) as String,
          superseded: row.columnAt(5) == 1,
        ),
    ];
  }
}

/// The same key the writer stores: NFC, trimmed, lowercase.
String _topic(String topic) => unorm.nfc(topic).trim().toLowerCase();

final _mark = RegExp(r'\p{M}', unicode: true);

/// Case- and accent-insensitive form for LIKE search, like FTS5's unicode61 tokenizer.
String _fold(String text) => unorm.nfkd(text.toLowerCase()).replaceAll(_mark, '');

String _escapeLike(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

DateTime? _day(String? iso) => iso == null ? null : DateTime.parse('${iso}T00:00:00Z');

Decision _decision(Row row) => Decision(
  _day(row.columnAt(0) as String)!,
  row.columnAt(1) as String,
  row.columnAt(2) as String,
  superseded: _day(row.columnAt(3) as String?),
);
