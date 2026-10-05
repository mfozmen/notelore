"""Writes spec/fixtures/merge.json: how the reference three-way merge splits edits.

Every device merges with its own implementation, so the Dart port must cut the
same clean parts and conflicts as the Python one for the same three texts (#64).
The cases are a few hand-picked ones plus seeded random edits over a small
alphabet, which exercises difflib's matching-block choices.

    uv run python spec/tools/generate_merge.py
"""

from __future__ import annotations

import json
import random
from pathlib import Path

from notelore.sync.merge import Conflict, three_way

HAND = [
    ("", "same start\nlocal\n", "same start\nremote\n"),
    ("a\nb", "a\nb", "a\nB"),
    ("x\nb\nc\nd\ny\n", "b\nc\nd\nx\ny\n", "x\nb\nc\nd\ny\n"),
    ("a\nb\nc\nd\ne\n", "a\nc\nd\ne\n", "a\nB\nc\nd\ne\n"),
    (
        "a\r\nb\rc\x0bd\x1ce\u2028f\n",
        "a\r\nB\rc\x0bd\x1ce\u2028f\n",
        "a\r\nb\rc\x0bd\x1ce\u2028F\n",
    ),
]


def edit(rng: random.Random, lines: list[str]) -> list[str]:
    out = list(lines)
    for _ in range(rng.randint(0, 3)):
        op = rng.choice(["insert", "delete", "replace"])
        at = rng.randint(0, len(out))
        if op == "insert" or not out or at == len(out):
            out.insert(at, rng.choice("abcdeXYZ") + "\n")
        elif op == "delete":
            del out[at]
        else:
            out[at] = rng.choice("abcdeXYZ") + "\n"
    return out


def generated() -> list[tuple[str, str, str]]:
    rng = random.Random(64)
    cases = []
    for _ in range(300):
        base = [rng.choice("abcde") + "\n" for _ in range(rng.randint(0, 8))]
        cases.append(("".join(base), "".join(edit(rng, base)), "".join(edit(rng, base))))
    return cases


def part(p: list[str] | Conflict) -> object:
    if isinstance(p, Conflict):
        return {"base": p.base, "local": p.local, "remote": p.remote}
    return p


cases = [
    {"base": b, "local": lo, "remote": r, "parts": [part(p) for p in three_way(b, lo, r).parts]}
    for b, lo, r in HAND + generated()
]
out = Path(__file__).resolve().parents[1] / "fixtures" / "merge.json"
out.write_text(
    json.dumps(cases, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
)
print(f"{len(cases)} cases -> {out}")
