"""File operations on the notes folder.

Every write is atomic (temp file in the same directory, fsync, ``os.replace``) and
only ever appends entries, marks a decision superseded, or moves content to
``_archive/``. Nothing here rewrites a file from model output or deletes anything.
Entry numbers in this module are 1-based, as a user sees them.
"""

from __future__ import annotations

import dataclasses
import datetime
import os
import re
import tempfile
import time
import unicodedata
from pathlib import Path

from notelore.i18n import SECTION_HEADINGS, section_heading
from notelore.store.format import (
    AnyEntry,
    Decision,
    Entry,
    Note,
    Raw,
    Section,
    Todo,
    parse,
    serialize,
)

KINDS = {"project": "projects", "topic": "topics"}
ARCHIVE = "_archive"
_TURKISH = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosucgiosu")
_RESERVED = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(1, 10))}
_RESERVED |= {f"lpt{i}" for i in range(1, 10)}
_REPLACE_ATTEMPTS = 5
_FORBIDDEN = '<>:"/\\|?*\n\0'


# ---------------------------------------------------------------- paths


def slugify(title: str) -> str:
    """Lowercase ASCII file stem: Turkish letters transliterated, accents stripped."""
    text = re.sub("['\u2019]", "", unicodedata.normalize("NFC", title).translate(_TURKISH))
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", text).strip("-")[:100].rstrip("-")
    if not slug:
        return "untitled"
    return f"{slug}-note" if slug in _RESERVED else slug


def note_path(root: Path, kind: str, slug: str) -> Path:
    if kind not in KINDS:
        raise ValueError(f"unknown note kind {kind!r}; expected one of {sorted(KINDS)}")
    # A slug is a bare file stem: hand-made names like "My Note" are fine, path escapes are not.
    if not slug or slug in (".", "..") or any(ch in slug for ch in _FORBIDDEN):
        raise ValueError(f"invalid slug {slug!r}; use the slug exactly as list_notes shows it")
    return root / KINDS[kind] / f"{slug}.md"


# ---------------------------------------------------------------- I/O


def _umask() -> int:
    current = os.umask(0)  # the only portable way to read it is to set it and set it back
    os.umask(current)
    return current


