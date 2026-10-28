"""Preference pairs for DPO (#607) from distilled turns: for one case, a turn the
eval passed against the student's own turn it failed, cut where they part:

    python tool/train/pairs.py <passed.jsonl>... --failed=<failed.jsonl> --out=<pairs.jsonl> [--most=4]

The prompt is everything both turns share (system prompt, message, the calls and
results up to the split), chosen and rejected the one assistant message after it.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

from finetune import clean


def _same(a, b):
    return clean(a) == clean(b)


def _shared(a, b):
    """How many messages two turns start with alike."""
    i = 0
    while i < min(len(a), len(b)) and _same(a[i], b[i]):
        i += 1
    return i


def pair(passed, failed):
    """The pair of two turns of one case, or None when neither has a message the
    other lacks at the split (one is a prefix of the other, or they are equal)."""
    a, b = passed["messages"], failed["messages"]
    i = _shared(a, b)
    if i == len(a) or i == len(b) or a[i]["role"] != "assistant" or b[i]["role"] != "assistant":
        return None
    return {"id": passed["id"], "prompt": a[:i], "chosen": [clean(a[i])], "rejected": [clean(b[i])],
            "tools": passed["tools"]}


def pairs(passed, failed, most=4):
    """Each failed turn against the passed turn of its case that shares most of
    its start, so the split falls nearest the mistake; at most [most] pairs a
    case so no case outweighs the rest."""
    wins, made, count = defaultdict(list), [], defaultdict(int)
    for row in passed:
        wins[row["id"]].append(row)
    for row in failed:
        case = row["id"]
        if not wins[case] or count[case] >= most:
            continue
        p = pair(max(wins[case], key=lambda w: _shared(w["messages"], row["messages"])), row)
        if p:
            made.append(p)
            count[case] += 1
    return made


def _rows(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]


def main(argv):
    def option(name, default=None):
        return next((a.split("=", 1)[1] for a in argv if a.startswith(f"--{name}=")), default)

    passed = [r for path in argv if not path.startswith("--") for r in _rows(path)]
    made = pairs(passed, _rows(option("failed")), int(option("most", "4")))
    with open(option("out"), "w", encoding="utf-8", newline="\n") as out:
        for p in made:
            out.write(json.dumps(p, ensure_ascii=False) + "\n")
    print(f"{len(made)} pairs from {len({p['id'] for p in made})} cases -> {option('out')}")


if __name__ == "__main__":
    main(sys.argv[1:])
