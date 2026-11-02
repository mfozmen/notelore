"""Tests for the training scenarios. Run by ci.yml:

    python3 tool/train/test_scenarios.py
"""

import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scenarios

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


check("a gift list is a gift list in either language", scenarios.themes("topics/gift-ideas.md"), {"gifts"})
check("a reading list is a book list", scenarios.themes("topics/books-on-my-nightstand.md"), {"books"})
check("a project is no list", scenarios.themes("projects/garden-shed.md"), set())

for case in scenarios.cases(random.Random(7)):
    if case["id"].startswith("done-other-"):
        check(f"{case['id']} reads the note before filing", case["expect"]["tools"][0], "read_note")
    if re.match(r"(file|done-other)-", case["id"]) and case["kind"] == "filing":
        check(f"{case['id']} ticks no todo", case["expect"].get("tools_not"), ["complete_todo"])
    # Twin lists are two of one kind on purpose; a plan may go anywhere.
    if case["id"].startswith("twin-") or case["kind"] == "plan":
        continue
    patterns = case["expect"].get("notes", {})
    wanted = set().union(*(scenarios.themes(p) for p in patterns))
    clash = sorted(p for p in case["notes"]
                   if scenarios.themes(p) & wanted and not any(re.search(q, p) for q in patterns))
    check(f"{case['id']} has no other list of its kind to add to", clash, [])

if failures:
    sys.exit(f"{failures} failed")
print("ok")
