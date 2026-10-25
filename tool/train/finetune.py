"""QLoRA fine-tune of Notelore's on-device model on distilled turns (#327).

Trains a LoRA on the base model (4-bit, so it fits an 8 GB GPU) from the JSONL
that `notelore_dev distill` writes (only turns the eval scorer passed), then
merges it into full weights, then into a Q4_K_M GGUF for Ollama:

    python tool/train/finetune.py <base dir> <train.jsonl> <out dir> [--epochs=3] [--assistant-only]
    python <llama.cpp>/convert_hf_to_gguf.py <out dir>/merged --outtype bf16 \\
        --outfile <out dir>/model-bf16.gguf
    llama-quantize <out dir>/model-bf16.gguf <out dir>/model-q4_K_M.gguf Q4_K_M
    ollama create notelore-qwen3-4b -f <out dir>/Modelfile

Ollama on Windows cannot import or quantize safetensors (that path needs its
MLX runtime), hence llama.cpp's converter (it needs the `gguf` and
`sentencepiece` packages) and its prebuilt `llama-quantize`. The Modelfile
takes its chat template and parameters from the base model as Ollama ships it
(`--ollama-base`, qwen3:4b-instruct-2507-q4_K_M by default), so tool calls
are read the same way.

A tenth of the turns is held out (the same tenth every run). The validation
loss on it is logged with the train loss every 5 steps, the LoRA saved is the
checkpoint where it was lowest, and three evaluations without a better one end
the run, so `--epochs` is a ceiling.

`--assistant-only` puts the loss on the assistant's tokens alone (about 7% of
a turn), not on the system prompt, tool schemas and tool results it would
otherwise also learn to predict. v1 and v2 trained without it; v3 uses it.

Needs torch with CUDA, transformers, peft, trl, bitsandbytes and datasets (a
venv under .dev-home/train is fine). Stop running Ollama models first, so the
GPU is free. Nothing here ships in the app.
"""

import importlib
import json
import random
import subprocess
import sys
from pathlib import Path

import torch
from datasets import Dataset
from peft import LoraConfig, PeftModel
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    EarlyStoppingCallback,
)
from trl import SFTConfig, SFTTrainer


def clean(message):
    """An assistant message without the teacher's reasoning: a thinking model
    leaks it into the text, ending with </think>. The student learns only the
    calls and the answer, so it stays fast and never shows its reasoning."""
    if message.get("role") != "assistant":
        return message
    text = message.get("content") or ""
    if "</think>" in text:
        text = text.rsplit("</think>", 1)[1]
    elif message.get("tool_calls"):
        text = ""
    return {**message, "content": text.strip()}


def texts(tokenizer, data):
    """Each kept turn rendered with the model's own chat template, tools included."""
    lines = Path(data).read_text(encoding="utf-8").splitlines()
    rows = [json.loads(line) for line in lines if line.strip()]
    return [
        tokenizer.apply_chat_template(
            [clean(m) for m in r["messages"]], tools=r["tools"], tokenize=False
        )
        for r in rows
    ]


def assistant_labels(ids, start, end):
    """Labels for one rendered turn: the assistant's tokens (its replies and
    tool calls, through its closing `end`) are learned. Everything else (the
    system prompt, tool schemas, user messages and tool results, about 2.6k of
    a turn's ~3k tokens) is context only, -100 (#373)."""
    labels, inside = [], False
    for i, token in enumerate(ids):
        labels.append(token if inside else -100)
        if inside and token == end:
            inside = False
        elif not inside and ids[max(0, i + 1 - len(start)) : i + 1] == start:
            inside = True
    return labels


def dataset(tokenizer, data, assistant_only):
    """The rows: rendered text (the loss covers every token, as v1 and v2
    trained), or with `assistant_only` token ids with assistant-only labels."""
    rendered = texts(tokenizer, data)
    if not assistant_only:
        return [{"text": text} for text in rendered]
    start = tokenizer("<|im_start|>assistant\n", add_special_tokens=False)["input_ids"]
    end = tokenizer.convert_tokens_to_ids("<|im_end|>")
    ids = [tokenizer(text, add_special_tokens=False)["input_ids"] for text in rendered]
    return [{"input_ids": i, "labels": assistant_labels(i, start, end)} for i in ids]


def split(rows, share=0.1, seed=0):
    """The rows to train on and the ones held out for the validation loss (#605):
    a [share] of them, at least one, the same ones on every run."""
    if len(rows) < 2:
        raise ValueError(f"need at least two turns to hold one out, got {len(rows)}")
    order = list(range(len(rows)))
    random.Random(seed).shuffle(order)
    held = set(order[: max(1, round(len(rows) * share))])
    return (
        [r for i, r in enumerate(rows) if i not in held],
        [r for i, r in enumerate(rows) if i in held],
    )


def trainer_args(out, epochs, flags):
    """The trainer's settings: evaluated and saved on the same steps, and the
    checkpoint with the best validation loss loaded at the end (early stopping
    needs that)."""
    return dict(
        output_dir=str(Path(out) / "lora"),
        num_train_epochs=epochs,
        per_device_train_batch_size=1,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=8,
        learning_rate=2e-4,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=5,
        eval_strategy="steps",
        eval_steps=5,
        save_strategy="steps",
        save_steps=5,
        save_total_limit=2,
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        **flags,
        gradient_checkpointing=True,
        max_length=6144,
        dataset_text_field="text",
        report_to=[],
    )


