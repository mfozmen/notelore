"""Train the on-device model's LoRA on Kaggle's free GPU (#327).

Kaggle gives a T4 (16 GB, no bf16) free for about 30 hours a week; our 8 GB
laptop GPU spills into shared memory. Only the training runs there. Distilling
the data, merging, quantizing and the eval stay local.

1. Make a Kaggle dataset, e.g. "notelore-train", from two files:
   `.dev-home/train/train-v3.jsonl` and this repo's `tool/train/finetune.py`.
2. New notebook: Accelerator "GPU T4 x2" (one is used), Internet on, and add
   the dataset as input.
3. Paste this whole file into one cell and run it. It takes about an hour for
   ~250 turns over two epochs.
4. Download `/kaggle/working/lora.zip` (~130 MB) from the Output panel and
   unpack it to `.dev-home/train/v3/lora`. Then, locally:

       python -c "import sys; sys.path.insert(0, 'tool/train'); import finetune as f; \\
           f.merge('.dev-home/train/base', '.dev-home/train/v3'); \\
           f.modelfile('.dev-home/train/v3', 'qwen3:4b-instruct-2507-q4_K_M')"

   and convert, quantize and import it as `finetune.py`'s docstring says.

The data is the user's own generated scenarios, no notes of theirs; still,
keep the Kaggle dataset private.
"""

import glob
import os
import shutil
import subprocess
import sys

os.environ["CUDA_VISIBLE_DEVICES"] = "0"  # one T4: the 4-bit model fits, and nothing is split
subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q",
     "transformers==5.4.0", "peft==0.21.2", "trl==1.16.0", "bitsandbytes", "datasets", "accelerate"],
    check=True,
)

from huggingface_hub import snapshot_download  # noqa: E402 (installed above)

base = snapshot_download("Qwen/Qwen3-4B-Instruct-2507", local_dir="/tmp/base")  # outside the saved output
data = glob.glob("/kaggle/input/**/train-v3.jsonl", recursive=True)[0]
sys.path.insert(0, os.path.dirname(glob.glob("/kaggle/input/**/finetune.py", recursive=True)[0]))
import finetune  # noqa: E402

# v3: one epoch, the loss on the answer alone; v2 learned its 209 turns by heart.
finetune.train(base, data, "/kaggle/working/v3", epochs=1, assistant_only=True)
print(shutil.make_archive("/kaggle/working/lora", "zip", "/kaggle/working/v3/lora"))
