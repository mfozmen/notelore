"""SQLite index derived from the notes folder.

Derived state only: delete the database at any time and :meth:`Index.rebuild`
recreates it from the Markdown files. Full-text search uses FTS5 when the
bundled SQLite has it and falls back to ``LIKE`` over case-folded text otherwise.
"""

from __future__ import annotations

import datetime
import hashlib
import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from notelore.store.format import Decision, Raw, parse
from notelore.store.notes import KINDS

SCHEMA = """
CREATE TABLE files(
    path TEXT PRIMARY KEY, slug TEXT, kind TEXT, title TEXT, updated TEXT,
    mtime_ns INTEGER, hash TEXT);
CREATE TABLE decisions(path TEXT, date TEXT, topic TEXT, text TEXT, superseded TEXT);
CREATE INDEX decisions_by_topic ON decisions(path, topic);
"""
FTS_TABLE = (
    "CREATE VIRTUAL TABLE content USING fts5("
    "slug, title, section, text, kind UNINDEXED, path UNINDEXED, superseded UNINDEXED)"
)
PLAIN_TABLE = "CREATE TABLE content(slug, title, section, text, kind, path, superseded, folded)"
# Bump when the tables change; the FTS flag is part of it because the content
# table has a different shape per backend. A mismatch drops and recreates everything.
SCHEMA_VERSION = 1


def fts5_available(conn: sqlite3.Connection) -> bool:
    try:
        conn.execute("CREATE VIRTUAL TABLE temp.fts5_probe USING fts5(x)")
    except sqlite3.OperationalError:
        return False
    conn.execute("DROP TABLE temp.fts5_probe")
    return True


@dataclass(frozen=True)
class NoteInfo:
    slug: str
    kind: str
    title: str
    updated: datetime.date | None


@dataclass(frozen=True)
class Hit:
    slug: str
    kind: str
    title: str
    section: str
    text: str
    superseded: bool  # a crossed-out decision, never to be presented as current


