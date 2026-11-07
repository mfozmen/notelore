"""A one-line plan before the first tool call (#608): `plan: <note> → <action>`,
derived from the verified turn itself, no teacher text. The note is the slug
the decision goes to (`new` for a note made, `-` for none); the action is the
first write that is not a new note, else `create_note`, else `ask` when the
answer asks back, else `answer`, as `eval --first-write` scores it. The app
never shows the line: the provider strips it.

    python tool/train/plan.py train-v7.jsonl train-v7-plan.jsonl

Standard library only.
"""

import json
import sys
from pathlib import Path

READS = {"list_notes", "read_note", "search_notes", "related_notes", "get_decision", "decision_history"}


def _calls(row):
    return [c["function"] for m in row["messages"] if m["role"] == "assistant" for c in m.get("tool_calls") or []]


def line(row):
    """The plan for [row], or None for a turn without a tool call."""
    calls = _calls(row)
    if not calls:
        return None
    writes = [c for c in calls if c["name"] not in READS]
    decided = next((c for c in writes if c["name"] != "create_note"), None)
    if decided:
        return f"plan: {decided['arguments'].get('slug', '-')} → {decided['name']}"
    if writes:
        return "plan: new → create_note"
    answer = row["messages"][-1].get("content") or ""
    slug = next((c["arguments"]["slug"] for c in calls if "slug" in c["arguments"]), "-")
    return f"plan: {slug} → {'ask' if '?' in answer else 'answer'}"


def main(argv):
    src, out = argv
    rows = []
    for text in Path(src).read_text(encoding="utf-8").splitlines():
        row = json.loads(text)
        planned = line(row)
        if planned:
            first = next(m for m in row["messages"] if m["role"] == "assistant" and m.get("tool_calls"))
            first["content"] = planned
        rows.append(json.dumps(row, ensure_ascii=False))
    Path(out).write_text("\n".join(rows) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
