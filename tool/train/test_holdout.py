"""Tests for the held-out set (#599). Run by ci.yml:

    python3 tool/train/test_holdout.py
"""

import json
import re
import random
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import holdout
import scenarios

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


with tempfile.TemporaryDirectory() as tmp:
    fresh = Path(tmp) / "holdout.json"
    holdout.main([str(fresh)])  # its own checks: disjoint, one note per case, 15 a kind
    checked_in = scenarios.ROOT / "eval/holdout.json"
    check("eval/holdout.json is what holdout.py writes", fresh.read_text(encoding="utf-8"),
          checked_in.read_text(encoding="utf-8"))

held = json.loads((scenarios.ROOT / "eval/holdout.json").read_text(encoding="utf-8"))


def note_lang(text):
    return "tr" if any(f"## {h}" in text for h in scenarios.HEADINGS["tr"]) else "en"


cross = [c for c in held if c["id"].startswith("cross-")]
check("there are cross-language cases", len(cross) >= holdout.MIN_PER_KIND, True)
for case in cross:
    pattern = next(iter(case["expect"]["notes"]))
    target = next(t for p, t in case["notes"].items() if re.search(pattern, p))
    check(f"{case['id']} is asked in the other language than its note's", note_lang(target) != case["lang"], True)

training = scenarios.cases(random.Random(7))
leak = [dict(held[0], id="leak", message=training[0]["message"])]
try:
    holdout.disjoint(leak, training)
    check("a training message in the held-out set is refused", "accepted", "refused")
except AssertionError as error:
    check("a training message in the held-out set says so", "messages in training" in str(error), True)

titled = dict(held[0], id="leak", notes={"topics/x.md": next(iter(training[0]["notes"].values()))})
try:
    holdout.disjoint([titled], training)
    check("a training note title in the held-out set is refused", "accepted", "refused")
except AssertionError as error:
    check("a training note title in the held-out set says so", "titles in training" in str(error), True)

sys.exit(1 if failures else 0)