class Index:
    def __init__(self, db_path: Path, root: Path) -> None:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.root = root
        self.conn = sqlite3.connect(db_path)
        self.fts = fts5_available(self.conn)
        version = SCHEMA_VERSION * 2 + int(self.fts)
        if self.conn.execute("PRAGMA user_version").fetchone()[0] != version:
            self.conn.executescript(
                "DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS decisions;"
                "DROP TABLE IF EXISTS content;" + SCHEMA + (FTS_TABLE if self.fts else PLAIN_TABLE)
            )
            self.conn.execute(f"PRAGMA user_version = {version}")
            self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    # ------------------------------------------------------------ building

    def rebuild(self) -> None:
        """Bring the index up to date: reparse only files whose mtime and hash changed."""
        known = {
            path: (mtime, digest)
            for path, mtime, digest in self.conn.execute("SELECT path, mtime_ns, hash FROM files")
        }
        seen: set[str] = set()
        for kind, folder in KINDS.items():
            for file in sorted((self.root / folder).glob("*.md")):
                rel = file.relative_to(self.root).as_posix()
                try:
                    mtime = file.stat().st_mtime_ns
                    if rel in known and known[rel][0] == mtime:
                        seen.add(rel)
                        continue
                    text = unicodedata.normalize("NFC", file.read_text(encoding="utf-8"))
                except (OSError, UnicodeDecodeError):
                    continue  # gone or not text: one bad file never takes down the index
                seen.add(rel)
                digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
                if rel in known and known[rel][1] == digest:
                    self.conn.execute("UPDATE files SET mtime_ns = ? WHERE path = ?", (mtime, rel))
                    continue
                self._index_file(rel, kind, file.stem, text, mtime, digest)
        for rel in known.keys() - seen:
            self._forget(rel)
        self.conn.commit()

    def _forget(self, rel: str) -> None:
        for table in ("files", "decisions", "content"):
            self.conn.execute(f"DELETE FROM {table} WHERE path = ?", (rel,))

    def _index_file(
        self, rel: str, kind: str, slug: str, text: str, mtime: int, digest: str
    ) -> None:
        self._forget(rel)
        try:
            note = parse(text)
        except ValueError:
            # A Markdown file that is not a note: remembered (so it is not reparsed on
            # every rebuild) but with no title, which keeps it out of every listing.
            self.conn.execute(
                "INSERT INTO files VALUES (?, ?, ?, NULL, '', ?, ?)",
                (rel, slug, kind, mtime, digest),
            )
            return
        updated = _date(str(note.meta.get("updated") or ""))  # NULL when not a date: sorts last
        self.conn.execute(
            "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?)",
            (rel, slug, kind, note.title, updated.isoformat() if updated else None, mtime, digest),
        )
        for section in note.sections:
            for entry in section.entries:
                superseded = False
                if isinstance(entry, Raw):
                    if not entry.text.strip():
                        continue
                    body = entry.text
                elif isinstance(entry, Decision):
                    superseded = entry.superseded is not None
                    self.conn.execute(
                        "INSERT INTO decisions VALUES (?, ?, ?, ?, ?)",
                        (
                            rel,
                            entry.date.isoformat(),
                            entry.topic,
                            entry.text,
                            entry.superseded.isoformat() if entry.superseded else None,
                        ),
                    )
                    body = f"{entry.topic}: {entry.text}"
                else:
                    body = entry.text
                row = (
                    slug,
                    note.title,
                    section.key or section.heading,
                    body,
                    kind,
                    rel,
                    superseded,
                )
                if self.fts:
                    self.conn.execute("INSERT INTO content VALUES (?, ?, ?, ?, ?, ?, ?)", row)
                else:
                    folded = _fold(f"{note.title}\n{body}")
                    self.conn.execute(
                        "INSERT INTO content VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (*row, folded)
                    )

    # ------------------------------------------------------------ queries

    def list_notes(self, kind: str | None = None) -> list[NoteInfo]:
        rows = self.conn.execute(
            "SELECT slug, kind, title, updated FROM files"
            " WHERE title IS NOT NULL AND (? IS NULL OR kind = ?) ORDER BY updated DESC, slug",
            (kind, kind),
        )
        return [
            NoteInfo(slug, kind_, title, datetime.date.fromisoformat(upd) if upd else None)
            for slug, kind_, title, upd in rows
        ]

    def _path(self, slug: str, kind: str | None) -> str | None:
        """The one file for ``slug``; a slug present as both project and topic needs ``kind``."""
        rows = self.conn.execute(
            "SELECT path, kind FROM files WHERE slug = ? AND title IS NOT NULL"
            " AND (? IS NULL OR kind = ?) ORDER BY kind",
            (unicodedata.normalize("NFC", slug), kind, kind),
        ).fetchall()
        if len(rows) > 1:
            kinds = " and ".join(row[1] for row in rows)
            raise LookupError(f"{slug!r} exists as {kinds}; pass kind")
        return str(rows[0][0]) if rows else None

    def get_decision(self, slug: str, topic: str, kind: str | None = None) -> Decision | None:
        """The current decision for ``topic`` in ``slug``: newest entry not superseded."""
        rows = self.conn.execute(
            "SELECT date, topic, text, superseded FROM decisions"
            " WHERE path = ? AND topic = ? AND superseded IS NULL"
            " ORDER BY date DESC, rowid DESC LIMIT 1",
            (self._path(slug, kind), _topic(topic)),
        ).fetchall()
        return _decision(rows[0]) if rows else None

    def decision_history(
        self, slug: str, topic: str | None = None, kind: str | None = None
    ) -> list[Decision]:
        key = _topic(topic) if topic else None
        rows = self.conn.execute(
            "SELECT date, topic, text, superseded FROM decisions"
            " WHERE path = ? AND (? IS NULL OR topic = ?) ORDER BY date, rowid",
            (self._path(slug, kind), key, key),
        )
        return [_decision(row) for row in rows]

    def search(self, query: str, kind: str | None = None) -> list[Hit]:
        """Hits containing every word of ``query`` in any order."""
        words = query.split()
        if not words:
            return []
        columns = "SELECT slug, kind, title, section, text, superseded FROM content WHERE "
        if self.fts:
            # Every word as a quoted phrase: user text never hits FTS5 query syntax.
            match = " ".join('"' + word.replace('"', '""') + '"' for word in words)
            rows = self.conn.execute(
                columns + "content MATCH ? AND (? IS NULL OR kind = ?) ORDER BY rank",
                (match, kind, kind),
            )
        else:
            clauses = " AND ".join("folded LIKE ? ESCAPE '\\'" for _ in words)
            patterns = ["%" + _escape_like(_fold(word)) + "%" for word in words]
            rows = self.conn.execute(
                columns + clauses + " AND (? IS NULL OR kind = ?) ORDER BY path, rowid",
                (*patterns, kind, kind),
            )
        return [
            Hit(slug, kind_, title, section, text, bool(sup))
            for slug, kind_, title, section, text, sup in rows
        ]


def _topic(topic: str) -> str:
    """The same key the writer stores: NFC, trimmed, lowercase."""
    return unicodedata.normalize("NFC", topic).strip().lower()


def _fold(text: str) -> str:
    """Case- and accent-insensitive form for LIKE search, like FTS5's unicode61 tokenizer."""
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def _escape_like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _date(value: str) -> datetime.date | None:
    try:
        return datetime.date.fromisoformat(value)
    except ValueError:
        return None


def _decision(row: tuple[str, str, str, str | None]) -> Decision:
    day, topic, text, superseded = row
    return Decision(
        datetime.date.fromisoformat(day),
        topic,
        text,
        datetime.date.fromisoformat(superseded) if superseded else None,
    )
