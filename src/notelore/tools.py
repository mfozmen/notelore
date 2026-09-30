"""The narrow tools the agent may call. Thin wrappers over ``notelore.store``.

Contracts (every result is a JSON string, or ``"ok"``, or ``"Error: ..."``; the
model never sees an exception):

- ``list_notes(kind?)``: ``[{slug, kind, title, updated}]``, newest first.
- ``read_note(slug, kind?)``: the whole note as Markdown text.
- ``create_note(kind, title, tags?, lang?)``: ``{slug, kind, path}``; fails if it exists.
- ``add_note_entry(slug, text, kind?)``: appends a dated entry under Notes.
- ``add_todo(slug, text, due?, kind?)`` / ``complete_todo(slug, number, kind?)``.
- ``record_decision(slug, topic, value, reason?, kind?)``: supersedes the active
  decision for ``topic`` in the same write.
- ``get_decision(slug, topic, kind?)``: the current decision, deterministic.
- ``decision_history(slug, topic?, kind?)``: every decision incl. superseded.
- ``search_notes(query, kind?)``: full-text hits.
- ``find_stale_notes()``: cleanup candidates with 1-based entry numbers.
- ``archive(slug, entries?, kind?)``: moves numbered entries per section, or the
  whole file when ``entries`` is omitted, under ``_archive/``.

``kind`` (``project`` | ``topic``) is only needed when the same slug exists as
both. No tool overwrites a file or deletes anything.
"""

from __future__ import annotations

import datetime
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from notelore.providers.base import Tool
from notelore.store import notes, stale
from notelore.store.index import Index

_KIND = {"type": "string", "enum": list(notes.KINDS)}
_SLUG = {"type": "string", "description": "Note slug as listed by list_notes"}
_DATE = {"type": "string", "description": "YYYY-MM-DD"}


def _schema(required: list[str], **properties: dict[str, Any]) -> dict[str, Any]:
    return {"type": "object", "properties": properties, "required": required}


TOOLS = [
    Tool(
        "list_notes",
        "Projects and topics with title, slug and last update.",
        _schema([], kind=_KIND),
    ),
    Tool("read_note", "The full note as Markdown.", _schema(["slug"], slug=_SLUG, kind=_KIND)),
    Tool(
        "create_note",
        "Create a new project or topic file. Fails if the title already maps to a file.",
        _schema(
            ["kind", "title"],
            kind=_KIND,
            title={"type": "string"},
            tags={"type": "array", "items": {"type": "string"}, "description": "lowercase"},
            lang={
                "type": "string",
                "enum": ["en", "tr"],
                "description": "language of the headings",
            },
        ),
    ),
    Tool(
        "add_note_entry",
        "Append a dated note. Write one clean, self-contained sentence in the user's language.",
        _schema(["slug", "text"], slug=_SLUG, text={"type": "string"}, kind=_KIND),
    ),
    Tool(
        "add_todo",
        "Add an open todo; due is the due date if the user gave one.",
        _schema(["slug", "text"], slug=_SLUG, text={"type": "string"}, due=_DATE, kind=_KIND),
    ),
    Tool(
        "complete_todo",
        "Tick todo number N (1-based, as shown in read_note order).",
        _schema(["slug", "number"], slug=_SLUG, number={"type": "integer"}, kind=_KIND),
    ),
    Tool(
        "record_decision",
        "Record a decision for a short lowercase topic key such as database or hosting. "
        "The previous active decision for that topic is marked superseded.",
        _schema(
            ["slug", "topic", "value"],
            slug=_SLUG,
            topic={"type": "string"},
            value={"type": "string"},
            reason={"type": "string"},
            kind=_KIND,
        ),
    ),
    Tool(
        "get_decision",
        "The current decision for a topic. Always use this instead of reading free text.",
        _schema(["slug", "topic"], slug=_SLUG, topic={"type": "string"}, kind=_KIND),
    ),
    Tool(
        "decision_history",
        "All decisions of a note, including superseded ones, oldest first.",
        _schema(["slug"], slug=_SLUG, topic={"type": "string"}, kind=_KIND),
    ),
    Tool(
        "search_notes",
        "Full-text search over every note; every word must match, in any order.",
        _schema(["query"], query={"type": "string"}, kind=_KIND),
    ),
    Tool("find_stale_notes", "Deterministic cleanup candidates.", _schema([])),
    Tool(
        "archive",
        "Move entries (by section and 1-based number) or the whole note to _archive/. "
        "Only after the user confirmed in the conversation.",
        _schema(
            ["slug"],
            slug=_SLUG,
            entries={
                "type": "object",
                "description": '{"notes": [2, 5], "todo": [1]}; omit to archive the whole file',
                "additionalProperties": {"type": "array", "items": {"type": "integer"}},
            },
            kind=_KIND,
        ),
    ),
]


