"""Writes spec/fixtures/front-matter.json: how PyYAML (the reference) writes and reads
front-matter values. The Dart port must produce the same bytes for every case (#62).

    uv run python spec/tools/generate_front_matter.py
"""

from __future__ import annotations

import datetime
import json
from pathlib import Path

import yaml

STRINGS = [
    "Mopsos",
    "Şirket Kuruluşu",
    "İstanbul'a Taşınma",
    "",
    " lead",
    "trail ",
    "two  spaces",
    "yes",
    "No",
    "on",
    "OFF",
    "y",
    "true",
    "False",
    "null",
    "Null",
    "~",
    "123",
    "-5",
    "+7",
    "1.5",
    "1e3",
    ".inf",
    "0x1F",
    "0o17",
    "1_000",
    "12:30",
    "2026-09-12",
    "2026-9-1",
    "2026-09-12T10:00:00",
    "a: b",
    "a:b",
    "ends:",
    "has # hash",
    "a#b",
    "#start",
    "- dash",
    "-dash",
    "?q",
    "? q",
    ":colon",
    ": colon",
    "[x]",
    "{x}",
    "x, y",
    "a [b]",
    "a {b}",
    "it's",
    '"quoted"',
    'say "hi"',
    "@at",
    "`tick",
    "%pct",
    "&amp",
    "*star",
    "!bang",
    "|pipe",
    ">gt",
    "=eq",
    "100%",
    "C:\\path\\x",
    "emoji \U0001f642",
    "tab\there",
    "caf\u00e9 r\u00e9sum\u00e9",
    "bell\x07",
    "esc\x1b",
    "vt\x0b",
    "nul\x00x",
    "del\x7f",
    "c1\x80",
    "nbsp\u00a0x",
    "bom\ufeffx",
    "back\\slash\ttab",
    'quote"\ttab',
]
LISTS = [
    ["investing", "side-project"],
    [],
    ["a, b", "yes", "x y"],
    ["[x]"],
    ["şirket", "hukuk"],
    ["2026-01-01"],
    ["1", "2"],
    ["it's"],
    ["#tag"],
    ["a: b"],
]
OTHER = [5, -3, 0, True, False, None, datetime.date(2026, 9, 12)]


def dump(value: object) -> str:
    return yaml.safe_dump(
        {"k": value},
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=None if isinstance(value, list) else False,
        width=10**6,
    )


def encode(value: object) -> object:
    if isinstance(value, datetime.date):
        return {"date": value.isoformat()}
    if isinstance(value, list):
        return [encode(v) for v in value]
    return value


cases = []
for value in [*STRINGS, *LISTS, *OTHER]:
    line = dump(value)
    loaded = yaml.safe_load(line)["k"]
    cases.append({"value": encode(value), "yaml": line, "loads_as": encode(loaded)})

out = Path(__file__).resolve().parents[1] / "fixtures" / "front-matter.json"
out.write_text(
    json.dumps(cases, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
)
print(f"{len(cases)} cases -> {out}")
