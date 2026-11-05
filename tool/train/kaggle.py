"""Train the on-device model's LoRA on Kaggle's free GPU (#327).

Kaggle gives a T4 (16 GB, no bf16) free for about 30 hours a week; our 8 GB
laptop GPU spills into shared memory. Only the training runs there. Distilling
the data, merging, quantizing and the eval stay local.

1. Make a private Kaggle dataset, e.g. "notelore-train", from two files:
   the training JSONL (`DATA` below, from `.dev-home/train/`) and this repo's
   `tool/train/finetune.py`.
2. A script kernel with GPU T4 (one is used), Internet on, the dataset as
   input, and the kernel's own output as input too (`kernel_sources` lists the
   kernel itself), so a run can go on from where the last session stopped.
3. Run it. A session stops itself after `HOURS`, saved (Kaggle ends one at
   12 hours); if the epoch is not done, run the kernel again and it resumes
   from that checkpoint on the same schedule. v7's 769 turns took 7.6 hours
   for one epoch, so about 1,500 turns need two sessions.
4. Download `/kaggle/working/lora.zip` (the best LoRA by validation loss) and
   unpack it to `.dev-home/train/<RUN>/lora`. Then, locally:

       python -c "import sys; sys.path.insert(0, 'tool/train'); import finetune as f; \\
           f.merge('.dev-home/train/base', '.dev-home/train/<RUN>'); \\
           f.modelfile('.dev-home/train/<RUN>', 'qwen3:4b-instruct-2507-q4_K_M')"

   and convert, quantize and import it as `finetune.py`'s docstring says.

The data is generated scenarios, no notes of the user's; still, keep the
Kaggle dataset private.
"""

import glob
import os
import shutil
import subprocess
import sys
import time

STARTED = time.monotonic()
# 11 of Kaggle's 12 hours: an evaluation (~30 min) may still run on the stopping step.
DATA, RUN, HOURS = "train-v8.jsonl", "v8", 11

os.environ["CUDA_VISIBLE_DEVICES"] = "0"  # one T4: the 4-bit model fits, and nothing is split
subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q",
     "transformers==5.4.0", "peft==0.21.2", "trl==1.16.0", "bitsandbytes", "datasets", "accelerate"],
    check=True,
)

from huggingface_hub import snapshot_download  # noqa: E402 (installed above)

base = snapshot_download("Qwen/Qwen3-4B-Instruct-2507", local_dir="/tmp/base")  # outside the saved output
data = glob.glob(f"/kaggle/input/**/{DATA}", recursive=True)[0]
sys.path.insert(0, os.path.dirname(glob.glob("/kaggle/input/**/finetune.py", recursive=True)[0]))
import finetune  # noqa: E402

out = f"/kaggle/working/{RUN}"
# The last session's checkpoints, from this kernel's own output.
earlier = glob.glob(f"/kaggle/input/**/{RUN}/lora/checkpoint-*", recursive=True)
for checkpoint in earlier:
    shutil.copytree(checkpoint, f"{out}/lora/{os.path.basename(checkpoint)}")
# One evaluation of ~150 held-out turns takes about half an hour on a T4.
finetune.train(base, data, out, epochs=1, assistant_only=True, eval_every=40,
               max_hours=HOURS - (time.monotonic() - STARTED) / 3600, resume=bool(earlier))
shutil.copytree(f"{out}/lora", "/tmp/best", ignore=shutil.ignore_patterns("checkpoint-*"))
print(shutil.make_archive("/kaggle/working/lora", "zip", "/tmp/best"))
