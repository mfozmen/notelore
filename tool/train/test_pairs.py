"""Tests for pairs.py. Run by ci.yml:

    python3 tool/train/test_pairs.py
"""

import sys
import types
from pathlib import Path

# pairs.py takes clean() from finetune.py, whose training libraries CI lacks.
for name in ("torch", "datasets", "peft", "transformers", "trl"):
    stub = types.ModuleType(name)
    stub.__getattr__ = lambda attr: attr
    sys.modules[name] = stub

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pairs import pair, pairs

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def call(name, **arguments):
    return {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": name, "arguments": arguments}}]}


def result(name, content):
    return {"role": "tool", "content": content, "tool_name": name}


system = {"role": "system", "content": "prompt"}
user = {"role": "user", "content": "Garden shed: I ordered the timber."}
read = call("read_note", slug="garden-shed")
note = result("read_note", "open todo 1 of garden-shed")
tick = call("complete_todo", slug="garden-shed", number=1)
entry = call("add_note_entry", slug="garden-shed", text="Ordered the timber.")
done = {"role": "assistant", "content": "Ticked it."}


def row(case, *messages):
    return {"id": case, "messages": [system, user, *messages], "tools": ["t"]}


good = row("done-1", read, note, tick, result("complete_todo", "ok"), done)
skip = row("done-1", entry, result("add_note_entry", "ok"), done)
late = row("done-1", read, note, entry, result("add_note_entry", "ok"), done)

check("a pair splits at the first call they disagree on", pair(good, skip),
      {"id": "done-1", "prompt": [system, user], "chosen": [read], "rejected": [entry], "tools": ["t"]})
check("a shared start goes into the prompt", pair(good, late)["prompt"], [system, user, read, note])
check("then the calls part", (pair(good, late)["chosen"], pair(good, late)["rejected"]), ([tick], [entry]))
check("the reasoning a teacher leaks is no difference",
      pair(good, row("done-1", {**read, "content": "<think>hm</think>"}, note, entry))["rejected"], [entry])
check("a turn that is a prefix of the other gives no pair", pair(good, row("done-1", read, note)), None)
check("two equal turns give no pair", pair(good, good), None)

other = row("done-2", entry, result("add_note_entry", "ok"), done)
made = pairs([good], [skip, late, skip, other], most=2)
check("each failure pairs with a pass of its case, at most `most` a case",
      [(p["id"], p["rejected"]) for p in made], [("done-1", [entry]), ("done-1", [entry])])
check("a failure whose case never passed is left out", [p for p in made if p["id"] == "done-2"], [])

later = call("complete_todo", slug="garden-shed", number=2)
other_good = row("done-1", read, note, entry, result("add_note_entry", "ok"), later, done)
check("a failure pairs with the pass that shares most of its start, nearest its mistake",
      pairs([good, other_good], [row("done-1", read, note, entry, result("add_note_entry", "ok"), done)])[0]["chosen"],
      [later])

if failures:
    sys.exit(f"{failures} failed")
print("ok")
