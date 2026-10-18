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

`--assistant-only` puts the loss on the assistant's tokens alone (about 7% of
a turn), not on the system prompt, tool schemas and tool results it would
otherwise also learn to predict. v1 and v2 trained without it; v3 uses it.

Needs torch with CUDA, transformers, peft, trl, bitsandbytes and datasets (a
venv under .dev-home/train is fine). Stop running Ollama models first, so the
GPU is free. Nothing here ships in the app.
"""

import json
import subprocess
import sys
from pathlib import Path

import torch
from datasets import Dataset
from peft import LoraConfig, PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
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
    """The training rows: rendered text (the loss covers every token, as v1 and
    v2 trained), or with `assistant_only` token ids with assistant-only labels."""
    rendered = texts(tokenizer, data)
    if not assistant_only:
        return Dataset.from_dict({"text": rendered})
    start = tokenizer("<|im_start|>assistant\n", add_special_tokens=False)["input_ids"]
    end = tokenizer.convert_tokens_to_ids("<|im_end|>")
    ids = [tokenizer(text, add_special_tokens=False)["input_ids"] for text in rendered]
    labels = [assistant_labels(i, start, end) for i in ids]
    return Dataset.from_dict({"input_ids": ids, "labels": labels})


def precision(bf16):
    """The trainer's mixed-precision flags and the compute dtype: bf16 where the
    GPU has it, fp16 on older ones such as Kaggle's T4."""
    return {"bf16": bf16, "fp16": not bf16}, (torch.bfloat16 if bf16 else torch.float16)


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
    rows = dataset(tokenizer, data, assistant_only)
    print(f"{len(rows)} training turns")
    flags, dtype = precision(torch.cuda.is_bf16_supported())
    model = load(base, dtype)
    trainer = SFTTrainer(
        model=model,
        train_dataset=rows,
        processing_class=tokenizer,
        peft_config=LoraConfig(
            r=16,
            lora_alpha=32,
            lora_dropout=0.05,
            target_modules="all-linear",
            task_type="CAUSAL_LM",
        ),
        args=SFTConfig(
            output_dir=str(Path(out) / "lora"),
            num_train_epochs=epochs,
            per_device_train_batch_size=1,
            gradient_accumulation_steps=8,
            learning_rate=2e-4,
            lr_scheduler_type="cosine",
            warmup_ratio=0.05,
            logging_steps=5,
            save_strategy="no",
            **flags,
            gradient_checkpointing=True,
            max_length=6144,
            dataset_text_field="text",
            report_to=[],
        ),
    )
    trainer.train()
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
