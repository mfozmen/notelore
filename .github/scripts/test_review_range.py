"""Tests for review_range: which earlier review counts, and which mode follows.
No network, no git. Run by ci.yml:

    python3 .github/scripts/test_review_range.py
"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from review_range import choose_mode, last_review, write_outputs
from review_verdict_gate import REVIEWER_LOGIN

BOT = REVIEWER_LOGIN
DONE = "**Claude finished @owner's task in 2m** ---\n"


def review(sha):
    return (BOT, DONE + "findings...\n\nREVIEWED-HEAD: " + sha + "\nREVIEW-VERDICT: CLEAN")


failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")


check("no comments", last_review([])[0], None)
check("a finished review names its head", last_review([review("abc1234")])[0], "abc1234")
check("the newest review wins", last_review([review("abc1234"), review("def5678")])[0], "def5678")
check(
    "an older review without the line does not hide a newer one",
    last_review([review("abc1234"), (BOT, DONE + "REVIEW-VERDICT: CLEAN")])[0],
    "abc1234",
)
check(
    "SPOOF: a human REVIEWED-HEAD is ignored",
    last_review([review("abc1234"), ("someone", "REVIEWED-HEAD: 0000000")])[0],
    "abc1234",
)
check(
    "SPOOF: a human copying the signature is ignored",
    last_review([("someone", DONE + "REVIEWED-HEAD: 0000000")])[0],
    None,
)
check(
    "an in-progress bot comment is ignored",
    last_review([(BOT, "working...\nREVIEWED-HEAD: abc1234")])[0],
    None,
)
check(
    "prose mentioning the marker mid-line is not a head",
    last_review([(BOT, DONE + "we write REVIEWED-HEAD: abc1234 at the end")])[0],
    None,
)

always, never = (lambda base, head: True), (lambda base, head: False)
check("no earlier review -> full", choose_mode("", "f" * 40, always), "full")
check(
    "same head (short sha) -> unchanged",
    choose_mode("abc1234", "abc1234" + "e" * 33, always),
    "unchanged",
)
check(
    "earlier head is an ancestor -> incremental",
    choose_mode("abc1234", "f" * 40, always),
    "incremental",
)
check(
    "force-push / rebase made it unreachable -> full",
    choose_mode("abc1234", "f" * 40, never),
    "full",
)

with tempfile.TemporaryDirectory() as folder:
    out_path = Path(folder) / "out"
    write_outputs(
        out_path,
        {"commits": "abc fix\nRANGE_EOF\nmode=unchanged", "mode": "incremental"},
        delimiter="RANGE_abc123",
    )
    lines = out_path.read_text(encoding="utf-8").splitlines()
check(
    "a subject equal to the old fixed delimiter stays inside the value",
    lines,
    [
        "commits<<RANGE_abc123",
        "abc fix",
        "RANGE_EOF",
        "mode=unchanged",
        "RANGE_abc123",
        "mode=incremental",
    ],
)

print("ALL PASS" if failures == 0 else f"{failures} FAILURE(S)")
sys.exit(1 if failures else 0)
