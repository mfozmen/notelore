# On-device model eval (#227)

Notelore should run on a free model on the user's device, with no server of our own. Paid plans and keys stay options. This page records how small open models do on the eval set (`eval/cases.json`, run with `notelore_dev eval`), so the default model is chosen by measurement.

## Baseline, 2026-10-18 (#326)

Setup: 38 cases (EN and TR) through the Ollama provider, with `num_ctx` 16384 and `think: false` (#336). Hardware: an RTX 4070 laptop (8 GB), Ollama 0.40.5, Q4 models as Ollama ships them. A case passes only if the right tools were called, only the expected notes changed, they hold the expected facts, and the answer has the expected facts.

| Model | All | Questions | Collection notes | Filing | Decisions | Todos (add / done) | Median time per case |
|---|---|---|---|---|---|---|---|
| qwen3:4b | **26/38 (68%)** | 10/10 | 4/9 | 2/4 | 2/4 | 1/2 · 0/2 | 52 s |
| qwen3-coder:30b (MoE, 3B active; teacher candidate) | 24/38 (63%) | 7/10 | 1/9 | 3/4 | 3/4 | 2/2 · 1/2 | 7.1 s |
| qwen3-vl:8b | 10/38 (26%) | 1/10 | 2/9 | 1/4 | 1/4 | 1/2 · 1/2 | 178 s |
| qwen3:4b-instruct-2507 (non-thinking) | 10/38 (26%) | 4/10 | 1/9 | 0/4 | 0/4 | 0/2 · 0/2 | 1.3 s |
| llama3.1:8b | 11/38 (29%) | 6/10 | 1/9 | 0/4 | 0/4 | 0/2 · 0/2 | 2.6 s |
| qwen3:1.7b | 10/38 (26%) | 5/10 | 0/9 | 2/4 | 0/4 | 0/2 · 0/2 | 0.7 s |
| phi4-mini | 4/38 (11%) | 1/10 | 0/9 | 0/4 | 0/4 | 0/2 · 0/2 | — |
| llama3.2:3b | 2/38 (5%) | 0/10 | 0/9 | 0/4 | 0/4 | 0/2 · 0/2 | — |
| gemma3:4b | not run | | | | | | Ollama's gemma3 has no tool calling |

Findings:

- **Qwen3 4B is the only usable baseline.**
  - It answers every question from the notes and handles new notes, archive, small talk and unclear requests.
  - It fails the cases a fine-tune targets:
    - it opens a note named after a book or film instead of adding to the collection note (the #293 mistake);
    - it does not complete todos;
    - it writes notes in the wrong language.
  - It is slow (52 s median). Ollama's `qwen3:4b` is the thinking variant, and with `think: false` it still writes long reasoning into the answer. A non-thinking instruct build is the next run.
- **Thinking buys the quality.** The non-thinking instruct build of the same 4B is 40 times faster (1.3 s) but drops to 26%. It skips writes, puts facts into new notes and answers questions without reading. This is the gap a fine-tune closes: teach the fast non-thinking model the right tool calls from a stronger teacher's correct turns (distillation, #327).
- **No local model is a clean teacher.** Qwen3 4B thinking (68%) and Qwen3-Coder 30B (63%) are the best, and every model fails collection notes, which points at the prompt as much as the model (#293). So the training data is filtered: the teacher plays generated turns, the eval's scorer keeps only the turns that pass, and only those train the student. A wrong teacher answer never reaches training.
- **Below 4B, tool use falls apart:** the models skip the write, loop on `create_note`, or answer without tools.
- **Next:**
  - run `qwen3:4b-instruct-2507` (non-thinking), FunctionGemma 270M and Gemma 3n through a runtime that supports their tool format;
  - add a hosted model as the ceiling;
  - fine-tune the best one (#327) on the failing kinds: collection notes, todo completion and note language.

## Fine-tune v1, 2026-10-18 (#327)

**Setup**
- Student: Qwen3-4B-Instruct-2507, trained with QLoRA (r=16, 3 epochs) by `tool/train/finetune.py`.
- Data: 120 turns that two teachers played on the generated scenarios (`tool/train/scenarios.py`, none from the eval set), kept only when the eval's scorer passed them. 66 came from qwen3:4b and 54 from qwen3-coder:30b.
- Served: merged, then converted to a Q4_K_M GGUF (2.5 GB) and run by Ollama.
- Eval: the same 38 cases, with the prompt that has the todo rule (#349). All three models were rerun on that prompt.

| Model | All | Questions | Collection notes | Filing | Decisions | Todos (add / done) | Median time per case |
|---|---|---|---|---|---|---|---|
| **notelore-qwen3-4b-v1** (fine-tuned) | **23/38 (61%)** | 8/10 | 3/9 | 3/4 | 3/4 | 1/2 · 0/2 | **2.1 s** |
| qwen3:4b-instruct-2507 (the untuned student) | 12/38 (32%) | 5/10 | 1/9 | 1/4 | 0/4 | 1/2 · 0/2 | 1.8 s |
| qwen3:4b, thinking (the teacher) | 26/38 (68%) | 9/10 | 5/9 | 2/4 | 1/4 | 2/2 · 1/2 | 68 s |

Findings:

- **Fine-tuning nearly doubles the student at the same speed.** v1 is 7 points behind the thinking teacher at about 32 times its speed. The goal is ≥70% at instruct speed.
- **v1 overfits.**
  - Training loss fell from 2.0 to 0.06.
  - It files most collection items into "Okumakta olduğum kitaplar", a note from its training data, whatever the item is.
  - The next run needs many more, more varied scenarios, fewer epochs and a held-out split.
- **No todo-done yet:** the training data had almost no completed-todo turns. With the #349 rule the teacher now ticks one of the two cases, so v2's data can have them.
- **Slug case:** two of v1's failures were the slug `Mopsos` for `mopsos.md`. On Windows that renamed the note; on Android it failed. The tools now find a note whatever the case (#367).
- **The run is slow because of memory, not length.**
  - Each training turn is 2.7–3.1k tokens, mostly the system prompt and the tool schemas.
  - 45 steps took about 5 h 20 min (about 7 min a step) at 7.9 of 8 GB. That points to spilling into shared memory.
- **Ollama on Windows** cannot import or quantize safetensors: that path needs its MLX runtime. The working route is llama.cpp's `convert_hf_to_gguf.py`, then `llama-quantize` to Q4_K_M, then `ollama create` with the template the base model ships with. `finetune.py`'s docstring has the steps.
