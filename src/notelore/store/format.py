"""Parse and serialize the note format from ``docs/note-format.md``.

Pure functions, no I/O. ``serialize(parse(text))`` returns ``text`` byte for byte for
every canonical file; CRLF input is normalized to LF and NFD to NFC on parse. Nothing
is dropped: lines that do not match an entry pattern survive as :class:`Raw`, and
blank lines are ``Raw("")`` entries of the section they sit in.
"""

from __future__ import annotations

import datetime
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Any

import yaml

from notelore.i18n import section_key

_DATE = r"\d{4}-\d{2}-\d{2}"
_DECISION = re.compile(
    rf"^- (?P<strike>~~)?(?P<date>{_DATE}) — \*\*(?P<topic>[^*\n]+)\*\*: (?P<text>.*?)"
    rf"(?(strike)~~ _\(superseded (?P<superseded>{_DATE})\)_)$",
    re.DOTALL,
)
_ENTRY = re.compile(rf"^- (?P<date>{_DATE}): (?P<text>.*)$", re.DOTALL)
_TODO = re.compile(rf"^- \[(?P<done>[ x])\] (?P<date>{_DATE}): (?P<text>.*)$", re.DOTALL)


@dataclass(frozen=True)
class Decision:
    date: datetime.date
    topic: str
    text: str  # "<value>. <optional reason>", verbatim
    superseded: datetime.date | None = None

    @property
    def value(self) -> str:
        return self.text.split(". ", 1)[0].rstrip(".")

    @property
    def reason(self) -> str | None:
        parts = self.text.split(". ", 1)
        return parts[1] if len(parts) == 2 else None

    def render(self) -> str:
        line = f"- {'~~' if self.superseded else ''}{self.date} — **{self.topic}**: {self.text}"
        return f"{line}~~ _(superseded {self.superseded})_" if self.superseded else line


@dataclass(frozen=True)
class Entry:
    date: datetime.date
    text: str  # continuation lines keep their "\n  " indentation

    def render(self) -> str:
        return f"- {self.date}: {self.text}"


@dataclass(frozen=True)
class Todo:
    date: datetime.date
    text: str
    done: bool = False

    def render(self) -> str:
        return f"- [{'x' if self.done else ' '}] {self.date}: {self.text}"


@dataclass(frozen=True)
class Raw:
    """A line (or bullet block) that is not a recognized entry. Preserved verbatim."""

    text: str

    def render(self) -> str:
        return self.text


AnyEntry = Decision | Entry | Todo | Raw


@dataclass
class Section:
    heading: str  # verbatim, e.g. "Kararlar"
    entries: list[AnyEntry] = field(default_factory=list)

    @property
    def key(self) -> str | None:
        return section_key(self.heading)


@dataclass
class Note:
    meta: dict[str, Any]  # front matter, insertion order preserved
    heading: str  # the "# ..." line, verbatim
    preamble: list[str] = field(default_factory=list)  # lines between title and first section
    sections: list[Section] = field(default_factory=list)

    @property
    def title(self) -> str:
        return str(self.meta["title"])

    def section(self, key_or_heading: str) -> Section | None:
        for section in self.sections:
            if key_or_heading in (section.key, section.heading):
                return section
        return None


def parse(text: str) -> Note:
    text = unicodedata.normalize("NFC", text.replace("\r\n", "\n"))
    if not text.startswith("---\n"):
        raise ValueError("missing YAML front matter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise ValueError("unterminated YAML front matter")
    try:
        meta = yaml.safe_load(text[4 : end + 1])
    except yaml.YAMLError as exc:
        raise ValueError(f"invalid YAML front matter: {exc}") from exc
    if not isinstance(meta, dict) or "title" not in meta:
        raise ValueError("front matter must be a mapping with a title")
    body = text[end + 5 :].removesuffix("\n")
    lines = body.split("\n") if body else []
    if not lines or not lines[0].startswith("# "):
        raise ValueError("missing '# <title>' line after the front matter")

    note = Note(meta=meta, heading=lines[0][2:])
    current: list[str] = note.preamble
    blocks: list[tuple[Section, list[str]]] = []
    for line in lines[1:]:
        if line.startswith("## "):
            section = Section(line[3:])
            note.sections.append(section)
            current = []
            blocks.append((section, current))
        else:
            current.append(line)
    for section, section_lines in blocks:
        section.entries = _parse_entries(section.key, section_lines)
    return note


def _parse_entries(key: str | None, lines: list[str]) -> list[AnyEntry]:
    if key is None:
        return [Raw(line) for line in lines]
    entries: list[AnyEntry] = []
    block: list[str] = []

    def flush() -> None:
        if block:
            entries.append(_parse_block(key, "\n".join(block)))
            block.clear()

    for line in lines:
        if line.startswith("- "):
            flush()
            block.append(line)
        elif block and line.startswith((" ", "\t")):
            block.append(line)
        else:
            flush()
            entries.append(Raw(line))
    flush()
    return entries


def _parse_block(key: str, block: str) -> AnyEntry:
    try:
        if key == "decisions" and (m := _DECISION.match(block)):
            superseded = m["superseded"]
            return Decision(
                datetime.date.fromisoformat(m["date"]),
                m["topic"],
                m["text"],
                datetime.date.fromisoformat(superseded) if superseded else None,
            )
        if key == "notes" and (m := _ENTRY.match(block)):
            return Entry(datetime.date.fromisoformat(m["date"]), m["text"])
        if key == "todo" and (m := _TODO.match(block)):
            return Todo(datetime.date.fromisoformat(m["date"]), m["text"], done=m["done"] == "x")
    except ValueError:  # a date like 2026-13-45: keep the line, do not guess
        pass
    return Raw(block)


def serialize(note: Note) -> str:
    # One key per dump: scalars in block style, lists in flow style (tags: [a, b]).
    front = "".join(
        yaml.safe_dump(
            {key: value},
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=None if isinstance(value, list) else False,
            width=10**6,
        )
        for key, value in note.meta.items()
    )
    out = ["---\n", front, "---\n", f"# {note.heading}\n"]
    out.extend(f"{line}\n" for line in note.preamble)
    for section in note.sections:
        out.append(f"## {section.heading}\n")
        out.extend(f"{entry.render()}\n" for entry in section.entries)
    return "".join(out)
