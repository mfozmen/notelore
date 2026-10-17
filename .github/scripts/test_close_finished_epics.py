"""Tests for close_finished_epics: which milestones count as finished.
No network. Run by ci.yml:

    python3 .github/scripts/test_close_finished_epics.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from close_finished_epics import finished, parse_lines

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")


def numbers(milestones):
    return [m["number"] for m in finished(milestones)]


def epic(number, state="open", open_issues=0, closed_issues=0):
    return {"number": number, "state": state, "open_issues": open_issues, "closed_issues": closed_issues}


check("every issue closed: finished", numbers([epic(1, closed_issues=3)]), [1])
check("an issue still open: not finished", numbers([epic(2, open_issues=1, closed_issues=3)]), [])
check("a new epic with no issue yet: not finished", numbers([epic(3)]), [])
check("an epic already closed: left alone", numbers([epic(4, state="closed", closed_issues=2)]), [])
check("only the finished ones of several", numbers([epic(5, closed_issues=1), epic(6, open_issues=2)]), [5])

# `gh api --paginate --jq '.[]'` prints one milestone per line, whatever the pages.
lines = '{"number": 7, "title": "Fix [a][b] links"}\n{"number": 8, "title": "x"}\n'
check("one milestone per line, brackets in a title kept", [m["title"] for m in parse_lines(lines)], ["Fix [a][b] links", "x"])
check("nothing open", parse_lines(""), [])

sys.exit(1 if failures else 0)