def atomic_write(path: Path, text: str) -> None:
    """UTF-8, LF, written to a temp file next to ``path`` and moved into place."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        Path(tmp).chmod(0o666 & ~_umask())  # mkstemp gives 0600; honour the user's umask
        for attempt in range(_REPLACE_ATTEMPTS - 1):
            try:
                Path(tmp).replace(path)
                return
            except PermissionError:  # Windows: antivirus or an editor holds the file
                time.sleep(0.05 * 2**attempt)
        Path(tmp).replace(path)  # the last attempt lets the error out
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def read_note(path: Path) -> Note:
    return parse(path.read_text(encoding="utf-8"))


def write_note(path: Path, note: Note, today: datetime.date | None = None) -> None:
    """Persist ``note``; ``updated`` is maintained here, never by the caller."""
    note.meta["updated"] = today or datetime.date.today()
    atomic_write(path, unicodedata.normalize("NFC", serialize(note)))


# ---------------------------------------------------------------- sections and entries


def _lang(note: Note) -> str:
    turkish = {variants["tr"] for variants in SECTION_HEADINGS.values()}
    return "tr" if any(section.heading in turkish for section in note.sections) else "en"


def _is_blank(entry: AnyEntry) -> bool:
    return isinstance(entry, Raw) and not entry.text.strip()


def _section(note: Note, key: str, lang: str | None = None) -> Section:
    """The known section ``key``, created at the end of the file if missing."""
    section = note.section(key)
    if section is None:
        if note.sections:
            previous = note.sections[-1].entries
            if not previous or not _is_blank(previous[-1]):
                previous.append(Raw(""))  # one blank line between sections
        section = Section(section_heading(key, lang or _lang(note)))
        note.sections.append(section)
    return section


def _append(section: Section, entry: AnyEntry) -> None:
    """Insert after the last real entry, before the blank line that ends the section."""
    index = len(section.entries)
    while index and _is_blank(section.entries[index - 1]):
        index -= 1
    section.entries.insert(index, entry)


def _text(text: str) -> str:
    """One clean entry text: NFC, CRLF removed, continuation lines indented by two spaces."""
    text = unicodedata.normalize("NFC", text).replace("\r\n", "\n").strip()
    return "\n  ".join(line.strip() for line in text.splitlines())


def _position(section: Section, number: int) -> int:
    """Index into ``section.entries`` of the ``number``-th real (non-Raw) entry, 1-based."""
    positions = [i for i, entry in enumerate(section.entries) if not isinstance(entry, Raw)]
    if not 1 <= number <= len(positions):
        raise IndexError(f"{section.heading} has {len(positions)} entries, no #{number}")
    return positions[number - 1]


# ---------------------------------------------------------------- operations


def create_note(
    root: Path,
    kind: str,
    title: str,
    tags: list[str] | None = None,
    lang: str = "en",
    today: datetime.date | None = None,
) -> Path:
    path = note_path(root, kind, slugify(title))
    if path.exists():
        raise FileExistsError(path)
    today = today or datetime.date.today()
    meta: dict[str, object] = {"title": title, "kind": kind, "created": today, "updated": today}
    if tags:
        meta["tags"] = tags
    sections = [Section(section_heading(key, lang)) for key in SECTION_HEADINGS]
    for section in sections[:-1]:
        section.entries.append(Raw(""))
    write_note(path, Note(meta, title, preamble=[""], sections=sections), today)
    return path


def add_entry(path: Path, text: str, today: datetime.date | None = None) -> None:
    note, today = read_note(path), today or datetime.date.today()
    _append(_section(note, "notes"), Entry(today, _text(text)))
    write_note(path, note, today)


def add_todo(
    path: Path, text: str, due: datetime.date | None = None, today: datetime.date | None = None
) -> None:
    note, today = read_note(path), today or datetime.date.today()
    _append(_section(note, "todo"), Todo(due or today, _text(text)))
    write_note(path, note, today)


def complete_todo(path: Path, number: int, today: datetime.date | None = None) -> None:
    note = read_note(path)
    section = _section(note, "todo")
    todos = [(i, entry) for i, entry in enumerate(section.entries) if isinstance(entry, Todo)]
    if not 1 <= number <= len(todos):
        raise IndexError(f"{section.heading} has {len(todos)} todos, no #{number}")
    position, todo = todos[number - 1]
    section.entries[position] = dataclasses.replace(todo, done=True)
    write_note(path, note, today)


def record_decision(
    path: Path,
    topic: str,
    value: str,
    reason: str | None = None,
    today: datetime.date | None = None,
) -> None:
    """Append a decision; the active one for the same topic is superseded in the same write."""
    topic = _text(topic).lower()
    if not topic or "*" in topic or "\n" in topic:
        raise ValueError(f"decision topic must be a short one-line key, got {topic!r}")
    note, today = read_note(path), today or datetime.date.today()
    section = _section(note, "decisions")
    for index, entry in enumerate(section.entries):
        if isinstance(entry, Decision) and entry.topic == topic and entry.superseded is None:
            section.entries[index] = dataclasses.replace(entry, superseded=today)
    text = _text(value).rstrip(".") + "." + (f" {_text(reason)}" if reason else "")
    _append(section, Decision(today, topic, text))
    write_note(path, note, today)


def active_decision(note: Note, topic: str) -> Decision | None:
    """The newest non-superseded decision for ``topic``; deterministic, no model involved."""
    section = note.section("decisions")
    topic = _text(topic).lower()
    found = None
    for entry in section.entries if section else []:
        if isinstance(entry, Decision) and entry.topic == topic and entry.superseded is None:
            found = entry
    return found


def _archive_path(root: Path, path: Path, today: datetime.date) -> Path:
    return root / ARCHIVE / today.isoformat() / path.relative_to(root)


def archive_note(root: Path, path: Path, today: datetime.date | None = None) -> Path:
    """Move a whole file under ``_archive/<date>/``, never overwriting an earlier archive."""
    target = _archive_path(root, path, today or datetime.date.today())
    target.parent.mkdir(parents=True, exist_ok=True)
    stem, number = target.stem, 1
    while target.exists():
        number += 1
        target = target.with_name(f"{stem}-{number}.md")
    path.replace(target)
    return target


def archive_entries(
    root: Path, path: Path, selection: dict[str, list[int]], today: datetime.date | None = None
) -> Path:
    """Move numbered entries per section into the archive copy of the same note."""
    note, today = read_note(path), today or datetime.date.today()
    target = _archive_path(root, path, today)
    archive = read_note(target) if target.exists() else Note(dict(note.meta), note.heading, [""])
    for key, numbers in selection.items():
        section = note.section(key)
        if section is None or section.key is None:
            raise ValueError(f"no known section {key!r} in {path.name}")
        if len(set(numbers)) != len(numbers):
            raise ValueError(f"an entry of {key!r} is listed twice: {numbers}")
        positions = [_position(section, number) for number in numbers]
        for position in positions:
            _append(_section(archive, key, _lang(note)), section.entries[position])
        for position in sorted(positions, reverse=True):  # delete from the end: indexes stay valid
            del section.entries[position]
    write_note(target, archive, today)  # archive first: a failure here loses nothing
    write_note(path, note, today)
    return target