def losses(history):
    """The trainer's log as one line per step: its train and validation loss."""
    steps = {}
    for entry in history:
        for key, name in (("loss", "train"), ("eval_loss", "validation")):
            if key in entry:
                steps.setdefault(entry["step"], {})[name] = entry[key]
    return [
        f"step {step}: train {got.get('train', float('nan')):.3f}, "
        f"validation {got.get('validation', float('nan')):.3f}"
        for step, got in sorted(steps.items())
    ]


def native_bf16():
    """Whether the GPU computes in bf16 itself (Ampere, compute 8.0, and
    later). torch.cuda.is_bf16_supported() also counts emulation, so a T4 said
    yes and then failed in bf16 (Kaggle v3 run 1)."""
    return torch.cuda.is_available() and torch.cuda.get_device_capability()[0] >= 8


def gpu_settings():
    """The trainer's precision, and whether the GPU has bf16 natively. A T4
    trains with the bf16 flags (emulated): with fp16 ones the grad scaler fails
    on the LoRA's bf16 gradients (Kaggle v3.1 run 1). Only TRL's log-prob
    kernel needs native bf16, so it keys on that ([fp32_logprobs])."""
    return precision(torch.cuda.is_bf16_supported()), native_bf16()


def precision(bf16):
    """The trainer's mixed-precision flags and the compute dtype: bf16 where the
    GPU has it, fp16 on older ones such as Kaggle's T4."""
    return {"bf16": bf16, "fp16": not bf16}, (torch.bfloat16 if bf16 else torch.float16)


def fp32_logprobs(native):
    """On a GPU without native bf16, TRL's chunked log-prob kernel takes its
    plain fp32 matmul: its dtype-keeping one failed on a T4 (Kaggle v2 runs
    1-2; run 3 and v3 trained with this)."""
    if native:
        return
    try:
        kernel = importlib.import_module("trl.kernels.chunked_logprob")
    except ImportError:  # an older TRL, without that kernel
        return
    kernel._MM_OUT_DTYPE = False


def load(base, dtype):
    """The base model in 4 bits, its unquantized parts (embeddings, lm_head) in
    [dtype] too: left in the checkpoint's bf16, a GPU without bf16 fails."""
    return AutoModelForCausalLM.from_pretrained(
        base,
        dtype=dtype,
        quantization_config=BitsAndBytesConfig(
            load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_compute_dtype=dtype
        ),
        device_map="auto",
    )


def train(base, data, out, epochs, assistant_only=False):
    tokenizer = AutoTokenizer.from_pretrained(base)
    kept, held = split(dataset(tokenizer, data, assistant_only))
    print(f"{len(kept)} training turns, {len(held)} held out for the validation loss")
    (flags, dtype), native = gpu_settings()
    fp32_logprobs(native)
    model = load(base, dtype)
    trainer = SFTTrainer(
        model=model,
        train_dataset=Dataset.from_list(kept),
        eval_dataset=Dataset.from_list(held),
        processing_class=tokenizer,
        peft_config=LoraConfig(
            r=16,
            lora_alpha=32,
            lora_dropout=0.05,
            target_modules="all-linear",
            task_type="CAUSAL_LM",
        ),
        args=SFTConfig(**trainer_args(out, epochs, flags)),
        # Three evaluations without a better validation loss end the run.
        callbacks=[EarlyStoppingCallback(early_stopping_patience=3)],
    )
    trainer.train()
    print("\n".join(losses(trainer.state.log_history)))
    best = trainer.state.best_model_checkpoint
    print(f"best validation loss {trainer.state.best_metric} at {best}")
    trainer.save_model(str(Path(out) / "lora"))


def modelfile(out, ollama_base):
    """A Modelfile for the quantized GGUF, with the base model's template and
    parameters as Ollama ships them (everything after its FROM line)."""
    shipped = subprocess.run(
        ["ollama", "show", "--modelfile", ollama_base],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    if "\nFROM " not in shipped:
        raise ValueError(
            f"`ollama show --modelfile {ollama_base}` has no FROM line: {shipped[:200]!r}"
        )
    rest = shipped.split("\nFROM ", 1)[1].split("\n", 1)[1]
    (Path(out) / "Modelfile").write_text("FROM ./model-q4_K_M.gguf\n" + rest, encoding="utf-8")


def merge(base, out):
    """Full bf16 weights with the LoRA folded in."""
    model = AutoModelForCausalLM.from_pretrained(base, dtype=torch.bfloat16, device_map="cpu")
    model = PeftModel.from_pretrained(model, str(Path(out) / "lora")).merge_and_unload()
    merged = Path(out) / "merged"
    model.save_pretrained(merged, safe_serialization=True)
    AutoTokenizer.from_pretrained(base).save_pretrained(merged)


USAGE = (
    "usage: python tool/train/finetune.py <base dir> <train.jsonl> <out dir> "
    "[--epochs=3] [--ollama-base=qwen3:4b-instruct-2507-q4_K_M] [--assistant-only]"
)


def main(argv):
    paths = [a for a in argv if not a.startswith("--")]
    if len(paths) != 3:
        raise SystemExit(USAGE)
    base, data, out = paths

    def option(name, default):
        return next((a.split("=", 1)[1] for a in argv if a.startswith(f"--{name}=")), default)

    # Before hours of training: fails at once if Ollama lacks the base model.
    modelfile(out, option("ollama-base", "qwen3:4b-instruct-2507-q4_K_M"))
    train(base, data, out, int(option("epochs", "3")), "--assistant-only" in argv)
    torch.cuda.empty_cache()
    merge(base, out)
    print(f"merged -> {Path(out) / 'merged'}; next: convert and quantize it")


if __name__ == "__main__":
    main(sys.argv[1:])
