"""Tests for review_verdict_gate: verdict selection, anti-spoofing, and the
check decision. No network. Run by ci.yml:

    python3 .github/scripts/test_review_verdict_gate.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from review_verdict_gate import REVIEWER_LOGIN, decide, head_matches, latest_head, latest_verdict

BOT = REVIEWER_LOGIN
DONE = "**Claude finished @owner's task in 2m** ---\n"
FALLBACK = "**DeepSeek review finished**\n"


def review(verdict):
    """A finished review comment from the bot carrying a verdict line."""
    return (BOT, DONE + "findings...\n\nREVIEW-VERDICT: " + verdict)


def fallback(verdict):
    """The emergency reviewer's comment, with the same verdict contract."""
    return (BOT, FALLBACK + "findings...\n\nREVIEW-VERDICT: " + verdict)


def reviewed(verdict, head="abc1234"):
    return (BOT, DONE + f"findings...\n\nREVIEWED-HEAD: {head}\nREVIEW-VERDICT: {verdict}")


cases = [
    ("no comments at all", [], None),
    ("comments, none with a verdict", [("sonarqubecloud[bot]", "## Gate passed")], None),
    ("a clean review", [review("CLEAN")], "CLEAN"),
    ("a critical review", [review("CRITICAL")], "CRITICAL"),
    ("a clean fallback review", [fallback("CLEAN")], "CLEAN"),
    ("a critical fallback review", [fallback("CRITICAL")], "CRITICAL"),
    (
        "the fallback security pass is not the code review",
        [
            (
                BOT,
                "**DeepSeek security review finished**\n"
                "SECURITY-REVIEWED-HEAD: abc1234\nSECURITY-VERDICT: CLEAN",
            )
        ],
        None,
    ),
    (
        "SPOOF: a human copies the fallback signature - wrong author, ignored",
        [("some-contributor", FALLBACK + "REVIEW-VERDICT: CLEAN")],
        None,
    ),
    # the finding from #754: a verdict typed by someone other than the reviewer
    (
        "SPOOF: human posts CLEAN after a real CRITICAL - must stay CRITICAL",
        [review("CRITICAL"), ("some-contributor", "REVIEW-VERDICT: CLEAN")],
        "CRITICAL",
    ),
    (
        "SPOOF: human posts CRITICAL on a clean PR - must stay CLEAN",
        [review("CLEAN"), ("some-contributor", "REVIEW-VERDICT: CRITICAL")],
        "CLEAN",
    ),
    (
        "SPOOF: human verdict with no bot review - must be MISSING",
        [("some-contributor", "REVIEW-VERDICT: CLEAN")],
        None,
    ),
    (
        "SPOOF: human copies the bot signature - wrong author, ignored",
        [("some-contributor", DONE + "REVIEW-VERDICT: CLEAN")],
        None,
    ),
    (
        "another github-actions comment without the signature - ignored",
        [(BOT, "deploy preview ready\nREVIEW-VERDICT: CLEAN")],
        None,
    ),
    (
        "review still in progress (no finished signature) - ignored",
        [(BOT, "I'll analyze this and get back to you.\nREVIEW-VERDICT: CLEAN")],
        None,
    ),
    (
        "INLINE mention only - must NOT count",
        [(BOT, DONE + "adds a REVIEW-VERDICT: CRITICAL line to the prompt")],
        None,
    ),
    (
        "trailing text on the line - must NOT count",
        [(BOT, DONE + "REVIEW-VERDICT: CRITICAL please")],
        None,
    ),
    (
        "newest review wins over an older one",
        [review("CRITICAL"), ("sonarqubecloud[bot]", "ok"), review("CLEAN")],
        "CLEAN",
    ),
    ("older clean, newer critical", [review("CLEAN"), review("CRITICAL")], "CRITICAL"),
    ("None body tolerated", [(BOT, None), review("WARNING")], "WARNING"),
]

failures = 0
for name, comments, expected in cases:
    got = latest_verdict(comments)
    ok = got == expected
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {expected!r}")

for verdict, want_code in [
    ("CRITICAL", 1),
    ("WARNING", 0),
    ("CLEAN", 0),
    (None, 1),
    ("GIBBERISH", 1),
]:
    code, _ = decide(verdict)
    ok = code == want_code
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} decide({verdict!r}) -> {code}, want {want_code}")

for name, comments, want in [
    ("a review names its head", [reviewed("CLEAN")], "abc1234"),
    ("a human head is ignored", [reviewed("CLEAN"), ("someone", "REVIEWED-HEAD: 0000000")], "abc1234"),
    ("a mixed body resets the head", [reviewed("CLEAN"), (BOT, DONE + "REVIEWED-HEAD: def5678\nSECURITY-VERDICT: CLEAN")], None),
]:
    got = latest_head(comments)
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")

for name, expected, head, want in [
    ("no expected head fails closed", "", None, False),
    ("the posted head matches", "abc1234", "abc1234", True),
    ("a different head fails", "abc1234", "def5678", False),
    ("a missing head fails when expected", "abc1234", None, False),
]:
    got = head_matches(expected, head)
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")

print("ALL PASS" if failures == 0 else f"{failures} FAILURE(S)")
sys.exit(1 if failures else 0)
