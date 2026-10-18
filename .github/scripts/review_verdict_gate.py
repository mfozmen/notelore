"""Turns the AI reviewer's verdict line into the claude-review check result.

Called by .github/workflows/claude-review.yml after the review step. Reads the
reviewer's own finished comment on the PR, finds its REVIEW-VERDICT line and
exits non-zero on CRITICAL (or on no verdict at all), so a Critical finding
fails the check instead of hiding behind a green tick.

Standard library only, on purpose: it needs nothing but python3.
Adapted from mfozmen/conflict.

Tests: .github/scripts/test_review_verdict_gate.py (run by ci.yml).
"""

import json
import os
import re
import sys
import urllib.request

# A whole line, and only a whole line: prose that merely MENTIONS the marker
# (a PR describing this very mechanism, for one) must not be read as a verdict.
VERDICT = re.compile(r"^REVIEW-VERDICT: ([A-Z]+)$", re.MULTILINE)

# Only the review action's own finished comment counts. Without this, anyone
# able to comment on the PR could post "REVIEW-VERDICT: CLEAN" after a real
# Critical and flip the check green - or post CRITICAL to force an unrelated
# PR red (caught by the reviewer on this gate's own PR, #754).
#   - the author must be the Actions bot: a human cannot post as it, only a
#     workflow running with GITHUB_TOKEN can;
#   - the body must open with the action's completion signature, so another
#     github-actions comment, or a review still in progress, is not read.
# If the action ever rewords its signature, nothing matches and the gate reads
# MISSING and fails: it fails CLOSED, never open.
REVIEWER_LOGIN = "github-actions[bot]"
FINISHED_SIGNATURE = "**Claude finished"


# Both passes post as the same bot with the same signature; these lines tell
# them apart. The other pass's own comments are skipped; a body carrying both
# passes' lines (a quote, a slip, an injection) resets the verdict to none, so
# the check fails closed instead of crossing over or keeping an older verdict.
SECURITY_MARKERS = re.compile(r"^SECURITY-VERDICT:", re.MULTILINE)
REVIEW_MARKERS = re.compile(r"^(REVIEW-VERDICT|REVIEWED-HEAD):", re.MULTILINE)


def latest_verdict(comments, marker=VERDICT, foreign=SECURITY_MARKERS):
    """The verdict of the newest finished review comment, else None.

    `comments` is a list of (author login, body) pairs, oldest first. Anything
    not written by the review action's own completed comment is ignored.
    `marker` picks whose verdict: the code review's, or the security pass's
    (security_verdict_gate.py); `foreign` matches the other pass's lines.
    """
    found = None
    for login, body in comments:
        body = body or ""
        if login != REVIEWER_LOGIN or not body.startswith(FINISHED_SIGNATURE):
            continue
        matches = marker.findall(body)
        if foreign.search(body):
            if matches:
                found = None  # both passes' lines: trust neither, nor anything older
            continue
        if matches:
            found = matches[-1]
    return found


def fetch_bodies(repo, number, token):
    """Every issue comment on the PR as (author login, body), following pagination."""
    bodies, page = [], 1
    while True:
        url = (
            f"https://api.github.com/repos/{repo}/issues/{number}/comments?per_page=100&page={page}"
        )
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            batch = json.load(response)
        if not batch:
            return bodies
        bodies.extend(
            ((comment.get("user") or {}).get("login", ""), comment.get("body") or "")
            for comment in batch
        )
        page += 1


def decide(verdict):
    """(exit code, message) for a verdict — the part that sets the check."""
    if verdict == "CRITICAL":
        return 1, (
            "::error::Claude review reported a Critical finding - read its "
            "comment on the PR. Fix it, or downgrade it there with a "
            "reason if you disagree."
        )
    if verdict == "WARNING":
        return 0, (
            "::warning::Claude review reported a Warning - not blocking, "
            "but read it before merging."
        )
    if verdict == "CLEAN":
        return 0, "Reviewer found nothing blocking."
    return 1, (
        "::error::The review ran but published no REVIEW-VERDICT line, so "
        "its verdict is unknown. Re-run this job; if it keeps happening "
        "the prompt contract is broken."
    )


def main():
    bodies = fetch_bodies(
        os.environ["GITHUB_REPOSITORY"], os.environ["PR_NUMBER"], os.environ["GH_TOKEN"]
    )
    verdict = latest_verdict(bodies)
    print(f"reviewer verdict: {verdict or 'MISSING'} (from {len(bodies)} comment(s))")
    code, message = decide(verdict)
    print(message)
    return code


if __name__ == "__main__":
    sys.exit(main())
