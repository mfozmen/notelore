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

generated = scenarios.cases(random.Random(7))
asked = [c["expect"] for c in generated if c["id"].startswith("note-") and c["kind"] == "question"]
check("a question on a note expects its answer and no tool", (bool(asked), all(list(e) == ["answer"] for e in asked)), (True, True))

# A row about a note uses one an earlier table wrote, and a question's answer is in it.
written = {p: text for c in generated for p, text in c["notes"].items()}
for table in (scenarios.CROSS, scenarios.ON_NOTE):
    for lang, title, kind, msg, case_kind, tool, word in table:
        p = scenarios.path(kind, title)
        check(f"{title} is written before a row uses it", p in written, True)
        if tool is None:
            check(f"the answer to {msg!r} is in {title}", word.casefold() in written.get(p, "").casefold(), True)

for case in generated:
    if case["id"].startswith("done-other-"):
        # The entry's result names a matching todo (#731), so no read is required (#733).
        check(f"{case['id']} is filed as an entry, unread", case["expect"]["tools"], ["add_note_entry"])
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

# About me (v10): every such case has the file, and only about-me cases do, so no
# other case gets it as a distractor.
about = [c for c in generated if c["kind"] == "about-me"]
check("there are about-me cases", len(about) >= 80, True)
check("every about-me case has the about-me file", all("about-me.md" in c["notes"] for c in about), True)
check("no other case has the about-me file", any("about-me.md" in c["notes"] for c in generated if c["kind"] != "about-me"), False)
updates = [c for c in about if "update_about_me" in c["expect"].get("tools", [])]
check("updates outnumber plain remembers", len(updates) > sum("remember_about_me" in c["expect"].get("tools", []) for c in about) / 2, True)
check("an update never also remembers", all("remember_about_me" in c["expect"]["tools_not"] for c in updates), True)
for c in about:
    if "update_about_me" in c["expect"].get("tools", []) or c["id"].startswith("aboutme-known-"):
        check(f"{c['id']} has a fact to update or know", "\n- " in c["notes"]["about-me.md"], True)
# The app keeps the replaced file under history and a moved entry under _archive.
history, archive = r"^\.notelore/history/", "^_archive/"
for c in about:
    tools = c["expect"].get("tools", [])
    if "update_about_me" in tools or "forget_about_me" in tools:
        check(f"{c['id']} may keep a history copy", history in c["expect"]["notes"], True)
    if c["id"].startswith("aboutme-move-"):
        check(f"{c['id']} may archive the entry and update", (archive in c["expect"]["notes"], tools), (True, []))
needs = [c for c in generated if c["id"].startswith("need-")]
check("an undated need is a todo, never an entry",
      all(c["expect"]["tools_not"] == ["add_note_entry"] for c in needs if c["kind"] == "todo"), True)
check("every need set has an entry or reminder to tell it from",
      {c["kind"] for c in needs}, {"todo", "filing", "reminder"})
check("a new list beside a list of another kind", sum(c["id"].startswith("newlist-other-") for c in generated), 12)

if failures:
    sys.exit(f"{failures} failed")
print("ok")
