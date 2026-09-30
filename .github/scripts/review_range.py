"""Decides what the AI reviewer looks at: only what changed since its last review.

Called by .github/workflows/claude-review.yml before the review step. The
reviewer's own finished comment ends with a `REVIEWED-HEAD: <sha>` line, so the
PR thread is the reviewer's notebook. This script finds the newest such line,
checks the sha is still an ancestor of the PR head (a rebase or force-push makes
it unreachable, and `git log A..B` would then list the whole branch), and hands
the review step:

  mode     incremental | full | unchanged
  base     the last reviewed sha (incremental/unchanged), else empty
  head     the PR head sha now under review
  commits  this PR's own new commits since base; merges and main's commits are
           left out so merging main into the branch does not flood the review
  previous the previous summary itself (kept even after a force-push), so open
           findings are checked closed rather than re-derived; passed inline
           because the reviewer may not read files outside the checkout

Standard library only. Adapted from mfozmen/conflict.
Tests: .github/scripts/test_review_range.py (run by ci.yml).
"""

import json
import os
import re
import subprocess
import sys
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from review_verdict_gate import FINISHED_SIGNATURE, REVIEWER_LOGIN, fetch_bodies

REVIEWED_HEAD = re.compile(r"^REVIEWED-HEAD: ([0-9a-f]{7,40})$", re.MULTILINE)


def last_review(comments):
    """(reviewed sha, body) of the newest finished review naming its head, else (None, None).

    `comments` is (author login, body) pairs, oldest first; only the review
    action's own completed comment counts, as in the verdict gate.
    """
    found = (None, None)
    for login, body in comments:
        body = body or ""
        if login != REVIEWER_LOGIN or not body.startswith(FINISHED_SIGNATURE):
            continue
        matches = REVIEWED_HEAD.findall(body)
        if matches:
            found = (matches[-1], body)
    return found


def choose_mode(base, head, is_ancestor):
    """full without a usable earlier review, unchanged when it already saw this head,
    incremental otherwise. `is_ancestor(base, head)` asks git."""
    if not base:
        return "full"
    if head.startswith(base) or base.startswith(head):
        return "unchanged"
    return "incremental" if is_ancestor(base, head) else "full"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)


def is_ancestor(base, head):
    return git("merge-base", "--is-ancestor", base, head).returncode == 0


def own_commits(base, head, main_ref="origin/main"):
    """This PR's commits since `base`, oldest first, without merges or main's commits.

    A failing `git log` raises: an empty answer would read as "nothing new" and
    silently skip the review.
    """
    listed = git(
        "log", "--no-merges", "--reverse", "--format=%h %s", f"{base}..{head}", f"^{main_ref}"
    )
    if listed.returncode != 0:
        raise RuntimeError(f"git log failed: {listed.stderr.strip()}")
    return listed.stdout.strip()


def pr_head(repo, number, token):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/pulls/{number}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)["head"]["sha"]


def write_outputs(path, values, delimiter=None):
    # A random delimiter: commit subjects flow into `commits`, and a fixed one could
    # be closed early by a subject equal to it, letting the rest overwrite `mode`.
    delimiter = delimiter or f"RANGE_{uuid.uuid4().hex}"
    with Path(path).open("a", encoding="utf-8") as out:
        for key, value in values.items():
            if "\n" in value:
                out.write(f"{key}<<{delimiter}\n{value}\n{delimiter}\n")
            else:
                out.write(f"{key}={value}\n")


def main():
    repo, number = os.environ["GITHUB_REPOSITORY"], os.environ["PR_NUMBER"]
    token = os.environ["GH_TOKEN"]
    head = pr_head(repo, number, token)
    base, previous = last_review(fetch_bodies(repo, number, token))
    mode = choose_mode(base or "", head, is_ancestor)
    commits = own_commits(base, head) if mode == "incremental" else ""
    if mode == "incremental" and not commits:
        mode = "unchanged"  # only merges from main arrived: nothing of its own to review
    write_outputs(
        os.environ["GITHUB_OUTPUT"],
        {
            "mode": mode,
            "base": (base or "") if mode != "full" else "",
            "head": head,
            "commits": commits,
            "previous": previous or "(none)",
        },
    )
    print(f"review range: mode={mode} base={base or '-'} head={head}")


if __name__ == "__main__":
    main()
