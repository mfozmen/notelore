# On-device model eval (#227)

Notelore should run on a free model on the user's device, with no server of our own. Paid plans and keys stay options. This page records how small open models do on the eval set (`eval/cases.json`, run with `notelore_dev eval`), so the default model is chosen by measurement.

## Baseline, 2026-10-18 (#326)

Setup: 38 cases (EN and TR) through the Ollama provider, with `num_ctx` 16384 and `think: false` (#336). Hardware: an RTX 4070 laptop (8 GB), Ollama 0.40.5, Q4 models as Ollama ships them. A case passes only if the right tools were called, only the expected notes changed, they hold the expected facts, and the answer has the expected facts.

| Model | All | Questions | Collection notes | Filing | Decisions | Todos (add / done) | Median time per case |
|---|---|---|---|---|---|---|---|
| qwen3:4b | **26/38 (68%)** | 10/10 | 4/9 | 2/4 | 2/4 | 1/2 · 0/2 | 52 s |
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
- **Below 4B, tool use falls apart:** the models skip the write, loop on `create_note`, or answer without tools.
- **Next:**
  - run `qwen3:4b-instruct-2507` (non-thinking), FunctionGemma 270M and Gemma 3n through a runtime that supports their tool format;
  - add a hosted model as the ceiling;
  - fine-tune the best one (#327) on the failing kinds: collection notes, todo completion and note language.
