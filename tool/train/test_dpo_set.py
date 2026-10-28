"""Tests for the DPO scenario set (#607). Run by ci.yml:

    python3 tool/train/test_dpo_set.py
"""

import collections
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dpo_set

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "nested" / "scenarios-dpo.json"
    dpo_set.main([str(out)])  # its own checks: disjoint from training and held-out, one note per case
    written = json.loads(out.read_text(encoding="utf-8"))

counts = collections.Counter(c["kind"] for c in written)
check("every kind has its minimum", {k: n for k, n in counts.items() if n < dpo_set.MIN_PER_KIND}, {})
check("all twelve kinds are there", len(counts), 12)

if failures:
    sys.exit(f"{failures} failed")
print("ok")
