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
from finetune import (
    assistant_labels,
    clean,
    fp32_logprobs,
    load,
    main,
    modelfile,
    gpu_settings,
    native_bf16,
    precision,
)

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r}, want {want!r}")




def gpu(capability):
    """torch.cuda for a GPU of this compute [capability], or none (None)."""
    sys.modules["torch"].cuda = types.SimpleNamespace(
        is_available=lambda: capability is not None,
        get_device_capability=lambda: capability,
        is_bf16_supported=lambda including_emulation=True: True,  # a T4 says yes, emulated
    )


# is_bf16_supported() counts emulation: a T4 says yes. Its trainer flags take
# that, but TRL's log-prob kernel failed in bf16 there (Kaggle v3 run 1): only
# Ampere (8.0) and later do it natively.
gpu((7, 5))
check("Kaggle's T4 has no native bf16", native_bf16(), False)
gpu((8, 0))
check("an A100 has it", native_bf16(), True)
gpu(None)
check("no GPU has none", native_bf16(), False)

# What trains on a T4 (v2, v3): the bf16 trainer flags, emulated, with TRL's
# plain fp32 log-prob matmul. fp16 flags made the grad scaler fail on the
# LoRA's bf16 gradients (Kaggle v3.1 run 1).
bf16_flags = ({"bf16": True, "fp16": False}, "bfloat16")
gpu((7, 5))
check("a T4 trains in bf16, the log-prob kernel in fp32", gpu_settings(), (bf16_flags, False))
gpu((8, 0))
check("an A100 trains in bf16 throughout", gpu_settings(), (bf16_flags, True))

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

kernel = types.ModuleType("trl.kernels.chunked_logprob")
kernel._MM_OUT_DTYPE = True
sys.modules["trl.kernels.chunked_logprob"] = kernel
fp32_logprobs(True)
check("with bf16 TRL's log-prob kernel is left as it is", kernel._MM_OUT_DTYPE, True)
# Without it, the kernel's backward got a bf16 gradient on fp16 weights and
# failed (Kaggle v2 runs 1-2); its plain fp32 path trained (run 3).
fp32_logprobs(False)
check("without bf16 it takes its plain fp32 path", kernel._MM_OUT_DTYPE, False)
del sys.modules["trl.kernels.chunked_logprob"]
check("a TRL without that kernel needs nothing", fp32_logprobs(False), None)

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

# Token ids: 7 opens a message, 8 is "assistant\n", 4 "user\n", 9 closes a message.
system, user, tool = [7, 5, 6, 9], [7, 4, 3, 9], [7, 4, 30, 9]
ids = system + user + [7, 8, 20, 21, 9] + tool + [7, 8, 22, 9]
_ = -100
check(
    "only the assistant's tokens are learned, through its closing token (#373)",
    assistant_labels(ids, start=[7, 8], end=9),
    [_] * 8 + [_, _, 20, 21, 9] + [_] * 4 + [_, _, 22, 9],
)
check("a turn with no assistant reply learns nothing", assistant_labels(system + user, start=[7, 8], end=9), [_] * 8)


class Shipped:
    def __init__(self, stdout):
        self.stdout = stdout


finetune.subprocess.run = lambda *a, **k: Shipped("# no model line here\n")
try:
    modelfile(".", "qwen3:4b-instruct-2507-q4_K_M")
    check("a Modelfile without FROM is refused", "no error", "ValueError")
except ValueError as error:
    check("a Modelfile without FROM says what it expected", "FROM" in str(error), True)

try:
    main(["only-a-base-dir"])
    check("too few paths stop with a usage message", "ran", "usage")
except SystemExit as stop:
    check("too few paths stop with a usage message", str(stop).startswith("usage: python tool/train/finetune.py"), True)

sys.exit(1 if failures else 0)
