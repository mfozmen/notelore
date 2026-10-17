"""The priority gate for issues (issue-priority.yml): every issue carries a
priority/* label. One opened without it takes the priority picked in the issue
form, or is closed with a note until a label is added, and then reopened.

    python3 issue_priority.py <event.json>   prints: ok | label <name> | close | reopen
"""

import json
import re
import sys

PRIORITIES = ("critical", "high", "medium", "low")

# In the gate's closing comment, so a later label reopens only what the gate closed.
MARKER = "<!-- priority-gate -->"


def form_priority(body):
    """The priority chosen in the issue form ("### Priority" then the value)."""
    found = re.search(r"^### Priority\s*\n+\s*(\S+)", body or "", re.MULTILINE)
    value = found.group(1).lower() if found else None
    return value if value in PRIORITIES else None


def decide(labels, body, state, comments):
    """What to do with an issue, from its label names, body, state and comments."""
    if any(label.startswith("priority/") for label in labels):
        closed_by_gate = any(MARKER in comment for comment in comments)
        return "reopen" if state == "closed" and closed_by_gate else "ok"
    if priority := form_priority(body):
        return f"label priority/{priority}"
    return "close" if state == "open" else "ok"


def main(path, comments):
    issue = json.load(open(path, encoding="utf-8"))["issue"]
    labels = [label["name"] for label in issue["labels"]]
    print(decide(labels, issue["body"], issue["state"], comments))


if __name__ == "__main__":
    main(sys.argv[1], [line for line in sys.stdin.read().split("\x1e") if line])
