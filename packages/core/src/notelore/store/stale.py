"""Deterministic cleanup candidates. The model only explains and ranks them.

Signals (``docs/note-format.md``): decisions superseded more than
``decision_days`` ago, files not updated for ``file_days``, open todos whose date
is in the past. Entry numbers are 1-based and match :func:`notes.archive_entries`.
"""

from __future__ import annotations

import datetime
from dataclasses import dataclass
from pathlib import Path

from notelore.store.format import Decision, NotANote, Note, Raw, Todo
from notelore.store.notes import KINDS, read_note


@dataclass(frozen=True)
class Stale:
    slug: str
    kind: str
    reason: str  # "superseded decision" | "overdue todo" | "not updated"
    section: str | None  # section key for entry candidates, None for a whole file
    number: int | None  # 1-based entry number, None for a whole file
    date: datetime.date  # the date that made it stale


def find_stale_notes(
    root: Path,
    today: datetime.date | None = None,
    decision_days: int = 90,
    file_days: int = 180,
) -> list[Stale]:
    today = today or datetime.date.today()
    found: list[Stale] = []
    for kind, folder in KINDS.items():
        for file in sorted((root / folder).glob("*.md")):
            try:
                note = read_note(file)
            except NotANote:
                continue  # not a note
            found.extend(_stale_entries(note, file.stem, kind, today, decision_days))
            updated = note.meta.get("updated")
            if isinstance(updated, datetime.date) and (today - updated).days > file_days:
                found.append(Stale(file.stem, kind, "not updated", None, None, updated))
    return found


def _stale_entries(
    note: Note, slug: str, kind: str, today: datetime.date, decision_days: int
) -> list[Stale]:
    found: list[Stale] = []
    for key, reason in (("decisions", "superseded decision"), ("todo", "overdue todo")):
        section = note.section(key)
        if section is None:
            continue
        number = 0
        for entry in section.entries:
            if isinstance(entry, Raw):
                continue
            number += 1
            if isinstance(entry, Decision) and entry.superseded is not None:
                if (today - entry.superseded).days > decision_days:
                    found.append(Stale(slug, kind, reason, key, number, entry.superseded))
            elif isinstance(entry, Todo) and not entry.done and entry.date < today:
                found.append(Stale(slug, kind, reason, key, number, entry.date))
    return found
