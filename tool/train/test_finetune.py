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
import finetune
from finetune import clean, load, precision

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")


check("bf16 where the GPU has it", precision(True), ({"bf16": True, "fp16": False}, "bfloat16"))
check("fp16 on a GPU without bf16 (Kaggle's T4)", precision(False), ({"bf16": False, "fp16": True}, "float16"))


class Recorder:
    """Stands in for a transformers class: records what it was built with."""

    def __init__(self, **kwargs):
        self.kwargs = kwargs

    @classmethod
    def from_pretrained(cls, *args, **kwargs):
        return cls(args=args, **kwargs)


finetune.AutoModelForCausalLM = finetune.BitsAndBytesConfig = Recorder
model = load("base", "float16")
# The parts left unquantized (embeddings, lm_head) take it too: kept in the
# checkpoint's bf16, a T4 fails in the loss (Kaggle run 1).
check("the whole model loads in the precision's dtype", model.kwargs.get("dtype"), "float16")
check("and so does the 4-bit compute", model.kwargs["quantization_config"].kwargs["bnb_4bit_compute_dtype"], "float16")

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