@dataclass
class Toolbox:
    root: Path
    index: Index
    today: datetime.date | None = None  # tests pin it; the app uses the local date

    @property
    def tools(self) -> list[Tool]:
        return TOOLS

    def call(self, name: str, args: dict[str, Any]) -> str:
        method = getattr(self, f"_{name}", None) if name in {t.name for t in TOOLS} else None
        if method is None:
            return f"Error: unknown tool {name!r}."
        try:
            return _dumps(method(**args))
        except (
            ValueError,
            LookupError,
            TypeError,
            OSError,  # incl. a Windows PermissionError while another app holds the file
        ) as exc:
            return f"Error: {_message(exc)}"

    # ------------------------------------------------------------ helpers

    def _path(self, slug: str, kind: str | None) -> Path:
        kinds = (
            [kind]
            if kind
            else [k for k in notes.KINDS if notes.note_path(self.root, k, slug).exists()]
        )
        if len(kinds) > 1:
            raise LookupError(f"{slug!r} exists as both project and topic; pass kind.")
        if not kinds or not notes.note_path(self.root, kinds[0], slug).exists():
            raise FileNotFoundError(f"no note with slug {slug!r}.")
        return notes.note_path(self.root, kinds[0], slug)

    def _fresh(self) -> Index:
        self.index.rebuild()
        return self.index

    # ------------------------------------------------------------ tools

    def _list_notes(self, kind: str | None = None) -> list[dict[str, Any]]:
        return [vars(n) for n in self._fresh().list_notes(kind)]

    def _read_note(self, slug: str, kind: str | None = None) -> str:
        return self._path(slug, kind).read_text(encoding="utf-8")

    def _create_note(
        self, kind: str, title: str, tags: list[str] | None = None, lang: str = "en"
    ) -> dict[str, str]:
        path = notes.create_note(self.root, kind, title, tags, lang, self.today)
        return {"slug": path.stem, "kind": kind, "path": path.relative_to(self.root).as_posix()}

    def _add_note_entry(self, slug: str, text: str, kind: str | None = None) -> str:
        notes.add_entry(self._path(slug, kind), text, self.today)
        return "ok"

    def _add_todo(
        self, slug: str, text: str, due: str | None = None, kind: str | None = None
    ) -> str:
        due_date = datetime.date.fromisoformat(due) if due else None
        notes.add_todo(self._path(slug, kind), text, due_date, self.today)
        return "ok"

    def _complete_todo(self, slug: str, number: int, kind: str | None = None) -> str:
        notes.complete_todo(self._path(slug, kind), number, self.today)
        return "ok"

    def _record_decision(
        self, slug: str, topic: str, value: str, reason: str | None = None, kind: str | None = None
    ) -> str:
        notes.record_decision(self._path(slug, kind), topic, value, reason, self.today)
        return "ok"

    def _get_decision(self, slug: str, topic: str, kind: str | None = None) -> Any:
        self._path(slug, kind)  # the same "pass kind" message as every other tool
        decision = self._fresh().get_decision(slug, topic, kind)
        if decision is None:
            return f"No active decision for {topic!r} in {slug!r}."
        return _decision(decision)

    def _decision_history(
        self, slug: str, topic: str | None = None, kind: str | None = None
    ) -> list[dict[str, Any]]:
        self._path(slug, kind)
        return [_decision(d) for d in self._fresh().decision_history(slug, topic, kind)]

    def _search_notes(self, query: str, kind: str | None = None) -> list[dict[str, Any]]:
        return [vars(h) for h in self._fresh().search(query, kind)]

    def _find_stale_notes(self) -> list[dict[str, Any]]:
        return [vars(s) for s in stale.find_stale_notes(self.root, self.today)]

    def _archive(
        self, slug: str, entries: dict[str, list[int]] | None = None, kind: str | None = None
    ) -> dict[str, str]:
        path = self._path(slug, kind)
        if entries:
            target = notes.archive_entries(self.root, path, entries, self.today)
        else:
            target = notes.archive_note(self.root, path, self.today)
        return {"archived_to": target.relative_to(self.root).as_posix()}


def _decision(decision: Any) -> dict[str, Any]:
    return {
        "date": decision.date,
        "topic": decision.topic,
        "value": decision.value,
        "reason": decision.reason,
        "superseded": decision.superseded,
    }


def _dumps(result: Any) -> str:
    if isinstance(result, str):
        return result
    return json.dumps(result, ensure_ascii=False, default=str)


def _message(exc: Exception) -> str:
    return exc.args[0] if isinstance(exc, KeyError) and exc.args else str(exc)
