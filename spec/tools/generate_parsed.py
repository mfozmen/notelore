"""Writes spec/fixtures/parsed.json: how the reference parser reads every note fixture.
The Dart port must produce the same structure (#62).

    uv run python spec/tools/generate_parsed.py
"""

from __future__ import annotations

import datetime
import json
from pathlib import Path

from notelore.store.format import Decision, Entry, Raw, Todo, parse

SPEC = Path(__file__).resolve().parents[1]


def value(v: object) -> object:
    if isinstance(v, datetime.date):
        return {"date": v.isoformat()}
    if isinstance(v, list):
        return [value(x) for x in v]
    return v


def entry(e: object) -> dict[str, object]:
    if isinstance(e, Decision):
        return {
            "type": "decision",
            "date": e.date.isoformat(),
            "topic": e.topic,
            "text": e.text,
            "value": e.value,
            "reason": e.reason,
            "superseded": e.superseded.isoformat() if e.superseded else None,
        }
    if isinstance(e, Entry):
        return {"type": "entry", "date": e.date.isoformat(), "text": e.text}
    if isinstance(e, Todo):
        return {"type": "todo", "date": e.date.isoformat(), "text": e.text, "done": e.done}
    assert isinstance(e, Raw)
    return {"type": "raw", "text": e.text}


parsed = {}
for path in sorted((SPEC / "fixtures" / "notes").glob("*.md")):
    note = parse(path.read_bytes().decode("utf-8"))
    parsed[path.name] = {
        "meta": {k: value(v) for k, v in note.meta.items()},
        "heading": note.heading,
        "preamble": note.preamble,
        "sections": [
            {"heading": s.heading, "key": s.key, "entries": [entry(e) for e in s.entries]}
            for s in note.sections
        ],
    }

out = SPEC / "fixtures" / "parsed.json"
out.write_text(
    json.dumps(parsed, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
)
print(f"{len(parsed)} notes -> {out}")
