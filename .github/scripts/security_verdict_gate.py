"""Turns the security pass's verdict line into the security-review check result.

Called by .github/workflows/ai-review.yml after the security pass, which
runs only when a PR touches sensitive paths (sensitive_paths.py). It reads the
pass's own finished comment, verifies its SECURITY-REVIEWED-HEAD is the head
this run reviewed, finds its SECURITY-VERDICT line and exits non-zero on
CRITICAL (or on no verdict at all). It never reads the code review's
REVIEW-VERDICT, and review_verdict_gate.py never reads this one.

Standard library only. Tests: .github/scripts/test_security_verdict_gate.py.
"""

import os
import re
import sys

from review_verdict_gate import (
    REVIEW_MARKERS,
    SECURITY_REVIEWED_HEAD,
    fetch_bodies,
    head_matches,
)
from review_verdict_gate import latest_head as _latest_head
from review_verdict_gate import latest_verdict as _latest

# A whole line only, as for the code review's verdict.
SECURITY_VERDICT = re.compile(r"^SECURITY-VERDICT: ([A-Z]+)$", re.MULTILINE)


def latest_verdict(comments, run_id=None):
    """The newest finished security pass's verdict, else None."""
    return _latest(comments, SECURITY_VERDICT, foreign=REVIEW_MARKERS, run_id=run_id)


def latest_head(comments, run_id=None):
    """The head the newest finished security pass reviewed, else None."""
    return _latest_head(comments, SECURITY_REVIEWED_HEAD, foreign=REVIEW_MARKERS, run_id=run_id)


def decide(verdict):
    """(exit code, message) for a verdict."""
    if verdict == "CRITICAL":
        return 1, (
            "::error::The security pass reported a Critical finding - read its "
            "comment on the PR and fix it before merging."
        )
    if verdict == "WARNING":
        return 0, "::warning::The security pass reported a Warning - read it before merging."
    if verdict == "CLEAN":
        return 0, "The security pass found nothing blocking."
    return 1, (
        "::error::The security pass ran but published no SECURITY-VERDICT line. "
        "Re-run this job; if it keeps happening the prompt contract is broken."
    )


def main():
    bodies = fetch_bodies(
        os.environ["GITHUB_REPOSITORY"], os.environ["PR_NUMBER"], os.environ["GH_TOKEN"]
    )
    run_id = os.environ.get("GITHUB_RUN_ID")
    expected = os.environ.get("REVIEW_HEAD", "")
    head = latest_head(bodies, run_id=run_id)
    if not head_matches(expected, head):
        print(f"::error::The security pass posted head {head or 'MISSING'}, expected {expected}.")
        return 1
    verdict = latest_verdict(bodies, run_id=run_id)
    print(f"security verdict: {verdict or 'MISSING'} (from {len(bodies)} comment(s))")
    code, message = decide(verdict)
    print(message)
    return code


if __name__ == "__main__":
    sys.exit(main())
