"""Tests for the training scenarios. Run by ci.yml:

    python3 tool/train/test_scenarios.py
"""

import json
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
check("a new list beside a list of another kind", sum(c["id"].startswith("newlist-other-") for c in generated), 22)

# Reminders (v12): every repeat value, a correction through change_reminder and
# a removal through remove_reminder, the old line kept under _archive.
repeats = [c for c in generated if c["id"].startswith("rem-repeat-")]
for value in ("daily", "weekly", "monthly", "yearly"):
    check(f"a {value} reminder is asked", any(f"({value})" in f for c in repeats
          for fs in c["expect"]["notes"].values() for f in fs), True)
once = [c for c in repeats if all("(" not in f for fs in c["expect"]["notes"].values() for f in fs)]
check("one-time reminders are asked too", len(once) >= 8, True)
check("a one-time reminder is written without a repeat", all(
    f.endswith(": ") for c in once for fs in c["expect"]["notes"].values() for f in fs[:1]), True)
for prefix, tool in (("rem-fix-", "change_reminder"), ("rem-remove-", "remove_reminder")):
    rows = [c for c in generated if c["id"].startswith(prefix)]
    check(f"there are {prefix} cases", len(rows) >= 10, True)
    for c in rows:
        check(f"{c['id']} calls {tool} and archives the old line",
              (c["expect"]["tools"], "^_archive/" in c["expect"]["notes"], bool(c.get("history"))), ([tool], True, True))
fixed_once = [c for c in generated if c["id"].startswith("rem-fix-") and
              any(f.endswith(": ") for fs in c["expect"]["notes"].values() for f in fs)]
check("a repeating reminder is fixed to once", len(fixed_once) >= 6, True)

# v12 kept this month for a monthly day that had passed ("the 1st" became
# 2026-10-01): a day already past rolls into November, a yearly date into 2027.
for lang in ("en", "tr"):
    rows = [r for r in scenarios.REPEATS if r[0] == lang]
    monthly = [r[4] for r in rows if r[5] == "monthly"]
    yearly = [r[4] for r in rows if r[5] == "yearly"]
    check(f"{lang} monthly days that rolled over outnumber those ahead",
          sum(a.startswith("2026-11") for a in monthly) > sum(a.startswith("2026-10") for a in monthly), True)
    check(f"{lang} yearly dates in 2027 outnumber those ahead in 2026",
          sum(a.startswith("2027") for a in yearly) > sum(a.startswith("2026") for a in yearly), True)
check("the 1st of every month is asked in both languages",
      [any(r[0] == lang and r[5] == "monthly" and r[4].startswith("2026-11-01") and re.search(pattern, r[3])
           for r in scenarios.REPEATS) for lang, pattern in (("en", r"1st of (every|each) month"), ("tr", r"ayın 1'inde"))],
      [True, True])

# v12b's rollover rows moved weekday dates a day early: weekday and relative
# days, in broad notes, at least match the monthly and yearly ones.
for lang in ("en", "tr"):
    repeats = [r for r in scenarios.REPEATS if r[0] == lang]
    dated = [r for r in scenarios.DATED if r[0] == lang]
    days = sum(r[5] in ("once", "daily", "weekly") for r in repeats) + len(dated)
    check(f"{lang} weekday and relative days match the monthly and yearly ones",
          days >= sum(r[5] in ("monthly", "yearly") for r in repeats), True)
    check(f"{lang} has Sunday later today and Sunday next week",
          (any(r[5].startswith("2026-10-18 ") for r in dated), any(r[5].startswith("2026-10-25") for r in dated)),
          (True, True))
    check(f"{lang} has days earlier in the week rolling to the coming one",
          sum("2026-10-19" <= r[5][:10] <= "2026-10-24" for r in dated) >= 8, True)
    check(f"{lang} dated rows go into broad notes, never one named after the reminder",
          all(r[1].split()[0].lower() not in r[3].lower() for r in dated), True)
vague = [c for c in generated if c["id"].startswith("vague-done-")]
check("vague done messages see several open todos and must ask",
      (len(vague) >= 6, all(c["expect"] == {"answer": ["?"], "tools_not": ["complete_todo"]} for c in vague),
       all(sum("- [ ] " in t for t in c["notes"].values()) >= 3 for c in vague)), (True, True, True))

# Earlier training rows carry these ids, so an id never changes its message
# (a row added mid-table renumbers the rest); a new id is added to the file.
pinned = json.loads((Path(__file__).resolve().parent / "scenario-ids.json").read_text(encoding="utf-8"))
messages = {c["id"]: c["message"] for c in generated}
check("every pinned id keeps its message", sorted(i for i, m in pinned.items() if messages.get(i) != m), [])
check("every id is pinned", sorted(set(messages) - set(pinned)), [])

if failures:
    sys.exit(f"{failures} failed")
print("ok")
