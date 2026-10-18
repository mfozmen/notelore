"""Tests for finetune.py's pure parts, without torch or a GPU (the training
libraries are stubbed). Run by ci.yml:

    python3 tool/train/test_finetune.py
"""

import sys
import types
from pathlib import Path

for name in ("torch", "datasets", "peft", "transformers", "trl"):
    stub = types.ModuleType(name)
    stub.__getattr__ = lambda attr: attr  # any name the script imports, as itself
    sys.modules[name] = stub
sys.modules["torch"].bfloat16, sys.modules["torch"].float16 = "bfloat16", "float16"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from finetune import clean, precision

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")


check("bf16 where the GPU has it", precision(True), ({"bf16": True, "fp16": False}, "bfloat16"))
check("fp16 on a GPU without bf16 (Kaggle's T4)", precision(False), ({"bf16": False, "fp16": True}, "float16"))

check(
    "an answer keeps only what follows the leaked reasoning",
    clean({"role": "assistant", "content": "Okay, let me see.\n</think>\n\nSaved."}),
    {"role": "assistant", "content": "Saved."},
)
call = {"function": {"name": "read_note", "arguments": {"slug": "x"}}}
check(
    "a tool call loses its text",
    clean({"role": "assistant", "content": "I will read it.", "tool_calls": [call]}),
    {"role": "assistant", "content": "", "tool_calls": [call]},
)
check("other roles stay as they are", clean({"role": "user", "content": " hi "}), {"role": "user", "content": " hi "})

sys.exit(1 if failures else 0)
