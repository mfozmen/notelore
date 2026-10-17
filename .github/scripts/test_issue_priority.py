"""Tests for issue_priority: what the gate does with an issue's labels and body.
No network. Run by ci.yml:

    python3 .github/scripts/test_issue_priority.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from issue_priority import MARKER, decide, form_priority

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")


FORM = "### What is it about?\n\nSomething.\n\n### Priority\n\nHigh\n"

check("the form's priority", form_priority(FORM), "high")
check("no form", form_priority("plain text"), None)
check("an unknown priority", form_priority("### Priority\n\nurgent!!\n"), None)
check("no body", form_priority(None), None)

check("labelled: nothing to do", decide(["bug", "priority/low"], "", "open", []), "ok")
check("from the form", decide([], FORM, "open", []), "label priority/high")
check("no priority: closed", decide(["bug"], "text", "open", []), "close")
check("already closed by someone else: left alone", decide([], "text", "closed", []), "ok")
check(
    "labelled after the gate closed it: reopened",
    decide(["priority/medium"], "", "closed", ["thanks", MARKER + " closed"]),
    "reopen",
)
check(
    "labelled but closed by a person: stays closed",
    decide(["priority/medium"], "", "closed", ["done, fixed in #1"]),
    "ok",
)

sys.exit(1 if failures else 0)
