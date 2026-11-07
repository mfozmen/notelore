"""Tests for the one-line plan (#608). Run by ci.yml:

    python3 tool/train/test_plan.py
"""

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import plan

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def call(name, **args):
    return {"function": {"name": name, "arguments": args}}


def row(*messages):
    return {"id": "x", "messages": [{"role": "system", "content": "s"}, *messages]}


def user(text):
    return {"role": "user", "content": text}


def calls(*tool_calls):
    return {"role": "assistant", "content": "", "tool_calls": list(tool_calls)}


def said(text):
    return {"role": "assistant", "content": text}


TOOL = {"role": "tool", "content": "ok"}

# The first write that is not a new note, with the note it goes to.
done = row(
    user("Ev tadilatı: elektrikçiyi aradım"),
    calls(call("read_note", slug="ev-tadilati")),
    TOOL,
    calls(call("complete_todo", slug="ev-tadilati", line=2)),
    TOOL,
    said("Tamam."),
)
check("done", plan.line(done), "plan: ev-tadilati → complete_todo")

# A new list note, then the entry into it: the entry is the decision.
listed = row(
    user("Movie to watch: Perfect Days"),
    calls(call("related_notes", title="Perfect Days")),
    TOOL,
    calls(call("create_note", kind="topic", title="Movies to Watch")),
    TOOL,
    calls(call("add_note_entry", slug="movies-to-watch", text="Perfect Days")),
    TOOL,
    said("Added."),
)
check("entry after create", plan.line(listed), "plan: movies-to-watch → add_note_entry")

check(
    "only a new note",
    plan.line(row(user("New project: shed"), calls(call("create_note", kind="project", title="Shed")), TOOL, said("Made."))),
    "plan: new → create_note",
)
check(
    "a question",
    plan.line(row(user("What is on my list?"), calls(call("read_note", slug="books")), TOOL, said("Two books."))),
    "plan: books → answer",
)
check(
    "asks back",
    plan.line(row(user("Add it"), calls(call("list_notes")), TOOL, said("Which note?"))),
    "plan: - → ask",
)
check("no tool call: no plan", plan.line(row(user("Hi"), said("Hello!"))), None)

# Written into the first call's content; the rest of the row stays as it was.
with tempfile.TemporaryDirectory() as tmp:
    src, out = Path(tmp) / "in.jsonl", Path(tmp) / "out.jsonl"
    hi = row(user("Hi"), said("Hello!"))
    src.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in [done, hi]) + "\n", encoding="utf-8")
    plan.main([str(src), str(out)])
    got = [json.loads(line) for line in out.read_text(encoding="utf-8").splitlines()]
    check("first call carries it", got[0]["messages"][2]["content"], "plan: ev-tadilati → complete_todo")
    check("later calls do not", got[0]["messages"][4]["content"], "")
    check("tool calls kept", got[0]["messages"][2]["tool_calls"], done["messages"][2]["tool_calls"])
    check("a chat row unchanged", got[1], hi)
    check("short", max(len(r["messages"][2]["content"].split()) for r in got[:1]) <= 25, True)

print("ok" if not failures else f"{failures} failed")
sys.exit(1 if failures else 0)
