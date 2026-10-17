"""Closes every epic (milestone) whose issues are all closed (#318, after
mfozmen/conflict). Run by close-finished-epics.yml whenever an issue closes or
changes milestone, so it covers merges by any session or tool.

Usage (repo root, GH_TOKEN and GH_REPO set):

    python3 .github/scripts/close_finished_epics.py

Standard library only. Tests: .github/scripts/test_close_finished_epics.py (ci.yml).
"""

import json
import subprocess
import sys


def finished(milestones):
    """The open milestones with no open issue and at least one closed one: an
    epic that never had an issue is not finished."""
    return [
        m
        for m in milestones
        if m.get("state") == "open" and m.get("open_issues", 0) == 0 and m.get("closed_issues", 0) > 0
    ]


def parse_lines(raw):
    """The milestones `gh api --paginate --jq '.[]'` printed, one JSON object a line."""
    return [json.loads(line) for line in raw.splitlines() if line.strip()]


def gh(*args):
    """Runs gh; a failure stops the run (a red job), never reads as \"nothing to do\"."""
    run = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8")
    if run.returncode:
        sys.exit(f"gh {' '.join(args)}: {run.stderr.strip()}")
    return run.stdout


def main():
    raw = gh("api", "--paginate", "--jq", ".[]", "repos/{owner}/{repo}/milestones?state=open&per_page=100")
    for m in finished(parse_lines(raw)):
        gh("api", "-X", "PATCH", f"repos/{{owner}}/{{repo}}/milestones/{m['number']}", "-f", "state=closed")
        print(f"closed epic #{m['number']} {m['title']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
