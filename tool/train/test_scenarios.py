"""Tests for the training scenarios. Run by ci.yml:

    python3 tool/train/test_scenarios.py
"""

import random
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
    if not case["id"].startswith("newlist"):
        continue
    wanted = set().union(*(scenarios.themes(p) for p in case["expect"]["notes"]))
    clash = sorted(p for p in case["notes"] if scenarios.themes(p) & wanted)
    check(f"{case['id']} has no list of its kind to add to", clash, [])

if failures:
    sys.exit(f"{failures} failed")
print("ok")
